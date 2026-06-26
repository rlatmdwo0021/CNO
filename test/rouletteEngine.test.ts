import { test } from 'node:test';
import assert from 'node:assert/strict';

import { POCKETS, SPOTS, colorOf, spin, settleSpot, getSpot } from '../src/rouletteEngine.ts';
import { seededRng } from '../src/rng.ts';

test('38 pockets: 0, 00, and 1..36', () => {
  assert.equal(POCKETS.length, 38);
  assert.ok(POCKETS.includes('0'));
  assert.ok(POCKETS.includes('00'));
  assert.equal(POCKETS.filter((p) => p !== '0' && p !== '00').length, 36);
});

test('colors: 0/00 green, classic red/black assignments', () => {
  assert.equal(colorOf('0'), 'green');
  assert.equal(colorOf('00'), 'green');
  assert.equal(colorOf('1'), 'red');
  assert.equal(colorOf('2'), 'black');
  assert.equal(colorOf('17'), 'black');
  assert.equal(colorOf('36'), 'red');
  // exactly 18 red and 18 black among 1..36
  const nums = POCKETS.filter((p) => p !== '0' && p !== '00');
  assert.equal(nums.filter((p) => colorOf(p) === 'red').length, 18);
  assert.equal(nums.filter((p) => colorOf(p) === 'black').length, 18);
});

test('spin stays within the pocket set', () => {
  const rng = seededRng(99);
  for (let i = 0; i < 500; i++) {
    assert.ok(POCKETS.includes(spin(rng)));
  }
});

test('board has the expected counts of each spot kind', () => {
  const byKind: Record<string, number> = {};
  for (const s of SPOTS.values()) byKind[s.kind] = (byKind[s.kind] ?? 0) + 1;
  assert.equal(byKind.straight, 38);
  assert.equal(byKind.street, 12);
  assert.equal(byKind.corner, 22);
  assert.equal(byKind.sixline, 11);
  assert.equal(byKind.column, 3);
  assert.equal(byKind.dozen, 3);
  assert.equal(byKind.five, 1);
  // 1:1 outside bets
  for (const k of ['red', 'black', 'even', 'odd', 'low', 'high']) assert.equal(byKind[k], 1);
});

test('every spot has non-empty pockets, all valid', () => {
  for (const s of SPOTS.values()) {
    assert.ok(s.pockets.length > 0, `${s.id} has no pockets`);
    for (const p of s.pockets) assert.ok(POCKETS.includes(p), `${s.id} -> bad pocket ${p}`);
  }
});

test('outside even-money sets are correct sizes', () => {
  assert.equal(getSpot('red')!.pockets.length, 18);
  assert.equal(getSpot('low')!.pockets.length, 18);
  assert.equal(getSpot('high')!.pockets.length, 18);
  assert.equal(getSpot('dz:1')!.pockets.length, 12);
  assert.equal(getSpot('col:1')!.pockets.length, 12);
  assert.deepEqual(getSpot('dz:1')!.pockets, Array.from({ length: 12 }, (_, i) => String(i + 1)));
  // bottom column ends in ...,31,34
  assert.deepEqual(getSpot('col:1')!.pockets, ['1', '4', '7', '10', '13', '16', '19', '22', '25', '28', '31', '34']);
});

test('a real corner exists and covers the 4 numbers', () => {
  const corner = getSpot('co:1'); // {1,2,4,5}
  assert.ok(corner);
  assert.deepEqual([...corner!.pockets].sort(), ['1', '2', '4', '5']);
  assert.equal(corner!.payout, 8);
});

test('settle: straight up pays 35:1', () => {
  assert.deepEqual(settleSpot('s:17', 100, '17'), { won: true, net: 3500, payout: 3600 });
  assert.deepEqual(settleSpot('s:17', 100, '18'), { won: false, net: -100, payout: 0 });
});

test('settle: red wins on red, loses on green 0/00', () => {
  assert.equal(settleSpot('red', 50, '1').won, true);
  assert.equal(settleSpot('red', 50, '2').won, false); // 2 is black
  assert.equal(settleSpot('red', 50, '0').won, false);
  assert.equal(settleSpot('red', 50, '00').won, false);
});

test('settle: dozen and column pay 2:1', () => {
  assert.deepEqual(settleSpot('dz:2', 10, '13'), { won: true, net: 20, payout: 30 });
  assert.equal(settleSpot('dz:2', 10, '12').won, false);
  assert.deepEqual(settleSpot('col:3', 10, '3'), { won: true, net: 20, payout: 30 });
});

test('settle: five-number bet pays 6:1 on 0,00,1,2,3', () => {
  for (const p of ['0', '00', '1', '2', '3']) assert.equal(settleSpot('five', 10, p).won, true);
  assert.deepEqual(settleSpot('five', 10, '0'), { won: true, net: 60, payout: 70 });
  assert.equal(settleSpot('five', 10, '4').won, false);
});

test('settle: unknown spot id throws', () => {
  assert.throws(() => settleSpot('nope', 10, '1'), RangeError);
});
