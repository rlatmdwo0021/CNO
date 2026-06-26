// Wire protocol between the WebSocket server and clients.
// Messages are JSON with a `t` (type) discriminator.

import type { BetType } from './types.ts';
import type { BeadCell, BigRoadCell, DerivedRoad } from './roadmap.ts';

export interface RoadmapView {
  bead: { cols: number; cells: BeadCell[] };
  big: { cols: number; cells: BigRoadCell[]; leadingTies: number };
  bigEye: DerivedRoad;
  small: DerivedRoad;
  cockroach: DerivedRoad;
}

// ---- client -> server ----
export interface RegisterMsg {
  t: 'register';
  username: string;
  password: string;
  name?: string;
}
export interface LoginMsg {
  t: 'login';
  username: string;
  password: string;
}
/** Reconnect within the same run using the in-memory session token. */
export interface AuthMsg {
  t: 'auth';
  token: string;
}
export interface BetMsg {
  t: 'bet';
  betType: BetType;
  amount: number;
}
export type ClientMsg = RegisterMsg | LoginMsg | AuthMsg | BetMsg;

// ---- server -> client ----
export interface CardView {
  rank: string;
  suit: string;
}
export interface HandView {
  cards: CardView[];
  value: number;
}
export interface SettledBetView {
  playerId: string;
  betType: BetType;
  amount: number;
  won: boolean | undefined; // undefined = push
  net: number;
}

export interface SessionMsg {
  t: 'session';
  playerId: string;
  name: string;
  /** Present only right after register — the client persists it for reconnect. */
  token?: string;
  balance: number;
  limits: { minBet: number; maxBet: number };
  phase: string;
  roundId?: string;
  endsAt?: number; // betting window end (epoch ms), if currently betting
  roadmap: RoadmapView; // current roads so late joiners see history
}
export interface AuthErrorMsg {
  t: 'authError';
  message: string;
}
export interface OpenMsg {
  t: 'open';
  roundId: string;
  endsAt: number;
}
export interface BetBroadcastMsg {
  t: 'bet';
  roundId: string;
  playerId: string;
  betType: BetType;
  amount: number;
}
export interface BetAckMsg {
  t: 'betAck';
  ok: boolean;
  betId?: string;
  balance?: number;
  error?: string;
}
export interface LockedMsg {
  t: 'locked';
  roundId: string;
}
export interface SettledMsg {
  t: 'settled';
  roundId: string;
  outcome: 'player' | 'banker' | 'tie';
  player: HandView;
  banker: HandView;
  settled: SettledBetView[];
  roadmap: RoadmapView; // roads updated with this round
}
/** Per-recipient balance update (sent privately after settlement). */
export interface BalanceMsg {
  t: 'balance';
  balance: number;
}
export interface ErrorMsg {
  t: 'error';
  message: string;
}
export type ServerMsg =
  | SessionMsg
  | AuthErrorMsg
  | OpenMsg
  | BetBroadcastMsg
  | BetAckMsg
  | LockedMsg
  | SettledMsg
  | BalanceMsg
  | ErrorMsg;

/** Parse an incoming client frame; returns null if malformed. */
export function parseClientMsg(raw: string): ClientMsg | null {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof data !== 'object' || data === null) return null;
  const msg = data as Record<string, unknown>;
  if (msg.t === 'register') {
    if (typeof msg.username !== 'string' || typeof msg.password !== 'string') return null;
    return {
      t: 'register',
      username: msg.username,
      password: msg.password,
      name: typeof msg.name === 'string' ? msg.name : undefined,
    };
  }
  if (msg.t === 'login') {
    if (typeof msg.username !== 'string' || typeof msg.password !== 'string') return null;
    return { t: 'login', username: msg.username, password: msg.password };
  }
  if (msg.t === 'auth') {
    if (typeof msg.token !== 'string') return null;
    return { t: 'auth', token: msg.token };
  }
  if (msg.t === 'bet') {
    if (typeof msg.betType !== 'string' || typeof msg.amount !== 'number') return null;
    return { t: 'bet', betType: msg.betType as BetType, amount: msg.amount };
  }
  return null;
}
