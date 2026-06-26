// Timed game loop that drives a Table through real betting windows.
//
// Transport-agnostic on purpose: it emits events and exposes placeBet(), and
// knows nothing about WebSockets. The server layer subscribes and broadcasts.
// Timing uses the global setTimeout/Date so tests can drive it deterministically
// with node:test mock timers.
//
// Per-round timeline:
//   open ──(bettingMs)──► lock ──(settleDelayMs)──► settle ──(pauseMs)──► open ...

import { EventEmitter } from 'node:events';
import type { Bet } from './types.ts';
import type { Round, Table, RoundOutcome, PlacedBet } from './round.ts';

export type LoopPhase = 'idle' | 'betting' | 'locked' | 'settled';

export interface GameLoopConfig {
  /** Betting window length in ms. */
  bettingMs: number;
  /** Suspense gap between locking bets and revealing cards. */
  settleDelayMs: number;
  /** How long the result stays up before the next round opens. */
  pauseMs: number;
}

export interface BetPlaceResult {
  ok: boolean;
  betId?: string;
  balance?: number;
  error?: string;
}

/**
 * Events (payloads):
 *   'open'    { roundId, endsAt, bettingMs }
 *   'bet'     { roundId, placed: PlacedBet, balance }
 *   'locked'  { roundId }
 *   'settled' RoundOutcome
 *   'stopped' {}
 */
export class GameLoop extends EventEmitter {
  private readonly table: Table;
  private readonly config: GameLoopConfig;
  private running = false;
  private current: Round | undefined;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private _phase: LoopPhase = 'idle';
  private _phaseEndsAt = 0;

  constructor(table: Table, config: GameLoopConfig) {
    super();
    this.table = table;
    this.config = config;
  }

  get phase(): LoopPhase {
    return this._phase;
  }

  /** When the current betting window ends (epoch ms); 0 if not betting. */
  get phaseEndsAt(): number {
    return this._phase === 'betting' ? this._phaseEndsAt : 0;
  }

  get roundId(): string | undefined {
    return this.current?.id;
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.openRound();
  }

  stop(): void {
    this.running = false;
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this._phase = 'idle';
    this.emit('stopped', {});
  }

  /**
   * Place a bet for the active round. Only valid during the betting window.
   * Never throws — returns a result so the server can ack the bettor and, on
   * success, the 'bet' event lets it broadcast to everyone.
   */
  async placeBet(playerId: string, bet: Bet): Promise<BetPlaceResult> {
    const round = this.current;
    if (this._phase !== 'betting' || !round) {
      return { ok: false, error: 'betting is closed' };
    }
    try {
      const placed = await round.placeBet(playerId, bet);
      const balance = await this.table.walletService.getBalance(placed.playerId);
      this.emit('bet', { roundId: round.id, placed, balance });
      return { ok: true, betId: placed.betId, balance };
    } catch (err) {
      return { ok: false, error: (err as Error).message };
    }
  }

  /**
   * Cancel and refund all of a player's bets in the open round. Emits
   * 'betsCleared' so the server can broadcast the reversal; never throws.
   */
  async clearBets(
    playerId: string,
  ): Promise<{ ok: boolean; byType?: Record<string, number>; balance?: number; error?: string }> {
    const round = this.current;
    if (this._phase !== 'betting' || !round) {
      return { ok: false, error: 'betting is closed' };
    }
    try {
      const res = await round.clearBets(playerId);
      this.emit('betsCleared', { roundId: round.id, playerId, byType: res.byType, balance: res.balance });
      return { ok: true, byType: res.byType, balance: res.balance };
    } catch (err) {
      return { ok: false, error: (err as Error).message };
    }
  }

  private openRound(): void {
    if (!this.running) return;
    this.current = this.table.startRound();
    this._phase = 'betting';
    this._phaseEndsAt = Date.now() + this.config.bettingMs;
    this.emit('open', {
      roundId: this.current.id,
      endsAt: this._phaseEndsAt,
      bettingMs: this.config.bettingMs,
    });
    this.timer = setTimeout(() => this.lockRound(), this.config.bettingMs);
  }

  private lockRound(): void {
    if (!this.running || !this.current) return;
    this.current.lock();
    this._phase = 'locked';
    this.emit('locked', { roundId: this.current.id });
    this.timer = setTimeout(() => {
      this.revealRound().catch((err) => this.emit('error', err));
    }, this.config.settleDelayMs);
  }

  private async revealRound(): Promise<void> {
    if (!this.running || !this.current) return;
    const outcome: RoundOutcome = await this.current.settle();
    if (!this.running) return; // stopped while settling
    this._phase = 'settled';
    this.emit('settled', outcome);
    this.timer = setTimeout(() => this.openRound(), this.config.pauseMs);
  }
}
