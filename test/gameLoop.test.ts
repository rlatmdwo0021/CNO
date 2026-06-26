import { test, mock } from 'node:test';
import assert from 'node:assert/strict';

import { GameLoop } from '../src/gameLoop.ts';
import { Table, type TableLimits } from '../src/round.ts';
import { InMemoryWallet } from '../src/wallet.ts';
import { ScriptedShoe } from '../src/testing.ts';
import type { Card, Rank } from '../src/types.ts';

const LIMITS: TableLimits = { minBet: 10, maxBet: 1000 };
const CFG = { bettingMs: 1000, settleDelayMs: 200, pauseMs: 500 };

const card = (rank: Rank): Card => ({ rank, suit: 'S' });

// settle() is async; after ticking the mock timer that triggers it, let its
// promise chain resolve. setImmediate is NOT mocked here, so it drains the
// microtasks queued by the awaited wallet writes.
const flush = () => new Promise((r) => setImmediate(r));

// A reshuffling shoe backed by a fixed script, so each round is deterministic.
// Player wins every round here: P[4,5]=9 vs B[5,3]=8 (order P1,B1,P2,B2).
function loopingShoe(): { draw(): Card; needsShuffle(): boolean; shuffle(): void } {
  const ranks: Rank[] = ['4', '5', '5', '3'];
  let i = 0;
  return {
    draw: () => card(ranks[i++ % ranks.length]),
    needsShuffle: () => false,
    shuffle: () => {},
  };
}

function makeLoop() {
  const wallet = new InMemoryWallet({ alice: 1000 });
  const table = new Table(loopingShoe(), wallet, LIMITS);
  const loop = new GameLoop(table, CFG);
  return { wallet, loop };
}

test('loop runs a full timed round and pays out', async () => {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  try {
    const { wallet, loop } = makeLoop();
    const events: string[] = [];
    loop.on('open', () => events.push('open'));
    loop.on('locked', () => events.push('locked'));
    loop.on('settled', () => events.push('settled'));

    loop.start();
    assert.equal(loop.phase, 'betting');

    const ack = await loop.placeBet('alice', { type: 'player', amount: 100 });
    assert.equal(ack.ok, true);
    assert.equal(await wallet.getBalance('alice'), 900); // escrowed

    mock.timers.tick(CFG.bettingMs); // -> lock
    assert.equal(loop.phase, 'locked');
    mock.timers.tick(CFG.settleDelayMs); // -> triggers async settle
    await flush();
    assert.equal(loop.phase, 'settled');
    assert.equal(await wallet.getBalance('alice'), 1100); // player won 1:1

    assert.deepEqual(events, ['open', 'locked', 'settled']);
    loop.stop();
  } finally {
    mock.timers.reset();
  }
});

test('betting is rejected outside the betting window', async () => {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  try {
    const { loop } = makeLoop();
    loop.start();
    mock.timers.tick(CFG.bettingMs); // now locked
    const ack = await loop.placeBet('alice', { type: 'player', amount: 100 });
    assert.equal(ack.ok, false);
    assert.match(ack.error ?? '', /closed/);
    loop.stop();
  } finally {
    mock.timers.reset();
  }
});

test('loop auto-advances to the next round after the pause', async () => {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  try {
    const { loop } = makeLoop();
    const opens: string[] = [];
    loop.on('open', (e: { roundId: string }) => opens.push(e.roundId));

    loop.start();
    // round 1: betting -> lock -> settle -> pause -> round 2 opens.
    mock.timers.tick(CFG.bettingMs); // lock
    mock.timers.tick(CFG.settleDelayMs); // triggers async settle
    await flush(); // settle completes, schedules the pause timer
    mock.timers.tick(CFG.pauseMs); // next round opens
    assert.equal(loop.phase, 'betting');
    assert.deepEqual(opens, ['R1', 'R2']);
    loop.stop();
  } finally {
    mock.timers.reset();
  }
});

test('stop() halts the loop and clears timers', () => {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  try {
    const { loop } = makeLoop();
    loop.start();
    loop.stop();
    assert.equal(loop.phase, 'idle');
    // advancing time must not reopen a round
    mock.timers.tick(CFG.bettingMs * 5);
    assert.equal(loop.phase, 'idle');
  } finally {
    mock.timers.reset();
  }
});
