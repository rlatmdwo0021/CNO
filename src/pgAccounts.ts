// Durable AccountStore on PostgreSQL — the cloud counterpart of
// SqliteAccountStore. Used when DATABASE_URL is set (e.g. on Render/Railway),
// so accounts persist across redeploys and instance restarts.

import pg from 'pg';
import type { Account, AccountStore } from './auth.ts';

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS accounts (
    player_id  TEXT PRIMARY KEY,
    token_hash TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    created_at BIGINT NOT NULL
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
    await this.pool.query(SCHEMA);
  }

  async create(account: Account): Promise<void> {
    await this.pool.query(
      'INSERT INTO accounts (player_id, token_hash, name, created_at) VALUES ($1, $2, $3, $4)',
      [account.playerId, account.tokenHash, account.name, account.createdAt],
    );
  }

  async findByTokenHash(tokenHash: string): Promise<Account | undefined> {
    const res = await this.pool.query('SELECT * FROM accounts WHERE token_hash = $1', [tokenHash]);
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
      tokenHash: r.token_hash as string,
      name: r.name as string,
      createdAt: Number(r.created_at),
    };
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
