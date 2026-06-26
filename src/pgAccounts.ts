// Durable AccountStore on PostgreSQL — the cloud counterpart of
// SqliteAccountStore. Used when DATABASE_URL is set (e.g. on Render/Railway),
// so accounts persist across redeploys and instance restarts.

import pg from 'pg';
import type { Account, AccountStore } from './auth.ts';

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS accounts (
    player_id     TEXT PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    name          TEXT NOT NULL,
    created_at    BIGINT NOT NULL
  );
`;

export class PgAccountStore implements AccountStore {
  private readonly pool: pg.Pool;

  constructor(connectionString: string, ssl = false) {
    this.pool = new pg.Pool({
      connectionString,
      ssl: ssl ? { rejectUnauthorized: false } : undefined,
    });
  }

  async init(): Promise<void> {
    // One-time prototype migration: an earlier accounts table used `token_hash`
    // instead of `username`/`password_hash`. If we detect that old shape (table
    // exists but has no `username` column), drop it — accounts are disposable at
    // this stage — so the new schema is created cleanly.
    const tbl = await this.pool.query(
      "SELECT 1 FROM information_schema.tables WHERE table_name = 'accounts'",
    );
    if (tbl.rows.length) {
      const col = await this.pool.query(
        "SELECT 1 FROM information_schema.columns WHERE table_name = 'accounts' AND column_name = 'username'",
      );
      if (!col.rows.length) await this.pool.query('DROP TABLE accounts');
    }
    await this.pool.query(SCHEMA);
  }

  async create(account: Account): Promise<void> {
    await this.pool.query(
      'INSERT INTO accounts (player_id, username, password_hash, name, created_at) VALUES ($1, $2, $3, $4, $5)',
      [account.playerId, account.username, account.passwordHash, account.name, account.createdAt],
    );
  }

  async findByUsername(username: string): Promise<Account | undefined> {
    const res = await this.pool.query('SELECT * FROM accounts WHERE username = $1', [username]);
    return this.row(res.rows[0]);
  }

  async findById(playerId: string): Promise<Account | undefined> {
    const res = await this.pool.query('SELECT * FROM accounts WHERE player_id = $1', [playerId]);
    return this.row(res.rows[0]);
  }

  private row(r: Record<string, unknown> | undefined): Account | undefined {
    if (!r) return undefined;
    return {
      playerId: r.player_id as string,
      username: r.username as string,
      passwordHash: r.password_hash as string,
      name: r.name as string,
      createdAt: Number(r.created_at),
    };
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
