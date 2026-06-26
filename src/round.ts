// Round state machine: betting -> locked -> settled.
//
// Orchestrates a single baccarat round on top of the engine + wallet:
//  - placeBet escrows coins (immediate debit) so a player can never bet money
//    they don't have, and stakes are held until settlement.
//  - settle deals via the engine and credits each bet's payout back. Because
//    settleBet.payout already encodes "stake + winnings" (win), "stake" (push)
//    or 0 (loss), crediting payout is the whole settlement.

import { playRound, settleBet } from './engine.ts';
import type { Bet, BetType, CardSource, RoundResult, BetSettlement } from './types.ts';
import type { WalletService } from './wallet.ts';

export type RoundPhase = 'betting' | 'locked' | 'settled';

export class InvalidPhaseError extends Error {
  constructor(action: string, phase: RoundPhase) {
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

export interface TableLimits {
  minBet: number;
  maxBet: number;
  /** If set, only these markets may be bet. Defaults to all. */
  allowedBets?: BetType[];
}

export interface PlacedBet {
  betId: string;
  playerId: string;
  bet: Bet;
}

export interface SettledBet extends PlacedBet {
  settlement: BetSettlement;
  /** Player's wallet balance after this bet's payout was credited. */
  balanceAfter: number;
}

export interface RoundOutcome {
  roundId: string;
  result: RoundResult;
  settled: SettledBet[];
}

export class Round {
  readonly id: string;
  private _phase: RoundPhase = 'betting';
  private readonly bets: PlacedBet[] = [];
  private seq = 0;
  private _outcome: RoundOutcome | undefined;

  private readonly source: CardSource;
  private readonly wallet: WalletService;
  private readonly limits: TableLimits;

  constructor(id: string, source: CardSource, wallet: WalletService, limits: TableLimits) {
    this.id = id;
    this.source = source;
    this.wallet = wallet;
    this.limits = limits;
  }

  get phase(): RoundPhase {
    return this._phase;
  }

  get outcome(): RoundOutcome | undefined {
    return this._outcome;
  }

  /** All bets placed so far (e.g. to broadcast table state). */
  getBets(): readonly PlacedBet[] {
    return this.bets;
  }

  /**
   * Place a bet during the betting window. Escrows the stake immediately.
   * Throws BetValidationError on bad input (wallet stays untouched), or
   * InsufficientFundsError from the wallet (bet not recorded).
   */
  async placeBet(playerId: string, bet: Bet): Promise<PlacedBet> {
    if (this._phase !== 'betting') throw new InvalidPhaseError('place a bet', this._phase);
    this.validate(bet);

    const betId = `${this.id}#${this.seq++}`;
    // Debit first; if it throws (insufficient funds) the bet is not recorded.
    await this.wallet.debit(playerId, bet.amount, `bet:${betId}`, `bet ${bet.type} @ ${this.id}`);

    const placed: PlacedBet = { betId, playerId, bet };
    this.bets.push(placed);
    return placed;
  }

  /** Close the betting window. No bets accepted after this. */
  lock(): void {
    if (this._phase !== 'betting') throw new InvalidPhaseError('lock', this._phase);
    this._phase = 'locked';
  }

  /**
   * Deal the round and pay out. Round must be locked first (so betting is
   * provably closed before any card is drawn — no last-second bets).
   */
  async settle(): Promise<RoundOutcome> {
    if (this._phase !== 'locked') throw new InvalidPhaseError('settle', this._phase);

    const result = playRound(this.source);
    const settled: SettledBet[] = [];
    for (const pb of this.bets) {
      const settlement = settleBet(pb.bet, result);
      let balanceAfter = await this.wallet.getBalance(pb.playerId);
      if (settlement.payout > 0) {
        const tx = await this.wallet.credit(
          pb.playerId,
          settlement.payout,
          `payout:${pb.betId}`,
          `payout ${pb.bet.type} @ ${this.id}`,
        );
        balanceAfter = tx.balance;
      }
      settled.push({ ...pb, settlement, balanceAfter });
    }

    this._phase = 'settled';
    this._outcome = { roundId: this.id, result, settled };
    return this._outcome;
  }

  private validate(bet: Bet): void {
    if (!Number.isInteger(bet.amount) || bet.amount <= 0) {
      throw new BetValidationError(`bet amount must be a positive integer, got ${bet.amount}`);
    }
    if (bet.amount < this.limits.minBet || bet.amount > this.limits.maxBet) {
      throw new BetValidationError(
        `bet ${bet.amount} outside table limits [${this.limits.minBet}, ${this.limits.maxBet}]`,
      );
    }
    if (this.limits.allowedBets && !this.limits.allowedBets.includes(bet.type)) {
      throw new BetValidationError(`bet type '${bet.type}' not allowed at this table`);
    }
  }
}

/**
 * A table ties a shoe + wallet together and produces sequential rounds,
 * reshuffling the shoe when the cut card is reached. Timing (betting windows,
 * WebSocket broadcasts) lives above this — the state machine stays synchronous
 * and deterministic so it's easy to test and drive from anywhere.
 */
export interface ReshufflingShoe extends CardSource {
  needsShuffle(): boolean;
  shuffle(): void;
}

export class Table {
  private roundNo = 0;
  private readonly shoe: ReshufflingShoe;
  private readonly wallet: WalletService;
  private readonly limits: TableLimits;
  private readonly idPrefix: string;

  constructor(
    shoe: ReshufflingShoe,
    wallet: WalletService,
    limits: TableLimits,
    idPrefix = 'R',
  ) {
    this.shoe = shoe;
    this.wallet = wallet;
    this.limits = limits;
    this.idPrefix = idPrefix;
  }

  /** The shared wallet, exposed for read access (balances, ledger). */
  get walletService(): WalletService {
    return this.wallet;
  }

  /** Begin a new round (reshuffling between rounds if the cut card was hit). */
  startRound(): Round {
    if (this.shoe.needsShuffle()) this.shoe.shuffle();
    this.roundNo += 1;
    return new Round(`${this.idPrefix}${this.roundNo}`, this.shoe, this.wallet, this.limits);
  }
}
