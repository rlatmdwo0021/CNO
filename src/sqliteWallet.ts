// Durable wallet backed by SQLite (Node's built-in node:sqlite — no deps).
//
// Same contract as InMemoryWallet, but balances and the ledger survive a
// restart. The `ledger.ref` PRIMARY KEY enforces idempotency at the storage
// layer, and each debit/credit runs inside an IMMEDIATE transaction so the
// read-check-write is atomic.

import { DatabaseSync } from 'node:sqlite';
import {
  InsufficientFundsError,
  type LedgerEntry,
  type LedgerType,
  type TxResult,
  type WalletService,
} from './wallet.ts';

export class SqliteWallet implements WalletService {
  private readonly db: DatabaseSync;

  /** @param path file path for persistence, or ':memory:' for ephemeral. */
  constructor(path = ':memory:') {
    this.db = new DatabaseSync(path);
    this.db.exec('PRAGMA journal_mode = WAL;');
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS balances (
        player_id TEXT PRIMARY KEY,
        balance   INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS ledger (
        ref           TEXT PRIMARY KEY,
        player_id     TEXT NOT NULL,
        type          TEXT NOT NULL,
        amount        INTEGER NOT NULL,
        balance_after INTEGER NOT NULL,
        reason        TEXT NOT NULL,
        created_at    INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS ledger_player ON ledger (player_id);
    `);
  }

  /** Seed a starting balance (test/setup helper, not part of the interface). */
  setBalance(playerId: string, balance: number): void {
    this.db
      .prepare(
        `INSERT INTO balances (player_id, balance) VALUES (?, ?)
         ON CONFLICT(player_id) DO UPDATE SET balance = excluded.balance`,
      )
      .run(playerId, balance);
  }

  async getBalance(playerId: string): Promise<number> {
    const row = this.db
      .prepare('SELECT balance FROM balances WHERE player_id = ?')
      .get(playerId) as { balance: number } | undefined;
    return row?.balance ?? 0;
  }

  async getLedger(playerId: string): Promise<readonly LedgerEntry[]> {
    const rows = this.db
      .prepare('SELECT * FROM ledger WHERE player_id = ? ORDER BY rowid')
      .all(playerId) as Array<{
      ref: string;
      player_id: string;
      type: LedgerType;
      amount: number;
      balance_after: number;
      reason: string;
    }>;
    return rows.map((r) => ({
      ref: r.ref,
      playerId: r.player_id,
      type: r.type,
      amount: r.amount,
      balanceAfter: r.balance_after,
      reason: r.reason,
    }));
  }

  async credit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    return this.apply('credit', playerId, amount, ref, reason);
  }

  async debit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    return this.apply('debit', playerId, amount, ref, reason);
  }

  private apply(
    type: LedgerType,
    playerId: string,
    amount: number,
    ref: string,
    reason: string,
  ): TxResult {
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new RangeError(`amount must be a positive integer, got ${amount}`);
    }

    // Idempotency: a known ref returns the original result, applied = false.
    const seen = this.db
      .prepare('SELECT balance_after FROM ledger WHERE ref = ?')
      .get(ref) as { balance_after: number } | undefined;
    if (seen) return { ref, applied: false, balance: seen.balance_after };

    this.db.exec('BEGIN IMMEDIATE');
    try {
      const current = (
        (this.db.prepare('SELECT balance FROM balances WHERE player_id = ?').get(playerId) as
          | { balance: number }
          | undefined) ?? { balance: 0 }
      ).balance;

      if (type === 'debit' && current < amount) {
        this.db.exec('ROLLBACK');
        throw new InsufficientFundsError(playerId, current, amount);
      }
      const balance = type === 'debit' ? current - amount : current + amount;

      this.db
        .prepare(
          `INSERT INTO balances (player_id, balance) VALUES (?, ?)
           ON CONFLICT(player_id) DO UPDATE SET balance = excluded.balance`,
        )
        .run(playerId, balance);
      this.db
        .prepare(
          `INSERT INTO ledger (ref, player_id, type, amount, balance_after, reason, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .run(ref, playerId, type, amount, balance, reason, Date.now());

      this.db.exec('COMMIT');
      return { ref, applied: true, balance };
    } catch (err) {
      if (!(err instanceof InsufficientFundsError)) {
        try {
          this.db.exec('ROLLBACK');
        } catch {
          /* already rolled back */
        }
      }
      throw err;
    }
  }

  close(): void {
    this.db.close();
  }
}
