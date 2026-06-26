import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rmSync } from 'node:fs';

import { SqliteWallet } from '../src/sqliteWallet.ts';
import { walletContract } from './walletContract.ts';

// Run the full contract against an ephemeral in-memory SQLite db.
walletContract('sqlite', async (initial) => {
  const w = new SqliteWallet(':memory:');
  if (initial) for (const [p, a] of Object.entries(initial)) w.setBalance(p, a);
  return w;
});

test('[sqlite] balances and ledger survive a restart', async () => {
  const file = join(tmpdir(), `baccarat-wallet-${process.pid}.db`);
  rmSync(file, { force: true });
  try {
    const w1 = new SqliteWallet(file);
    w1.setBalance('alice', 1000);
    await w1.debit('alice', 250, 'bet:1', 'bet');
    await w1.credit('alice', 500, 'payout:1', 'payout');
    assert.equal(await w1.getBalance('alice'), 1250);
    w1.close();

    // Reopen the same file: state is still there.
    const w2 = new SqliteWallet(file);
    assert.equal(await w2.getBalance('alice'), 1250);
    assert.equal((await w2.getLedger('alice')).length, 2);

    // Idempotency persists too: replaying a ref is a no-op after restart.
    const replay = await w2.debit('alice', 250, 'bet:1', 'bet');
    assert.equal(replay.applied, false);
    assert.equal(await w2.getBalance('alice'), 1250);
    w2.close();
  } finally {
    rmSync(file, { force: true });
    rmSync(`${file}-wal`, { force: true });
    rmSync(`${file}-shm`, { force: true });
  }
});
