// ID/password accounts with persistent identity + in-session reconnect.
//
// Register/login take a username + password. Passwords are stored only as a
// scrypt hash (salt:hash), never in the clear. A successful register/login
// mints a short-lived session token kept in server memory (token -> playerId);
// the client uses it to re-auth on a dropped connection. Tokens are NOT
// persisted on the client, so each app launch requires a fresh login.

import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

export interface Account {
  playerId: string;
  username: string;
  passwordHash: string; // "saltHex:keyHex"
  name: string;
  createdAt: number;
}

/** Persistence seam for accounts (in-memory / SQLite / Postgres). */
export interface AccountStore {
  create(account: Account): Promise<void>;
  findByUsername(username: string): Promise<Account | undefined>;
  findById(playerId: string): Promise<Account | undefined>;
}

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AuthError';
  }
}

export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const key = scryptSync(password, salt, 64);
  return `${salt.toString('hex')}:${key.toString('hex')}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const [saltHex, keyHex] = stored.split(':');
  if (!saltHex || !keyHex) return false;
  const key = Buffer.from(keyHex, 'hex');
  const test = scryptSync(password, Buffer.from(saltHex, 'hex'), 64);
  return key.length === test.length && timingSafeEqual(key, test);
}

export interface Session {
  playerId: string;
  name: string;
  /** In-memory session token — used only for reconnect within the same run. */
  token: string;
}

export class AuthService {
  private readonly store: AccountStore;
  /** token -> playerId, in memory only (cleared on server restart). */
  private readonly sessions = new Map<string, string>();

  constructor(store: AccountStore) {
    this.store = store;
  }

  async register(username: string, password: string, name?: string): Promise<Session> {
    const u = (username ?? '').trim();
    if (u.length < 3 || u.length > 20) {
      throw new AuthError('아이디는 3~20자여야 합니다.');
    }
    if ((password ?? '').length < 4) {
      throw new AuthError('비밀번호는 4자 이상이어야 합니다.');
    }
    if (await this.store.findByUsername(u)) {
      throw new AuthError('이미 사용 중인 아이디입니다.');
    }
    const playerId = `p_${randomBytes(6).toString('hex')}`;
    const finalName = (name ?? '').trim() || u;
    await this.store.create({
      playerId,
      username: u,
      passwordHash: hashPassword(password),
      name: finalName,
      createdAt: Date.now(),
    });
    return { playerId, name: finalName, token: this.issueToken(playerId) };
  }

  async login(username: string, password: string): Promise<Session> {
    const account = await this.store.findByUsername((username ?? '').trim());
    if (!account || !verifyPassword(password ?? '', account.passwordHash)) {
      throw new AuthError('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    return {
      playerId: account.playerId,
      name: account.name,
      token: this.issueToken(account.playerId),
    };
  }

  /**
   * Test-only guest login: log into a fixed account by username, creating it
   * (with a random password the client never needs) if it doesn't exist yet.
   * Idempotent and password-free — no login/register race. Gate in production.
   */
  async guestLogin(username = 'test', name = '테스터'): Promise<Session> {
    let account = await this.store.findByUsername(username);
    if (!account) {
      const playerId = `p_${randomBytes(6).toString('hex')}`;
      account = {
        playerId,
        username,
        passwordHash: hashPassword(randomBytes(16).toString('hex')),
        name,
        createdAt: Date.now(),
      };
      await this.store.create(account);
    }
    return { playerId: account.playerId, name: account.name, token: this.issueToken(account.playerId) };
  }

  /** Resolve a session token to its account, or null if unknown/expired. */
  async authenticate(token: string): Promise<Account | null> {
    const playerId = this.sessions.get(token ?? '');
    if (!playerId) return null;
    return (await this.store.findById(playerId)) ?? null;
  }

  private issueToken(playerId: string): string {
    const token = randomBytes(24).toString('hex');
    this.sessions.set(token, playerId);
    return token;
  }
}

export class InMemoryAccountStore implements AccountStore {
  private byId = new Map<string, Account>();
  private byUsername = new Map<string, Account>();

  async create(account: Account): Promise<void> {
    this.byId.set(account.playerId, account);
    this.byUsername.set(account.username, account);
  }
  async findByUsername(username: string): Promise<Account | undefined> {
    return this.byUsername.get(username);
  }
  async findById(playerId: string): Promise<Account | undefined> {
    return this.byId.get(playerId);
  }
}
