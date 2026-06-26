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
import { AuthService, AuthError, InMemoryAccountStore, type AccountStore } from './auth.ts';
import { SqliteAccountStore } from './sqliteAccounts.ts';
import { Table, type TableLimits } from './round.ts';
import { GameLoop } from './gameLoop.ts';
import { parseClientMsg, type ServerMsg, type RoadmapView, type GameInfo } from './protocol.ts';
import { beadPlate, bigRoad, derivedRoads, summarize, type RoundSummary } from './roadmap.ts';
import type { Card } from './types.ts';

const PORT = Number(process.env.PORT ?? 8080);
const WELCOME_COINS = 1000;

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

// ---- games & rooms ----
const wallet = await createWallet();
const auth = new AuthService(await createAccountStore());

const GAMES: GameInfo[] = [
  { id: 'baccarat', name: '바카라', status: 'live' },
  { id: 'slots', name: '슬롯', status: 'soon' },
  { id: 'roulette', name: '룰렛', status: 'soon' },
];
const GRADE_PLACEHOLDER = '브론즈';

// Fixed preset rooms by betting limit. Each is an independent table/loop/shoe.
const ROOM_CONFIGS = [
  { id: 'beginner', name: '초보', minBet: 10, maxBet: 500 },
  { id: 'standard', name: '일반', minBet: 100, maxBet: 5000 },
  { id: 'vip', name: 'VIP', minBet: 1000, maxBet: 50000 },
];
const TIMING = {
  bettingMs: Number(process.env.BETTING_MS ?? 8000),
  settleDelayMs: Number(process.env.SETTLE_DELAY_MS ?? 1200),
  pauseMs: Number(process.env.PAUSE_MS ?? 4000),
};

interface Room {
  id: string;
  name: string;
  gameId: string;
  limits: TableLimits;
  loop: GameLoop;
  history: RoundSummary[];
  subscribers: Set<WebSocket>;
}

// ---- connections ----
const clients = new Map<WebSocket, string>(); // socket -> playerId (authenticated)
const subscriptions = new Map<WebSocket, string>(); // socket -> current roomId

const send = (ws: WebSocket, msg: ServerMsg) => {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
};
const cardView = (cards: Card[]) => cards.map((c) => ({ rank: c.rank, suit: c.suit }));

const broadcastRoom = (room: Room, msg: ServerMsg) => {
  for (const ws of room.subscribers) send(ws, msg);
};
const roomPlayers = (room: Room): number => {
  const ids = new Set<string>();
  for (const ws of room.subscribers) {
    const p = clients.get(ws);
    if (p) ids.add(p);
  }
  return ids.size;
};

// Each room derives its roadmaps from its own rolling round history.
const HISTORY_WINDOW = 60;
const buildRoadmap = (history: RoundSummary[]): RoadmapView => {
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

// Wire one room's loop events to room-scoped broadcasts.
function wireRoom(room: Room): void {
  room.loop.on('open', ({ roundId, endsAt }) =>
    broadcastRoom(room, { t: 'open', roomId: room.id, roundId, endsAt }),
  );
  room.loop.on('locked', ({ roundId }) =>
    broadcastRoom(room, { t: 'locked', roomId: room.id, roundId }),
  );
  room.loop.on('bet', ({ roundId, placed }) =>
    broadcastRoom(room, {
      t: 'bet',
      roomId: room.id,
      roundId,
      playerId: placed.playerId,
      betType: placed.bet.type,
      amount: placed.bet.amount,
    }),
  );
  room.loop.on('settled', async (outcome) => {
    room.history.push(summarize(outcome.result));
    if (room.history.length > HISTORY_WINDOW) room.history.shift();
    broadcastRoom(room, {
      t: 'settled',
      roomId: room.id,
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
      roadmap: buildRoadmap(room.history),
    });
    for (const ws of room.subscribers) {
      const playerId = clients.get(ws);
      if (playerId) send(ws, { t: 'balance', gold: await wallet.getBalance(playerId), diamond: 0 });
    }
  });
}

const rooms = new Map<string, Room>();
for (const cfg of ROOM_CONFIGS) {
  const limits: TableLimits = { minBet: cfg.minBet, maxBet: cfg.maxBet };
  const loop = new GameLoop(new Table(new Shoe(8, secureRng), wallet, limits), TIMING);
  const room: Room = {
    id: cfg.id,
    name: cfg.name,
    gameId: 'baccarat',
    limits,
    loop,
    history: [],
    subscribers: new Set(),
  };
  rooms.set(cfg.id, room);
  wireRoom(room);
}

function leaveCurrentRoom(ws: WebSocket): void {
  const roomId = subscriptions.get(ws);
  if (!roomId) return;
  rooms.get(roomId)?.subscribers.delete(ws);
  subscriptions.delete(ws);
}

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
    grade: GRADE_PLACEHOLDER,
    gold: await wallet.getBalance(playerId),
    diamond: 0,
    games: GAMES,
  });
}

wss.on('connection', (ws) => {
  ws.on('message', async (data) => {
    const msg = parseClientMsg(data.toString());
    if (!msg) return send(ws, { t: 'error', message: 'malformed message' });

    if (msg.t === 'register') {
      try {
        const session = await auth.register(msg.username, msg.password, msg.name);
        await startSession(ws, session.playerId, session.name, session.token);
      } catch (err) {
        send(ws, { t: 'authError', message: err instanceof AuthError ? err.message : '회원가입에 실패했습니다.' });
      }
      return;
    }

    if (msg.t === 'login') {
      try {
        const session = await auth.login(msg.username, msg.password);
        await startSession(ws, session.playerId, session.name, session.token);
      } catch (err) {
        send(ws, { t: 'authError', message: err instanceof AuthError ? err.message : '로그인에 실패했습니다.' });
      }
      return;
    }

    if (msg.t === 'auth') {
      const account = await auth.authenticate(msg.token);
      if (!account) {
        return send(ws, { t: 'authError', message: '세션이 만료되었습니다. 다시 로그인해주세요.' });
      }
      await startSession(ws, account.playerId, account.name); // reconnect: keep existing token
      return;
    }

    if (msg.t === 'listRooms') {
      if (!clients.get(ws)) return send(ws, { t: 'error', message: '먼저 로그인하세요.' });
      send(ws, {
        t: 'rooms',
        gameId: msg.gameId,
        rooms: [...rooms.values()]
          .filter((r) => r.gameId === msg.gameId)
          .map((r) => ({
            id: r.id,
            name: r.name,
            minBet: r.limits.minBet,
            maxBet: r.limits.maxBet,
            players: roomPlayers(r),
            phase: r.loop.phase,
          })),
      });
      return;
    }

    if (msg.t === 'joinRoom') {
      if (!clients.get(ws)) return send(ws, { t: 'error', message: '먼저 로그인하세요.' });
      const room = rooms.get(msg.roomId);
      if (!room) return send(ws, { t: 'error', message: '존재하지 않는 방입니다.' });
      leaveCurrentRoom(ws);
      room.subscribers.add(ws);
      subscriptions.set(ws, room.id);
      send(ws, {
        t: 'roomJoined',
        roomId: room.id,
        name: room.name,
        minBet: room.limits.minBet,
        maxBet: room.limits.maxBet,
        phase: room.loop.phase,
        roundId: room.loop.roundId,
        endsAt: room.loop.phaseEndsAt || undefined,
        roadmap: buildRoadmap(room.history),
      });
      return;
    }

    if (msg.t === 'leaveRoom') {
      leaveCurrentRoom(ws);
      return;
    }

    if (msg.t === 'bet') {
      const playerId = clients.get(ws);
      if (!playerId) return send(ws, { t: 'error', message: '먼저 로그인하세요.' });
      const roomId = subscriptions.get(ws);
      const room = roomId ? rooms.get(roomId) : undefined;
      if (!room) return send(ws, { t: 'betAck', ok: false, error: '방에 입장한 뒤 베팅하세요.' });
      const result = await room.loop.placeBet(playerId, { type: msg.betType, amount: msg.amount });
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

  ws.on('close', () => {
    leaveCurrentRoom(ws);
    clients.delete(ws);
  });
});

// Bind on all interfaces so phones on the same Wi-Fi can reach it.
httpServer.listen(PORT, '0.0.0.0', () => {
  for (const room of rooms.values()) room.loop.start();
  const nets = networkInterfaces();
  const lan = Object.values(nets)
    .flat()
    .find((n) => n && n.family === 'IPv4' && !n.internal)?.address;
  console.log(`Baccarat live (app + WebSocket):`);
  console.log(`  this PC : http://localhost:${PORT}`);
  if (lan) console.log(`  phone   : http://${lan}:${PORT}  (same Wi-Fi)`);
});
