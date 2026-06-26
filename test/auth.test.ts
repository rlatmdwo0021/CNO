import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rmSync } from 'node:fs';

import {
  AuthService,
  AuthError,
  InMemoryAccountStore,
  hashPassword,
  verifyPassword,
} from '../src/auth.ts';
import { SqliteAccountStore } from '../src/sqliteAccounts.ts';

test('register then login with the right password returns the same player', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const reg = await auth.register('alice', 'secret123', 'Alice');
  assert.match(reg.playerId, /^p_/);
  assert.equal(reg.name, 'Alice');

  const login = await auth.login('alice', 'secret123');
  assert.equal(login.playerId, reg.playerId);
  assert.equal(login.name, 'Alice');
});

test('duplicate username is rejected', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  await auth.register('bob', 'password');
  await assert.rejects(() => auth.register('bob', 'other'), AuthError);
});

test('wrong password and unknown user both fail to log in', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  await auth.register('carol', 'correct-horse');
  await assert.rejects(() => auth.login('carol', 'wrong'), AuthError);
  await assert.rejects(() => auth.login('nobody', 'whatever'), AuthError);
});

test('short username or password is rejected', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  await assert.rejects(() => auth.register('ab', 'longenough'), AuthError);
  await assert.rejects(() => auth.register('validname', '123'), AuthError);
});

test('default display name falls back to the username', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const reg = await auth.register('dave', 'password');
  assert.equal(reg.name, 'dave');
});

test('password is stored only as a salted hash', async () => {
  const stored = hashPassword('hunter2');
  assert.notEqual(stored, 'hunter2');
  assert.match(stored, /^[0-9a-f]+:[0-9a-f]+$/);
  assert.equal(verifyPassword('hunter2', stored), true);
  assert.equal(verifyPassword('wrong', stored), false);
});

test('session token authenticates back to the account; bad token does not', async () => {
  const auth = new AuthService(new InMemoryAccountStore());
  const reg = await auth.register('erin', 'password');
  const acc = await auth.authenticate(reg.token);
  assert.equal(acc?.playerId, reg.playerId);
  assert.equal(await auth.authenticate('not-a-token'), null);
  assert.equal(await auth.authenticate(''), null);
});

test('[sqlite] accounts persist; login works after a restart', async () => {
  const file = join(tmpdir(), `baccarat-accounts-${process.pid}.db`);
  rmSync(file, { force: true });
  try {
    const store1 = new SqliteAccountStore(file);
    const reg = await new AuthService(store1).register('frank', 'password', 'Frank');
    store1.close();

    // Reopen: the password still verifies via a fresh login.
    const store2 = new SqliteAccountStore(file);
    const login = await new AuthService(store2).login('frank', 'password');
    assert.equal(login.playerId, reg.playerId);
    assert.equal(login.name, 'Frank');
    await assert.rejects(() => new AuthService(store2).login('frank', 'nope'), AuthError);
    store2.close();
  } finally {
    rmSync(file, { force: true });
    rmSync(`${file}-wal`, { force: true });
    rmSync(`${file}-shm`, { force: true });
  }
});
