// Token-based accounts: persistent player identity + reconnect.
//
// On first contact a player registers; the server mints a random secret token
// and stores only its SHA-256 hash. The client keeps the token and presents it
// to re-authenticate (reconnect) as the same account. Tokens are never stored
// or logged in the clear, and playerId alone grants no access — you need the
// token, so one player can't impersonate another by guessing an id.

import { randomBytes, createHash } from 'node:crypto';

export interface Account {
  playerId: string;
  tokenHash: string;
  name: string;
  createdAt: number;
}

/** Persistence seam for accounts (mirrors WalletService). */
export interface AccountStore {
  create(account: Account): Promise<void>;
  findByTokenHash(tokenHash: string): Promise<Account | undefined>;
  findById(playerId: string): Promise<Account | undefined>;
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export interface Session {
  playerId: string;
  name: string;
  /** The raw token — returned ONCE at registration for the client to store. */
  token: string;
}

export class AuthService {
  private readonly store: AccountStore;

  constructor(store: AccountStore) {
    this.store = store;
  }

  /** Create a new account and issue its token. */
  async register(name?: string): Promise<Session> {
    const token = randomBytes(24).toString('hex');
    const playerId = `p_${randomBytes(6).toString('hex')}`;
    const finalName = name?.trim() || `Player-${playerId.slice(2, 8)}`;
    await this.store.create({
      playerId,
      tokenHash: hashToken(token),
      name: finalName,
      createdAt: Date.now(),
    });
    return { playerId, name: finalName, token };
  }

  /** Resolve a token to its account, or null if unknown. */
  async authenticate(token: string): Promise<Account | null> {
    if (!token) return null;
    return (await this.store.findByTokenHash(hashToken(token))) ?? null;
  }
}

export class InMemoryAccountStore implements AccountStore {
  private byId = new Map<string, Account>();
  private byHash = new Map<string, Account>();

  async create(account: Account): Promise<void> {
    this.byId.set(account.playerId, account);
    this.byHash.set(account.tokenHash, account);
  }
  async findByTokenHash(tokenHash: string): Promise<Account | undefined> {
    return this.byHash.get(tokenHash);
  }
  async findById(playerId: string): Promise<Account | undefined> {
    return this.byId.get(playerId);
  }
}
