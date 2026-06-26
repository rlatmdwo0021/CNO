# Baccarat Game Engine (Prototype)

Server-authoritative baccarat engine for the social casino app. Pure game
logic — no framework, no DB — so the same rules run on the backend and can be
reused by clients. Built in TypeScript, runs on Node 22+ with no build step
(native type stripping) and no dependencies.

## Design principles
- **Server decides everything.** Cards come from an injected `CardSource`;
  results are computed here, never trusted from the client.
- **RNG is injectable.** `secureRng` (crypto) for production, `seededRng` for
  deterministic tests and a future "provably fair" mode.
- **Rules are exact.** Full Punto Banco third-card rules, verified statistically
  against the known 8-deck house edge.

## Layout
```
src/
  types.ts     Domain types (Card, Bet, RoundResult, ...)
  rng.ts       secureRng + seededRng (mulberry32)
  cards.ts     card/hand values, Shoe (8-deck, cut card, shuffle)
  engine.ts    playRound(), bankerShouldDraw(), settleBet(s)  <- the rules
  wallet.ts    WalletService interface (async) + InMemoryWallet
  sqliteWallet.ts  Durable wallet on node:sqlite (file-backed, transactional)
  pgWallet.ts  Durable wallet on Postgres (SELECT ... FOR UPDATE row locking)
  auth.ts      AuthService + AccountStore (token accounts, reconnect)
  sqliteAccounts.ts  Durable AccountStore on node:sqlite
  round.ts     Round state machine (betting->locked->settled) + Table
  gameLoop.ts  Timed loop: betting windows -> lock -> settle -> next (events)
  roadmap.ts   Bead plate, Big Road + 3 derived roads from round history
  protocol.ts  WebSocket message types + client-frame parsing
  server.ts    HTTP + WebSocket server wiring the loop to many clients
  testing.ts   ScriptedShoe for deterministic tests
  demo.ts      End-to-end demo: 2 players, full bet->settle loop, balances
public/
  index.html   Browser client (watch/bet; open several tabs for multi-client)
test/
  engine.test.ts    13 tests (values, naturals, third-card table, payouts)
  walletContract.ts  shared WalletService spec (run by the files below)
  wallet.test.ts     contract vs InMemoryWallet
  sqliteWallet.test.ts  contract vs SQLite + survives-restart test
  pgWallet.test.ts   contract vs Postgres (skipped unless DATABASE_URL set)
  auth.test.ts       7 tests (register, reconnect, impersonation, hashing)
  round.test.ts     11 tests (escrow, push, multi-player, phase guards)
  gameLoop.test.ts   4 tests (timed phases via mock timers, auto-advance)
  roadmap.test.ts   17 tests (bead, streaks, dragon tail, ties, derived roads)
```

## Roadmaps
Built from round history (`roadmap.ts`), pushed to clients in every `welcome`
and `settled` message and rendered live:
- **Bead Plate** — one cell per round, column-major; ties get their own cell.
- **Big Road** — P/B streaks run down a column; a different result starts a new
  column; ties attach to the previous cell as a count; a streak hitting row 6
  turns right (dragon tail). Pair markers ride on the cell.

- **Derived roads** — Big Eye Boy (offset 1), Small Road (2), Cockroach (3).
  Each compares the Big Road's logical column lengths at its offset and emits
  red (regular) / blue (irregular), then lays that out as its own streak road.
  Perfect alternation → all red; equal-length repeats → red; mismatches → blue.

## Wallet persistence
The wallet is an async `WalletService`; pick the backend at startup:
```bash
npm start                         # SQLite at ./data/casino.db (default, durable)
WALLET=memory npm start           # volatile in-memory
WALLET_DB=/tmp/casino.db npm start  # SQLite at a custom path
DATABASE_URL=postgres://… npm start # Postgres (SELECT ... FOR UPDATE)
```
Balances and the ledger survive a restart (SQLite/Postgres): a returning player
keeps their coins, and the welcome bonus is granted once (idempotent `ref`).
All three backends pass the same `walletContract` spec, so they're swappable.

## Accounts & reconnect
No guests: a client `register`s once and the server mints a random token,
storing only its SHA-256 hash. The client keeps the token (localStorage) and
`auth`s with it to reconnect as the same account — balance and history intact.
A playerId alone is not a credential, so players can't impersonate each other.
Accounts persist with the same backend as the wallet (SQLite by default).

Protocol: `register {name?}` / `auth {token}` → `session {playerId, name,
token?, balance, …}`; an unknown token returns `authError`. The "New account"
button forgets the token and registers fresh (handy for multi-player demos).

## Run the live table
```bash
npm start                       # http://localhost:8080
PORT=3000 BETTING_MS=5000 npm start   # override port / timings
```
Each browser registers an account (+1000 welcome coins) and reconnects with its
saved token; use "New account" in a second tab to play as another player. Bets
land during the shared betting window; everyone sees the same deal and result
in sync. Architecture stays layered:

```
browser tabs ──WebSocket──► server.ts ──► GameLoop ──► Table ──► Round ──► engine
                              (transport)   (timing)   (shoe+wallet)  (rules)
```
The loop is transport-agnostic (emits events, exposes placeBet); the server
only translates events↔frames. Game and coin logic never touch the socket.

## Round lifecycle
```
                 placeBet (debits stake)        lock()              settle()
   [ betting ] ───────────────────────────► [ locked ] ──────► [ settled ]
        │  rejects bad / over-limit / broke bets      deals via engine,
        │  escrows stake immediately                  credits each payout
```
- **Bet placed** → stake debited at once (can't bet money you don't have).
- **Lock** → betting provably closed before any card is drawn.
- **Settle** → engine deals once; each bet's `payout` is credited back
  (win = stake+winnings, push = stake, loss = 0). Idempotent refs make
  retries safe; every move is in the wallet ledger.

## Commands
```bash
npm test        # run the test suite (node --test)
npm run demo    # deal 10 rounds from a seeded shoe
node src/demo.ts 50   # deal 50 rounds
```

## Payouts
| Bet | Pays | On tie |
|---|---|---|
| Player | 1:1 | push (stake returned) |
| Banker | 1:1 − 5% commission (0.95) | push |
| Tie | 8:1 | win |
| Player Pair | 11:1 | — |
| Banker Pair | 11:1 | — |

## Validated house edge (2M rounds, secure RNG)
Player 1.23% · Banker 1.07% · Tie 14.20% — matches published 8-deck figures.

## Next steps
- Second game (slots / blackjack) reusing the wallet + round + loop layers
- Wrap engine + round in the backend API (NestJS/Go) — engine stays the source of truth
- Account hardening: token rotation/expiry, rate limiting, display-name edits
