import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Round, Table, InvalidPhaseError, BetValidationError } from '../src/round.ts';
import type { TableLimits } from '../src/round.ts';
import { InMemoryWallet, InsufficientFundsError } from '../src/wallet.ts';
import { scriptByRank } from '../src/testing.ts';
import { Shoe } from '../src/cards.ts';
import { seededRng } from '../src/rng.ts';

const LIMITS: TableLimits = { minBet: 10, maxBet: 1000 };

// Player wins this round: P[4,5]=9 natural vs B[5,3]=8. (order P1,B1,P2,B2)
const playerWinsScript = () => scriptByRank(['4', '5', '5', '3']);

test('full happy path: bet escrowed then winnings paid', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);

  await round.placeBet('alice', { type: 'player', amount: 100 });
  assert.equal(await wallet.getBalance('alice'), 900); // stake escrowed immediately

  round.lock();
  const outcome = await round.settle();

  assert.equal(outcome.result.outcome, 'player');
  assert.equal(await wallet.getBalance('alice'), 1100); // 900 + payout 200
  assert.equal(outcome.settled[0].settlement.won, true);
  assert.equal(outcome.settled[0].balanceAfter, 1100);
});

test('losing bet: stake already gone, nothing credited back', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'banker', amount: 100 }); // banker loses
  round.lock();
  await round.settle();
  assert.equal(await wallet.getBalance('alice'), 900);
});

test('tie pushes the player bet: stake returned', async () => {
  // Tie: P[5,4]=9 vs B[4,5]=9
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', scriptByRank(['5', '4', '4', '5']), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 });
  round.lock();
  const outcome = await round.settle();
  assert.equal(outcome.result.outcome, 'tie');
  assert.equal(outcome.settled[0].settlement.won, undefined); // push
  assert.equal(await wallet.getBalance('alice'), 1000); // back to start
});

test('multiple players and bets settle independently', async () => {
  const wallet = new InMemoryWallet({ alice: 1000, bob: 500 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 }); // wins -> +100
  await round.placeBet('bob', { type: 'banker', amount: 50 }); // loses -> -50
  await round.placeBet('alice', { type: 'tie', amount: 10 }); // loses -> -10
  round.lock();
  await round.settle();
  assert.equal(await wallet.getBalance('alice'), 1090); // 1000 +100 -10
  assert.equal(await wallet.getBalance('bob'), 450); // 500 -50
});

test('cannot bet below table minimum or above maximum', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await assert.rejects(() => round.placeBet('alice', { type: 'player', amount: 5 }), BetValidationError);
  await assert.rejects(() => round.placeBet('alice', { type: 'player', amount: 9999 }), BetValidationError);
  assert.equal(await wallet.getBalance('alice'), 1000); // nothing escrowed
});

test('limits are cumulative per market: chips stack up to max, overflow rejected', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS); // max 1000
  await round.placeBet('alice', { type: 'player', amount: 500 });
  await round.placeBet('alice', { type: 'player', amount: 500 }); // total 1000 = max, ok
  assert.equal(await wallet.getBalance('alice'), 0);
  // one more coin over the cap is rejected, wallet untouched
  await assert.rejects(() => round.placeBet('alice', { type: 'player', amount: 1 }), BetValidationError);
  // a different market still has its own headroom (but alice is broke here)
  assert.equal(round.getBets().length, 2);
});

test('only the opening bet on a market must meet the minimum', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS); // min 10
  await assert.rejects(() => round.placeBet('alice', { type: 'player', amount: 5 }), BetValidationError);
  await round.placeBet('alice', { type: 'player', amount: 100 }); // opens the market
  await round.placeBet('alice', { type: 'player', amount: 5 }); // top-up below min is fine
  assert.equal(await wallet.getBalance('alice'), 895);
});

test('clearBets refunds and removes only the caller\'s bets during betting', async () => {
  const wallet = new InMemoryWallet({ alice: 1000, bob: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 });
  await round.placeBet('alice', { type: 'banker', amount: 50 });
  await round.placeBet('bob', { type: 'player', amount: 200 });
  assert.equal(await wallet.getBalance('alice'), 850);

  const res = await round.clearBets('alice');
  assert.deepEqual(res.byType, { player: 100, banker: 50 });
  assert.equal(res.balance, 1000); // fully refunded
  assert.equal(await wallet.getBalance('alice'), 1000);
  assert.equal(await wallet.getBalance('bob'), 800); // untouched
  assert.equal(round.getBets().length, 1); // only bob's bet remains
});

test('bet rejected when allowedBets excludes the market', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, {
    minBet: 10,
    maxBet: 1000,
    allowedBets: ['player', 'banker'],
  });
  await assert.rejects(() => round.placeBet('alice', { type: 'tie', amount: 100 }), BetValidationError);
});

test('insufficient funds prevents the bet from being recorded', async () => {
  const wallet = new InMemoryWallet({ alice: 50 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await assert.rejects(
    () => round.placeBet('alice', { type: 'player', amount: 100 }),
    InsufficientFundsError,
  );
  assert.equal(round.getBets().length, 0);
  assert.equal(await wallet.getBalance('alice'), 50);
});

test('phase guards: no bets after lock, no double settle', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 });
  round.lock();
  await assert.rejects(() => round.placeBet('alice', { type: 'player', amount: 100 }), InvalidPhaseError);
  await round.settle();
  await assert.rejects(() => round.settle(), InvalidPhaseError);
});

test('cannot settle before locking (betting must close first)', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 });
  await assert.rejects(() => round.settle(), InvalidPhaseError);
});

test('settle is not double-credited even if outcome read twice', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const round = new Round('R1', playerWinsScript(), wallet, LIMITS);
  await round.placeBet('alice', { type: 'player', amount: 100 });
  round.lock();
  const a = await round.settle();
  assert.equal(await wallet.getBalance('alice'), 1100);
  assert.equal(round.outcome, a); // cached, settle() not re-run
});

test('Table produces sequential rounds sharing one shoe and wallet', async () => {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const shoe = new Shoe(8, seededRng(42));
  const table = new Table(shoe, wallet, LIMITS);

  const r1 = table.startRound();
  assert.equal(r1.id, 'R1');
  await r1.placeBet('alice', { type: 'player', amount: 100 });
  r1.lock();
  await r1.settle();

  const r2 = table.startRound();
  assert.equal(r2.id, 'R2');
  // wallet carried over between rounds
  assert.equal(await wallet.getBalance('alice'), r1.outcome!.settled[0].balanceAfter);
});
