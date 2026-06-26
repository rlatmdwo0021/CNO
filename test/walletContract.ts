// Shared behavioural contract every WalletService must satisfy. Run against
// each implementation (in-memory, SQLite, and Postgres when available) so they
// stay interchangeable. This file defines no tests on its own — it exports a
// function the real *.test.ts files call.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { InsufficientFundsError, type WalletService } from '../src/wallet.ts';

type Make = (initial?: Record<string, number>) => Promise<WalletService>;

export function walletContract(label: string, make: Make): void {
  const t = (name: string, fn: () => Promise<void>) => test(`[${label}] ${name}`, fn);

  t('credit and debit move the balance', async () => {
    const w = await make({ alice: 1000 });
    assert.equal(await w.getBalance('alice'), 1000);
    await w.debit('alice', 300, 'r1', 'bet');
    assert.equal(await w.getBalance('alice'), 700);
    await w.credit('alice', 100, 'r2', 'payout');
    assert.equal(await w.getBalance('alice'), 800);
  });

  t('unknown player starts at 0', async () => {
    const w = await make();
    assert.equal(await w.getBalance('ghost'), 0);
  });

  t('debit beyond balance throws and does not change balance', async () => {
    const w = await make({ bob: 50 });
    await assert.rejects(() => w.debit('bob', 100, 'r1', 'bet'), InsufficientFundsError);
    assert.equal(await w.getBalance('bob'), 50);
  });

  t('idempotent: repeating a ref does not apply twice', async () => {
    const w = await make({ alice: 1000 });
    const first = await w.debit('alice', 200, 'same-ref', 'bet');
    assert.equal(first.applied, true);
    assert.equal(first.balance, 800);

    const retry = await w.debit('alice', 200, 'same-ref', 'bet');
    assert.equal(retry.applied, false); // recognized as a replay
    assert.equal(retry.balance, 800);
    assert.equal(await w.getBalance('alice'), 800);
  });

  t('idempotency is keyed by ref, not amount', async () => {
    const w = await make({ alice: 1000 });
    await w.credit('alice', 100, 'ref-A', 'x');
    await w.credit('alice', 999, 'ref-A', 'x'); // same ref -> ignored
    assert.equal(await w.getBalance('alice'), 1100);
  });

  t('rejects non-positive or fractional amounts', async () => {
    const w = await make({ alice: 1000 });
    await assert.rejects(() => w.debit('alice', 0, 'r', 'x'), RangeError);
    await assert.rejects(() => w.credit('alice', -5, 'r', 'x'), RangeError);
    await assert.rejects(() => w.debit('alice', 1.5, 'r', 'x'), RangeError);
  });

  t('ledger records every change with running balance', async () => {
    const w = await make({ alice: 1000 });
    await w.debit('alice', 200, 'r1', 'bet');
    await w.credit('alice', 400, 'r2', 'payout');
    const ledger = await w.getLedger('alice');
    assert.equal(ledger.length, 2);
    assert.deepEqual(
      ledger.map((e) => [e.type, e.amount, e.balanceAfter]),
      [
        ['debit', 200, 800],
        ['credit', 400, 1200],
      ],
    );
  });
}
