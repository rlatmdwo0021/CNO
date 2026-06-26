import { test } from 'node:test';
import assert from 'node:assert/strict';

import { RouletteRound, RouletteTable, InvalidPhaseError, BetValidationError } from '../src/rouletteRound.ts';
import type { RouletteLimits } from '../src/rouletteRound.ts';
import { InMemoryWallet, InsufficientFundsError } from '../src/wallet.ts';
import { POCKETS } from '../src/rouletteEngine.ts';
import type { Rng } from '../src/rng.ts';

const LIMITS: RouletteLimits = { minBet: 10, maxBet: 1000 };

// An RNG that always lands the wheel on POCKETS[idx], so settlement is deterministic.
function fixedRng(idx: number): Rng {
  return { next: () => 0, nextInt: () => idx };
}
const RED_1 = POCKETS.indexOf('1'); // '1' is red
const BLACK_2 = POCKETS.indexOf('2'); // '2' is black
const ZERO = POCKETS.indexOf('0');

test('straight-up win pays 35:1; round escrows then credits', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await round.placeBet('alice', { spotId: 's:1', amount: 100 });
  assert.equal(await wallet.getBalance('alice'), 900); // escrowed
  round.lock();
  const out = await round.settle();
  assert.equal(out.winning, '1');
  assert.equal(out.color, 'red');
  assert.equal(await wallet.getBalance('alice'), 900 + 3600); // stake back + 3500 win
});

test('losing bets keep the escrow (no payout)', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new RouletteRound('RO1', fixedRng(BLACK_2), wallet, LIMITS);
  await round.placeBet('alice', { spotId: 'red', amount: 100 }); // 2 is black -> lose
  round.lock();
  const out = await round.settle();
  assert.equal(out.settled[0].settlement.won, false);
  assert.equal(await wallet.getBalance('alice'), 900);
});

test('red bet wins on red, loses on green zero', async () => {
  const w1 = new InMemoryWallet({ a: 1000 });
  const r1 = new RouletteRound('RO1', fixedRng(RED_1), w1, LIMITS);
  await r1.placeBet('a', { spotId: 'red', amount: 100 });
  r1.lock();
  await r1.settle();
  assert.equal(await w1.getBalance('a'), 1000 + 100); // 1:1

  const w2 = new InMemoryWallet({ a: 1000 });
  const r2 = new RouletteRound('RO2', fixedRng(ZERO), w2, LIMITS);
  await r2.placeBet('a', { spotId: 'red', amount: 100 });
  r2.lock();
  await r2.settle();
  assert.equal(await w2.getBalance('a'), 900); // 0 -> red loses
});

test('clearBets refunds and removes only the caller\'s bets', async () => {
  const wallet = new InMemoryWallet({ alice: 1000, bob: 1000 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await round.placeBet('alice', { spotId: 's:1', amount: 100 });
  await round.placeBet('alice', { spotId: 'red', amount: 50 });
  await round.placeBet('bob', { spotId: 'black', amount: 200 });
  const res = await round.clearBets('alice');
  assert.deepEqual(res.byType, { 's:1': 100, red: 50 });
  assert.equal(res.balance, 1000);
  assert.equal(await wallet.getBalance('bob'), 800);
  assert.equal(round.getBets().length, 1);
});

test('limits: unknown spot, below-min opening, and over-max are rejected', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await assert.rejects(() => round.placeBet('alice', { spotId: 'nope', amount: 100 }), BetValidationError);
  await assert.rejects(() => round.placeBet('alice', { spotId: 'red', amount: 5 }), BetValidationError);
  await assert.rejects(() => round.placeBet('alice', { spotId: 'red', amount: 9999 }), BetValidationError);
  assert.equal(await wallet.getBalance('alice'), 1000); // nothing escrowed
});

test('limits are cumulative per spot; top-ups below min allowed once opened', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await round.placeBet('alice', { spotId: 'red', amount: 500 });
  await round.placeBet('alice', { spotId: 'red', amount: 500 }); // total 1000 = max, ok
  await assert.rejects(() => round.placeBet('alice', { spotId: 'red', amount: 1 }), BetValidationError); // over max
  // a small top-up below the table minimum is fine once a spot is opened
  const w2 = new InMemoryWallet({ alice: 1000 });
  const r2 = new RouletteRound('RO2', fixedRng(RED_1), w2, LIMITS);
  await r2.placeBet('alice', { spotId: 'black', amount: 100 }); // opens black (>= min 10)
  await r2.placeBet('alice', { spotId: 'black', amount: 5 }); // top-up below min ok
  assert.equal(await w2.getBalance('alice'), 895);
});

test('phase guards: no bets after lock, no double settle', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await round.placeBet('alice', { spotId: 'red', amount: 100 });
  round.lock();
  await assert.rejects(() => round.placeBet('alice', { spotId: 'red', amount: 100 }), InvalidPhaseError);
  await round.settle();
  await assert.rejects(() => round.settle(), InvalidPhaseError);
});

test('insufficient funds prevents the bet from being recorded', async () => {
  const wallet = new InMemoryWallet({ alice: 50 });
  const round = new RouletteRound('RO1', fixedRng(RED_1), wallet, LIMITS);
  await assert.rejects(() => round.placeBet('alice', { spotId: 'red', amount: 100 }), InsufficientFundsError);
  assert.equal(round.getBets().length, 0);
});

test('Table produces sequential rounds sharing one wallet', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const table = new RouletteTable(fixedRng(RED_1), wallet, LIMITS);
  const r1 = table.startRound();
  const r2 = table.startRound();
  assert.notEqual(r1.id, r2.id);
  assert.equal(table.walletService, wallet);
});
