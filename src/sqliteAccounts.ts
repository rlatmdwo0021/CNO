// Durable AccountStore on node:sqlite. Can share the wallet's database file
// (separate `accounts` table), so one file holds balances, ledger and accounts.

import { DatabaseSync } from 'node:sqlite';
import type { Account, AccountStore } from './auth.ts';

export class SqliteAccountStore implements AccountStore {
  private readonly db: DatabaseSync;

  constructor(path = ':memory:') {
    this.db = new DatabaseSync(path);
    this.db.exec('PRAGMA journal_mode = WAL;');
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS accounts (
        player_id  TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        name       TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    `);
  }

  async create(account: Account): Promise<void> {
    this.db
      .prepare(
        'INSERT INTO accounts (player_id, token_hash, name, created_at) VALUES (?, ?, ?, ?)',
      )
      .run(account.playerId, account.tokenHash, account.name, account.createdAt);
  }

  async findByTokenHash(tokenHash: string): Promise<Account | undefined> {
    return this.row(
      this.db.prepare('SELECT * FROM accounts WHERE token_hash = ?').get(tokenHash),
    );
  }

  async findById(playerId: string): Promise<Account | undefined> {
    return this.row(this.db.prepare('SELECT * FROM accounts WHERE player_id = ?').get(playerId));
  }

  private row(r: unknown): Account | undefined {
    if (!r) return undefined;
    const a = r as { player_id: string; token_hash: string; name: string; created_at: number };
    return { playerId: a.player_id, tokenHash: a.token_hash, name: a.name, createdAt: a.created_at };
  }

  close(): void {
    this.db.close();
  }
}
