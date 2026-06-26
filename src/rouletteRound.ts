// Roulette round state machine: betting -> locked -> settled.
//
// Mirrors the baccarat Round (escrow on bet, refund on cancel, credit payouts on
// settle) but for roulette spots. Shaped so the existing GameLoop can drive it:
// same id/phase/placeBet/clearBets/lock/settle/getBets surface.

import { spin, settleSpot, getSpot, colorOf } from './rouletteEngine.ts';
import type { Pocket, Color, RouletteSettlement } from './rouletteEngine.ts';
import type { Rng } from './rng.ts';
import type { WalletService } from './wallet.ts';

export type RoulettePhase = 'betting' | 'locked' | 'settled';

export class InvalidPhaseError extends Error {
  constructor(action: string, phase: RoulettePhase) {
    super(`Cannot ${action} while round is '${phase}'`);
    this.name = 'InvalidPhaseError';
  }
}

export class BetValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BetValidationError';
  }
}

export interface RouletteBet {
  spotId: string;
  amount: number;
}

export interface RouletteLimits {
  minBet: number;
  maxBet: number;
}

export interface PlacedRouletteBet {
  betId: string;
  playerId: string;
  bet: RouletteBet;
}

export interface SettledRouletteBet extends PlacedRouletteBet {
  settlement: RouletteSettlement;
  balanceAfter: number;
}

export interface RouletteOutcome {
  roundId: string;
  winning: Pocket;
  color: Color;
  settled: SettledRouletteBet[];
}

export class RouletteRound {
  readonly id: string;
  private _phase: RoulettePhase = 'betting';
  private readonly bets: PlacedRouletteBet[] = [];
  private seq = 0;
  private _outcome: RouletteOutcome | undefined;

  private readonly rng: Rng;
  private readonly wallet: WalletService;
  private readonly limits: RouletteLimits;

  constructor(id: string, rng: Rng, wallet: WalletService, limits: RouletteLimits) {
    this.id = id;
    this.rng = rng;
    this.wallet = wallet;
    this.limits = limits;
  }

  get phase(): RoulettePhase {
    return this._phase;
  }

  get outcome(): RouletteOutcome | undefined {
    return this._outcome;
  }

  getBets(): readonly PlacedRouletteBet[] {
    return this.bets;
  }

  async placeBet(playerId: string, bet: RouletteBet): Promise<PlacedRouletteBet> {
    if (this._phase !== 'betting') throw new InvalidPhaseError('place a bet', this._phase);
    this.validate(playerId, bet);
    const betId = `${this.id}#${this.seq++}`;
    await this.wallet.debit(playerId, bet.amount, `bet:${betId}`, `bet ${bet.spotId} @ ${this.id}`);
    const placed: PlacedRouletteBet = { betId, playerId, bet };
    this.bets.push(placed);
    return placed;
  }

  async clearBets(playerId: string): Promise<{ byType: Record<string, number>; balance: number }> {
    if (this._phase !== 'betting') throw new InvalidPhaseError('clear bets', this._phase);
    const byType: Record<string, number> = {};
    let refund = 0;
    for (const pb of this.bets) {
      if (pb.playerId !== playerId) continue;
      byType[pb.bet.spotId] = (byType[pb.bet.spotId] ?? 0) + pb.bet.amount;
      refund += pb.bet.amount;
    }
    for (let i = this.bets.length - 1; i >= 0; i--) {
      if (this.bets[i].playerId === playerId) this.bets.splice(i, 1);
    }
    let balance = await this.wallet.getBalance(playerId);
    if (refund > 0) {
      const tx = await this.wallet.credit(
        playerId,
        refund,
        `refund:${this.id}:${playerId}:${this.seq++}`,
        `cancel bets @ ${this.id}`,
      );
      balance = tx.balance;
    }
    return { byType, balance };
  }

  lock(): void {
    if (this._phase !== 'betting') throw new InvalidPhaseError('lock', this._phase);
    this._phase = 'locked';
  }

  async settle(): Promise<RouletteOutcome> {
    if (this._phase !== 'locked') throw new InvalidPhaseError('settle', this._phase);
    const winning = spin(this.rng);
    const settled: SettledRouletteBet[] = [];
    for (const pb of this.bets) {
      const settlement = settleSpot(pb.bet.spotId, pb.bet.amount, winning);
      let balanceAfter = await this.wallet.getBalance(pb.playerId);
      if (settlement.payout > 0) {
        const tx = await this.wallet.credit(
          pb.playerId,
          settlement.payout,
          `payout:${pb.betId}`,
          `payout ${pb.bet.spotId} @ ${this.id}`,
        );
        balanceAfter = tx.balance;
      }
      settled.push({ ...pb, settlement, balanceAfter });
    }
    this._phase = 'settled';
    this._outcome = { roundId: this.id, winning, color: colorOf(winning), settled };
    return this._outcome;
  }

  private validate(playerId: string, bet: RouletteBet): void {
    if (!Number.isInteger(bet.amount) || bet.amount <= 0) {
      throw new BetValidationError(`bet amount must be a positive integer, got ${bet.amount}`);
    }
    if (!getSpot(bet.spotId)) {
      throw new BetValidationError(`unknown roulette spot '${bet.spotId}'`);
    }
    // Cumulative per spot: minBet gates the opening bet, maxBet caps the total.
    const existing = this.bets
      .filter((p) => p.playerId === playerId && p.bet.spotId === bet.spotId)
      .reduce((sum, p) => sum + p.bet.amount, 0);
    if (existing === 0 && bet.amount < this.limits.minBet) {
      throw new BetValidationError(`opening bet ${bet.amount} below table minimum ${this.limits.minBet}`);
    }
    if (existing + bet.amount > this.limits.maxBet) {
      throw new BetValidationError(`total ${existing + bet.amount} exceeds table maximum ${this.limits.maxBet}`);
    }
  }
}

/** Produces sequential roulette rounds sharing one wallet + RNG + limits. */
export class RouletteTable {
  private roundNo = 0;
  private readonly rng: Rng;
  private readonly wallet: WalletService;
  private readonly limits: RouletteLimits;
  private readonly idPrefix: string;

  constructor(rng: Rng, wallet: WalletService, limits: RouletteLimits, idPrefix = 'RO') {
    this.rng = rng;
    this.wallet = wallet;
    this.limits = limits;
    this.idPrefix = idPrefix;
  }

  get walletService(): WalletService {
    return this.wallet;
  }

  startRound(): RouletteRound {
    this.roundNo += 1;
    return new RouletteRound(`${this.idPrefix}${this.roundNo}`, this.rng, this.wallet, this.limits);
  }
}
