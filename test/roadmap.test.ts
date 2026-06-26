import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  beadPlate,
  bigRoad,
  derivedRoads,
  summarize,
  type RoundSummary,
} from '../src/roadmap.ts';
import { playRound } from '../src/engine.ts';
import { scriptByRank } from '../src/testing.ts';

// Build history from a compact string: P=player, B=banker, T=tie.
function hist(seq: string): RoundSummary[] {
  const map: Record<string, RoundSummary['outcome']> = { P: 'player', B: 'banker', T: 'tie' };
  return [...seq].map((ch) => ({ outcome: map[ch], playerPair: false, bankerPair: false }));
}

const at = (cells: { row: number; col: number }[]) => cells.map((c) => [c.col, c.row]);

test('summarize pulls outcome + pairs from a round result', () => {
  // P:7,7 pair; B:9 natural ends round
  const r = playRound(scriptByRank(['7', '9', '7', 'K']));
  assert.deepEqual(summarize(r), { outcome: 'banker', playerPair: true, bankerPair: false });
});

// --- bead plate ---

test('bead plate fills top-to-bottom then next column', () => {
  const { cols, cells } = beadPlate(hist('PBPBPBP')); // 7 rounds
  assert.equal(cols, 2);
  assert.deepEqual(at(cells), [
    [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], // column 0
    [1, 0], // column 1
  ]);
});

test('empty history yields no columns', () => {
  assert.deepEqual(beadPlate([]), { cols: 0, cells: [] });
  assert.deepEqual(bigRoad([]).cells, []);
});

// --- big road ---

test('alternating results make one cell per column', () => {
  const { cols, cells } = bigRoad(hist('PBPB'));
  assert.equal(cols, 4);
  assert.deepEqual(at(cells), [[0, 0], [1, 0], [2, 0], [3, 0]]);
});

test('a streak runs straight down one column', () => {
  const { cols, cells } = bigRoad(hist('PPP'));
  assert.equal(cols, 1);
  assert.deepEqual(at(cells), [[0, 0], [0, 1], [0, 2]]);
});

test('different result opens a new column at row 0', () => {
  const { cells } = bigRoad(hist('PPB'));
  assert.deepEqual(at(cells), [[0, 0], [0, 1], [1, 0]]);
});

test('a 7-long streak turns the dragon tail to the right', () => {
  const { cols, cells } = bigRoad(hist('BBBBBBB'));
  assert.equal(cols, 2);
  assert.deepEqual(at(cells), [
    [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], // fills column 0
    [1, 5], // 7th turns right along the bottom row
  ]);
});

test('opposite result after a dragon tail starts beside the streak origin', () => {
  const { cells } = bigRoad(hist('BBBBBBBP'));
  const p = cells[cells.length - 1];
  assert.deepEqual([p.col, p.row], [1, 0]); // top of column 1, above the tail at (1,5)
});

test('ties attach to the previous cell as a count', () => {
  const { cells, leadingTies } = bigRoad(hist('PTTB'));
  assert.equal(leadingTies, 0);
  assert.equal(cells[0].ties, 2); // two ties on the player cell
  assert.equal(cells[1].outcome, 'banker');
  assert.deepEqual(at(cells), [[0, 0], [1, 0]]);
});

test('leading ties (before any P/B) are counted separately', () => {
  const { cells, leadingTies } = bigRoad(hist('TTP'));
  assert.equal(leadingTies, 2);
  assert.deepEqual(at(cells), [[0, 0]]);
});

test('pair flags ride along on the big road cell', () => {
  const h: RoundSummary[] = [{ outcome: 'player', playerPair: true, bankerPair: false }];
  const { cells } = bigRoad(h);
  assert.equal(cells[0].playerPair, true);
  assert.equal(cells[0].bankerPair, false);
});

// --- derived roads ---

const colors = (cells: { color: string }[]) => cells.map((c) => c.color);

test('big eye boy: regular-then-irregular sequence', () => {
  // pb = B B P P P B  → logical lengths [2,3,1]
  // start at P(col1,row1): red(col0 had row1) , blue(col0 no row2), blue(new col 3!=2)
  const { bigEye } = derivedRoads(hist('BBPPPB'));
  assert.deepEqual(colors(bigEye.cells), ['red', 'blue', 'blue']);
});

test('perfect alternation makes the derived roads all red', () => {
  // Alternating = maximally predictable.
  const { bigEye, small, cockroach } = derivedRoads(hist('PBPBPB'));
  assert.deepEqual(colors(bigEye.cells), ['red', 'red', 'red', 'red']); // starts at col2
  assert.deepEqual(colors(small.cells), ['red', 'red', 'red']); // starts at col3
  assert.deepEqual(colors(cockroach.cells), ['red', 'red']); // starts at col4
});

test('repeating unequal columns make blue marks', () => {
  // pb = P P B P P B → lengths [2,1,2,1]; big eye starts at B(col1)... actually col2,row0.
  const { bigEye } = derivedRoads(hist('PPBPPB'));
  assert.deepEqual(colors(bigEye.cells), ['blue', 'blue', 'blue']);
});

test('ties do not affect the derived roads', () => {
  assert.deepEqual(
    colors(derivedRoads(hist('BBPPPB')).bigEye.cells),
    colors(derivedRoads(hist('BTBPPTPB')).bigEye.cells),
  );
});

test('derived roads are empty until enough columns exist', () => {
  const { bigEye, small, cockroach } = derivedRoads(hist('PP')); // one column
  assert.deepEqual(bigEye.cells, []);
  assert.deepEqual(small.cells, []);
  assert.deepEqual(cockroach.cells, []);
});

test('derived marks lay out as their own streak road', () => {
  // bigEye marks for BBPPPB = [red, blue, blue] -> red(0,0), blue(1,0), blue(1,1)
  const { bigEye } = derivedRoads(hist('BBPPPB'));
  assert.deepEqual(at(bigEye.cells), [[0, 0], [1, 0], [1, 1]]);
});
