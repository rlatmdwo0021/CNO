import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rmSync } from 'node:fs';

import { AuthService, InMemoryAccountStore, hashToken } from '../src/auth.ts';
import { SqliteAccountStore } from '../src/sqliteAccounts.ts';

test('register issues a token that authenticates back to the same account', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const session = await auth.register('Alice');
  assert.match(session.playerId, /^p_/);
  assert.equal(session.name, 'Alice');
  assert.ok(session.token.length >= 32);

  const acc = await auth.authenticate(session.token);
  assert.ok(acc);
  assert.equal(acc.playerId, session.playerId);
  assert.equal(acc.name, 'Alice');
});

test('reconnect: the same token resolves to the same player across calls', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const { token, playerId } = await auth.register();
  const first = await auth.authenticate(token);
  const second = await auth.authenticate(token);
  assert.equal(first?.playerId, playerId);
  assert.equal(second?.playerId, playerId);
});

test('an unknown or empty token is rejected (no impersonation)', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  await auth.register();
  assert.equal(await auth.authenticate('not-a-real-token'), null);
  assert.equal(await auth.authenticate(''), null);
});

test('knowing only the playerId does not grant access', async () => {
  const store = new InMemoryAccountStore();
  const auth = new AuthService(store);
  const { playerId } = await auth.register();
  // The playerId is not a credential; only the token authenticates.
  assert.equal(await auth.authenticate(playerId), null);
});

test('the store keeps only the token hash, never the raw token', async () => {
  const store = new InMemoryAccountStore();
  const auth = new AuthService(store);
  const { token, playerId } = await auth.register();
  const acc = await store.findById(playerId);
  assert.notEqual(acc?.tokenHash, token);
  assert.equal(acc?.tokenHash, hashToken(token));
});

test('default name is derived from the player id when none given', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const session = await auth.register();
  assert.match(session.name, /^Player-/);
});

test('[sqlite] accounts persist across a restart', async () => {
  const file = join(tmpdir(), `baccarat-accounts-${process.pid}.db`);
  rmSync(file, { force: true });
  try {
    const store1 = new SqliteAccountStore(file);
    const auth1 = new AuthService(store1);
    const { token, playerId } = await auth1.register('Returning');
    store1.close();

    // Reopen: the token still authenticates to the same account.
    const store2 = new SqliteAccountStore(file);
    const auth2 = new AuthService(store2);
    const acc = await auth2.authenticate(token);
    assert.equal(acc?.playerId, playerId);
    assert.equal(acc?.name, 'Returning');
    store2.close();
  } finally {
    rmSync(file, { force: true });
    rmSync(`${file}-wal`, { force: true });
    rmSync(`${file}-shm`, { force: true });
  }
});
