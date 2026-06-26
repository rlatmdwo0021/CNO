// Durable wallet backed by PostgreSQL (production target).
//
// Same contract as the other wallets. Each debit/credit runs in a transaction
// that locks the player's balance row with SELECT ... FOR UPDATE, so concurrent
// requests for the same player serialize instead of racing. The ledger.ref
// PRIMARY KEY enforces idempotency.
//
// Requires a reachable Postgres (DATABASE_URL). Not exercised in environments
// without one; its integration tests are skipped unless DATABASE_URL is set.

import pg from 'pg';
import {
  InsufficientFundsError,
  type LedgerEntry,
  type LedgerType,
  type TxResult,
  type WalletService,
} from './wallet.ts';

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS balances (
    player_id TEXT PRIMARY KEY,
    balance   BIGINT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS ledger (
    ref           TEXT PRIMARY KEY,
    player_id     TEXT NOT NULL,
    type          TEXT NOT NULL,
    amount        BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    reason        TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    seq           BIGSERIAL
  );
  CREATE INDEX IF NOT EXISTS ledger_player ON ledger (player_id, seq);
`;

export class PgWallet implements WalletService {
  private readonly pool: pg.Pool;

  constructor(connectionString: string, ssl = false) {
    this.pool = new pg.Pool({
      connectionString,
      ssl: ssl ? { rejectUnauthorized: false } : undefined,
    });
  }

  /** Create tables if absent. Call once at startup. */
  async init(): Promise<void> {
    await this.pool.query(SCHEMA);
  }

  /** Seed a starting balance without a ledger entry (setup helper). */
  async setBalance(playerId: string, balance: number): Promise<void> {
    await this.pool.query(
      `INSERT INTO balances (player_id, balance) VALUES ($1, $2)
       ON CONFLICT (player_id) DO UPDATE SET balance = excluded.balance`,
      [playerId, balance],
    );
  }

  async getBalance(playerId: string): Promise<number> {
    const res = await this.pool.query<{ balance: string }>(
      'SELECT balance FROM balances WHERE player_id = $1',
      [playerId],
    );
    return res.rows.length ? Number(res.rows[0].balance) : 0;
  }

  async getLedger(playerId: string): Promise<readonly LedgerEntry[]> {
    const res = await this.pool.query(
      'SELECT ref, player_id, type, amount, balance_after, reason FROM ledger WHERE player_id = $1 ORDER BY seq',
      [playerId],
    );
    return res.rows.map((r) => ({
      ref: r.ref,
      playerId: r.player_id,
      type: r.type as LedgerType,
      amount: Number(r.amount),
      balanceAfter: Number(r.balance_after),
      reason: r.reason,
    }));
  }

  credit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    return this.apply('credit', playerId, amount, ref, reason);
  }

  debit(playerId: string, amount: number, ref: string, reason: string): Promise<TxResult> {
    return this.apply('debit', playerId, amount, ref, reason);
  }

  private async apply(
    type: LedgerType,
    playerId: string,
    amount: number,
    ref: string,
    reason: string,
  ): Promise<TxResult> {
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new RangeError(`amount must be a positive integer, got ${amount}`);
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Idempotency: known ref -> original result, no second application.
      const seen = await client.query<{ balance_after: string }>(
        'SELECT balance_after FROM ledger WHERE ref = $1',
        [ref],
      );
      if (seen.rows.length) {
        await client.query('COMMIT');
        return { ref, applied: false, balance: Number(seen.rows[0].balance_after) };
      }

      // Ensure the row exists, then lock it for the rest of the transaction.
      await client.query(
        'INSERT INTO balances (player_id, balance) VALUES ($1, 0) ON CONFLICT (player_id) DO NOTHING',
        [playerId],
      );
      const locked = await client.query<{ balance: string }>(
        'SELECT balance FROM balances WHERE player_id = $1 FOR UPDATE',
        [playerId],
      );
      const current = Number(locked.rows[0].balance);

      if (type === 'debit' && current < amount) {
        await client.query('ROLLBACK');
        throw new InsufficientFundsError(playerId, current, amount);
      }
      const balance = type === 'debit' ? current - amount : current + amount;

      await client.query('UPDATE balances SET balance = $1 WHERE player_id = $2', [
        balance,
        playerId,
      ]);
      await client.query(
        `INSERT INTO ledger (ref, player_id, type, amount, balance_after, reason)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [ref, playerId, type, amount, balance, reason],
      );

      await client.query('COMMIT');
      return { ref, applied: true, balance };
    } catch (err) {
      if (!(err instanceof InsufficientFundsError)) {
        await client.query('ROLLBACK').catch(() => {});
      }
      throw err;
    } finally {
      client.release();
    }
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
