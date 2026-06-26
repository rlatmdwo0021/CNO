// WebSocket server: wires the GameLoop to many clients and serves a browser
// client so you can watch multi-client sync live. Run: npm start
//
// Responsibilities (thin): translate loop events -> broadcasts, and client
// messages -> loop calls. All game/coin logic stays in the layers below.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { mkdirSync } from 'node:fs';
import { networkInterfaces } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join, normalize, extname } from 'node:path';
import { WebSocketServer, type WebSocket } from 'ws';

import { Shoe } from './cards.ts';
import { secureRng } from './rng.ts';
import { InMemoryWallet, type WalletService } from './wallet.ts';
import { SqliteWallet } from './sqliteWallet.ts';
import { AuthService, InMemoryAccountStore, type AccountStore } from './auth.ts';
import { SqliteAccountStore } from './sqliteAccounts.ts';
import { Table, type TableLimits } from './round.ts';
import { GameLoop } from './gameLoop.ts';
import { parseClientMsg, type ServerMsg, type RoadmapView } from './protocol.ts';
import { beadPlate, bigRoad, derivedRoads, summarize, type RoundSummary } from './roadmap.ts';
import type { Card } from './types.ts';

const PORT = Number(process.env.PORT ?? 8080);
const WELCOME_COINS = 1000;
const LIMITS: TableLimits = { minBet: 10, maxBet: 500 };

// ---- wallet selection ----
// WALLET=memory  -> volatile (default if you want a clean slate each run)
// WALLET=sqlite  -> durable file at WALLET_DB (default ./data/casino.db)
// DATABASE_URL set -> Postgres (loaded lazily; see PgWallet)
const DB_SSL = process.env.DATABASE_SSL === 'true';

async function createWallet(): Promise<WalletService> {
  if (process.env.DATABASE_URL) {
    const { PgWallet } = await import('./pgWallet.ts');
    const pg = new PgWallet(process.env.DATABASE_URL, DB_SSL);
    await pg.init();
    console.log('Wallet: Postgres');
    return pg;
  }
  if ((process.env.WALLET ?? 'sqlite') === 'memory') {
    console.log('Wallet: in-memory (volatile)');
    return new InMemoryWallet();
  }
  const path = process.env.WALLET_DB ?? 'data/casino.db';
  mkdirSync(dirname(path), { recursive: true });
  console.log(`Wallet: SQLite (${path})`);
  return new SqliteWallet(path);
}

// Accounts use the same backend as the wallet.
async function createAccountStore(): Promise<AccountStore> {
  if (process.env.DATABASE_URL) {
    const { PgAccountStore } = await import('./pgAccounts.ts');
    const store = new PgAccountStore(process.env.DATABASE_URL, DB_SSL);
    await store.init();
    console.log('Accounts: Postgres');
    return store;
  }
  if ((process.env.WALLET ?? 'sqlite') === 'memory') return new InMemoryAccountStore();
  const path = process.env.ACCOUNTS_DB ?? process.env.WALLET_DB ?? 'data/casino.db';
  mkdirSync(dirname(path), { recursive: true });
  return new SqliteAccountStore(path);
}

// ---- game wiring ----
const wallet = await createWallet();
const auth = new AuthService(await createAccountStore());
const shoe = new Shoe(8, secureRng);
const table = new Table(shoe, wallet, LIMITS);
const loop = new GameLoop(table, {
  bettingMs: Number(process.env.BETTING_MS ?? 8000),
  settleDelayMs: Number(process.env.SETTLE_DELAY_MS ?? 1200),
  pauseMs: Number(process.env.PAUSE_MS ?? 4000),
});

// ---- connections ----
const clients = new Map<WebSocket, string>(); // socket -> playerId (authenticated)

const send = (ws: WebSocket, msg: ServerMsg) => {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
};
const broadcast = (msg: ServerMsg) => {
  for (const ws of clients.keys()) send(ws, msg);
};
const cardView = (cards: Card[]) => cards.map((c) => ({ rank: c.rank, suit: c.suit }));

// Round history feeds the roadmaps. Keep a rolling window for the display.
const HISTORY_WINDOW = 60;
const history: RoundSummary[] = [];
const buildRoadmap = (): RoadmapView => {
  const recent = history.slice(-HISTORY_WINDOW);
  const derived = derivedRoads(recent);
  return {
    bead: beadPlate(recent),
    big: bigRoad(recent),
    bigEye: derived.bigEye,
    small: derived.small,
    cockroach: derived.cockroach,
  };
};

// ---- loop events -> broadcasts ----
loop.on('open', ({ roundId, endsAt }) => broadcast({ t: 'open', roundId, endsAt }));
loop.on('locked', ({ roundId }) => broadcast({ t: 'locked', roundId }));
loop.on('bet', ({ roundId, placed }) =>
  broadcast({
    t: 'bet',
    roundId,
    playerId: placed.playerId,
    betType: placed.bet.type,
    amount: placed.bet.amount,
  }),
);
loop.on('settled', async (outcome) => {
  history.push(summarize(outcome.result));
  broadcast({
    t: 'settled',
    roundId: outcome.roundId,
    outcome: outcome.result.outcome,
    player: { cards: cardView(outcome.result.player.cards), value: outcome.result.player.value },
    banker: { cards: cardView(outcome.result.banker.cards), value: outcome.result.banker.value },
    settled: outcome.settled.map((s) => ({
      playerId: s.playerId,
      betType: s.bet.type,
      amount: s.bet.amount,
      won: s.settlement.won,
      net: s.settlement.net,
    })),
    roadmap: buildRoadmap(),
  });
  // Private balance update to each connected player.
  for (const [ws, playerId] of clients) {
    send(ws, { t: 'balance', balance: await wallet.getBalance(playerId) });
  }
});

// ---- HTTP: serve the Flutter web client (app + WebSocket on one port) ----
// Serving the app here means phones only need ONE reachable port: open
// http://<pc-ip>:8080 and the app's socket targets that same origin.
const here = dirname(fileURLToPath(import.meta.url));
const webRoot = process.env.STATIC_DIR ?? join(here, '..', 'app', 'build', 'web');

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.ico': 'image/x-icon',
  '.bin': 'application/octet-stream',
};

const httpServer = createServer(async (req, res) => {
  let urlPath = decodeURIComponent((req.url ?? '/').split('?')[0]);
  // Liveness probe for the host platform (works even without the web build).
  if (urlPath === '/healthz') {
    res.writeHead(200, { 'content-type': 'text/plain' }).end('ok');
    return;
  }
  if (urlPath === '/') urlPath = '/index.html';
  const filePath = normalize(join(webRoot, urlPath));
  if (!filePath.startsWith(webRoot)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  try {
    const body = await readFile(filePath);
    res.writeHead(200, { 'content-type': MIME[extname(filePath)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    // SPA fallback (or a clear hint if the app hasn't been built yet).
    try {
      const body = await readFile(join(webRoot, 'index.html'));
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(body);
    } catch {
      res
        .writeHead(503, { 'content-type': 'text/plain; charset=utf-8' })
        .end('Flutter web build not found. Run: cd app && flutter build web');
    }
  }
});

// ---- WebSocket ----
const wss = new WebSocketServer({ server: httpServer });

// Bind a socket to a player and send the opening session snapshot.
// token is included only on registration so the client can store it.
async function startSession(ws: WebSocket, playerId: string, name: string, token?: string) {
  clients.set(ws, playerId);
  // Welcome coins once per account (idempotent on reconnect / restart).
  await wallet.credit(playerId, WELCOME_COINS, `welcome:${playerId}`, 'welcome bonus');
  send(ws, {
    t: 'session',
    playerId,
    name,
    token,
    balance: await wallet.getBalance(playerId),
    limits: { minBet: LIMITS.minBet, maxBet: LIMITS.maxBet },
    phase: loop.phase,
    roundId: loop.roundId,
    endsAt: loop.phaseEndsAt || undefined,
    roadmap: buildRoadmap(),
  });
}

wss.on('connection', (ws) => {
  ws.on('message', async (data) => {
    const msg = parseClientMsg(data.toString());
    if (!msg) return send(ws, { t: 'error', message: 'malformed message' });

    if (msg.t === 'register') {
      const session = await auth.register(msg.name);
      await startSession(ws, session.playerId, session.name, session.token);
      return;
    }

    if (msg.t === 'auth') {
      const account = await auth.authenticate(msg.token);
      if (!account) return send(ws, { t: 'authError', message: 'invalid or expired token' });
      await startSession(ws, account.playerId, account.name);
      return;
    }

    if (msg.t === 'bet') {
      const playerId = clients.get(ws);
      if (!playerId) return send(ws, { t: 'error', message: 'authenticate first' });
      const result = await loop.placeBet(playerId, { type: msg.betType, amount: msg.amount });
      send(ws, {
        t: 'betAck',
        ok: result.ok,
        betId: result.betId,
        balance: result.balance,
        error: result.error,
      });
      return;
    }
  });

  ws.on('close', () => clients.delete(ws));
});

// Bind on all interfaces so phones on the same Wi-Fi can reach it.
httpServer.listen(PORT, '0.0.0.0', () => {
  loop.start();
  const nets = networkInterfaces();
  const lan = Object.values(nets)
    .flat()
    .find((n) => n && n.family === 'IPv4' && !n.internal)?.address;
  console.log(`Baccarat live (app + WebSocket):`);
  console.log(`  this PC : http://localhost:${PORT}`);
  if (lan) console.log(`  phone   : http://${lan}:${PORT}  (same Wi-Fi)`);
});
