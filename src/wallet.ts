// Coin wallet with an append-only ledger.
//
// Casino-critical properties (upheld by every WalletService implementation):
//  - Atomic: a debit/credit reads, checks and writes as one unit.
//  - Idempotent: every debit/credit carries a `ref`. Re-applying the same ref
//    (e.g. a network retry) returns the original result without double-spending.
//  - Auditable: every balance change is recorded as a ledger entry.
//
// The interface is async so it fits a real database. InMemoryWallet (here) is
// the volatile implementation; SqliteWallet and PgWallet are durable ones.

export class InsufficientFundsError extends Error {
  readonly playerId: string;
  readonly balance: number;
  readonly requested: number;
  constructor(playerId: string, balance: number, requested: number) {
    super(`Insufficient funds for ${playerId}: have ${balance}, need ${requested}`);
    this.name = 'InsufficientFundsError';
    this.playerId = playerId;
    this.balance = balance;
    this.requested = requested;
  }
}

export type LedgerType = 'debit' | 'credit';

export interface LedgerEntry {
  ref: string;
  playerId: string;
  type: LedgerType;
  amount: number;
  balanceAfter: number;
  reason: string;
}

export interface TxResult {
  ref: string;
  applied: boolean; // false if this ref was already applied (idempotent no-op)
  balance: number;
}

export interface WalletService {
  getBalance(playerId: string): Promise<number>;
  credit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult>;
  debit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult>;
  getLedger(playerId: string): Promise<readonly LedgerEntry[]>;
}

export class InMemoryWallet implements WalletService {
  private balances = new Map<string, number>();
  private ledger: LedgerEntry[] = [];
  /** ref -> the TxResult we returned, so retries are exact no-ops. */
  private appliedRefs = new Map<string, TxResult>();

  constructor(initialBalances: Record<string, number> = {}) {
    for (const [playerId, amount] of Object.entries(initialBalances)) {
      this.balances.set(playerId, amount);
    }
  }

  async getBalance(playerId: string): Promise<number> {
    return this.balances.get(playerId) ?? 0;
  }

  async getLedger(playerId: string): Promise<readonly LedgerEntry[]> {
    return this.ledger.filter((e) => e.playerId === playerId);
  }

  async credit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    this.assertAmount(amount);
    const replay = this.appliedRefs.get(ref);
    if (replay) return replay;

    const balance = (this.balances.get(playerId) ?? 0) + amount;
    this.balances.set(playerId, balance);
    this.record(ref, playerId, 'credit', amount, balance, reason);
    return this.remember(ref, balance);
  }

  async debit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    this.assertAmount(amount);
    const replay = this.appliedRefs.get(ref);
    if (replay) return replay;

    const current = this.balances.get(playerId) ?? 0;
    if (current < amount) {
      throw new InsufficientFundsError(playerId, current, amount);
    }
    const balance = current - amount;
    this.balances.set(playerId, balance);
    this.record(ref, playerId, 'debit', amount, balance, reason);
    return this.remember(ref, balance);
  }

  private assertAmount(amount: number): void {
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new RangeError(`amount must be a positive integer, got ${amount}`);
    }
  }

  private record(
    ref: string,
    playerId: string,
    type: LedgerType,
    amount: number,
    balanceAfter: number,
    reason: string,
  ): void {
    this.ledger.push({ ref, playerId, type, amount, balanceAfter, reason });
  }

  private remember(ref: string, balance: number): TxResult {
    const result: TxResult = { ref, applied: true, balance };
    this.appliedRefs.set(ref, { ...result, applied: false }); // replays report applied:false
    return result;
  }
}
