import { test } from 'node:test';
import { walletContract } from './walletContract.ts';

// Postgres is exercised only when DATABASE_URL points at a reachable database.
// Otherwise this file registers a single skipped test so the suite stays green
// in environments without Postgres.
const url = process.env.DATABASE_URL;

if (!url) {
  test('[pg] skipped — set DATABASE_URL to run the Postgres wallet contract', { skip: true }, () => {});
} else {
  const { PgWallet } = await import('../src/pgWallet.ts');
  const pg = (await import('pg')).default;

  walletContract('pg', async (initial) => {
    const wallet = new PgWallet(url);
    await wallet.init();
    // Isolate each contract case: clear the shared tables first.
    const pool = new pg.Pool({ connectionString: url });
    await pool.query('TRUNCATE balances, ledger');
    await pool.end();
    if (initial) {
      for (const [p, a] of Object.entries(initial)) await wallet.setBalance(p, a);
    }
    return wallet;
  });
}
