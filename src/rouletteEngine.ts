// American roulette engine: 38 pockets (0, 00, 1..36) and the full betting board.
//
// Pure + deterministic (RNG is injected) so it's easy to test and to drive a
// "provably fair" mode later. No card state — a spin is one draw from 38 pockets.
//
// Bets are addressed by a stable **spot id** (e.g. 's:17', 'sp:1-2', 'co:1',
// 'red', 'dz:2'). The server validates a bet by checking the spot id exists and
// settles by checking whether the winning pocket is in that spot's pocket list.
// This keeps adjacency logic (splits/corners/streets) in one precomputed table.

import type { Rng } from './rng.ts';

export type Pocket = string; // '0' | '00' | '1' .. '36'
export type Color = 'red' | 'black' | 'green';

export type SpotKind =
  | 'straight'
  | 'split'
  | 'trio'
  | 'street'
  | 'corner'
  | 'five'
  | 'sixline'
  | 'column'
  | 'dozen'
  | 'red'
  | 'black'
  | 'even'
  | 'odd'
  | 'low'
  | 'high';

export interface Spot {
  id: string;
  kind: SpotKind;
  payout: number; // net winnings multiplier (x:1)
  pockets: Pocket[]; // winning pockets for this spot
}

export interface RouletteSettlement {
  won: boolean;
  net: number; // +winnings on a win, -stake on a loss
  payout: number; // total returned to the wallet (stake + winnings on a win, else 0)
}

export const POCKETS: Pocket[] = ['0', '00', ...Array.from({ length: 36 }, (_, i) => String(i + 1))];

const RED_NUMBERS = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);

export function colorOf(p: Pocket): Color {
  if (p === '0' || p === '00') return 'green';
  return RED_NUMBERS.has(Number(p)) ? 'red' : 'black';
}

/** Draw a winning pocket uniformly from the 38 pockets. */
export function spin(rng: Rng): Pocket {
  return POCKETS[rng.nextInt(POCKETS.length)];
}

// ---- betting board (precomputed once) ----

// Table grid: 3 rows x 12 columns. Column index c = 0..11.
//   row 0 (top)    -> 3c + 3   (…3,6,9 / column 3)
//   row 1 (middle) -> 3c + 2   (…2,5,8 / column 2)
//   row 2 (bottom) -> 3c + 1   (…1,4,7 / column 1)
function numAt(row: number, col: number): number {
  return 3 * col + (3 - row);
}

function buildSpots(): Map<string, Spot> {
  const spots = new Map<string, Spot>();
  const add = (s: Spot): void => {
    spots.set(s.id, s);
  };
  const range = (lo: number, hi: number): Pocket[] =>
    Array.from({ length: hi - lo + 1 }, (_, i) => String(lo + i));

  // straight up — every pocket incl. 0 and 00
  for (const p of POCKETS) add({ id: `s:${p}`, kind: 'straight', payout: 35, pockets: [p] });

  // splits, streets, corners, six-lines across the numeric grid
  for (let c = 0; c < 12; c++) {
    const street = [numAt(2, c), numAt(1, c), numAt(0, c)];
    add({ id: `st:${numAt(2, c)}`, kind: 'street', payout: 11, pockets: street.map(String) });

    // vertical splits within the column (bottom-mid, mid-top)
    addSplit(add, numAt(2, c), numAt(1, c));
    addSplit(add, numAt(1, c), numAt(0, c));

    if (c < 11) {
      // horizontal splits to the next column (one per row)
      for (let row = 0; row < 3; row++) addSplit(add, numAt(row, c), numAt(row, c + 1));

      // corners: lower (rows 1,2) and upper (rows 0,1)
      const lower = [numAt(2, c), numAt(1, c), numAt(2, c + 1), numAt(1, c + 1)];
      const upper = [numAt(1, c), numAt(0, c), numAt(1, c + 1), numAt(0, c + 1)];
      add({ id: `co:${Math.min(...lower)}`, kind: 'corner', payout: 8, pockets: lower.map(String) });
      add({ id: `co:${Math.min(...upper)}`, kind: 'corner', payout: 8, pockets: upper.map(String) });

      // six-line: this street + the next
      const six = [...street, numAt(2, c + 1), numAt(1, c + 1), numAt(0, c + 1)];
      add({ id: `sl:${numAt(2, c)}`, kind: 'sixline', payout: 5, pockets: six.map(String) });
    }
  }

  // zero-row bets (American layout: 0 touches 1,2 — 00 touches 2,3)
  add({ id: 'sp:0-00', kind: 'split', payout: 17, pockets: ['0', '00'] });
  add({ id: 'sp:0-1', kind: 'split', payout: 17, pockets: ['0', '1'] });
  add({ id: 'sp:0-2', kind: 'split', payout: 17, pockets: ['0', '2'] });
  add({ id: 'sp:00-2', kind: 'split', payout: 17, pockets: ['00', '2'] });
  add({ id: 'sp:00-3', kind: 'split', payout: 17, pockets: ['00', '3'] });
  add({ id: 'tr:0-1-2', kind: 'trio', payout: 11, pockets: ['0', '1', '2'] });
  add({ id: 'tr:00-2-3', kind: 'trio', payout: 11, pockets: ['00', '2', '3'] });
  add({ id: 'five', kind: 'five', payout: 6, pockets: ['0', '00', '1', '2', '3'] });

  // columns (2:1)
  add({ id: 'col:1', kind: 'column', payout: 2, pockets: Array.from({ length: 12 }, (_, c) => String(numAt(2, c))) });
  add({ id: 'col:2', kind: 'column', payout: 2, pockets: Array.from({ length: 12 }, (_, c) => String(numAt(1, c))) });
  add({ id: 'col:3', kind: 'column', payout: 2, pockets: Array.from({ length: 12 }, (_, c) => String(numAt(0, c))) });

  // dozens (2:1)
  add({ id: 'dz:1', kind: 'dozen', payout: 2, pockets: range(1, 12) });
  add({ id: 'dz:2', kind: 'dozen', payout: 2, pockets: range(13, 24) });
  add({ id: 'dz:3', kind: 'dozen', payout: 2, pockets: range(25, 36) });

  // even-money outside bets (1:1)
  const all = range(1, 36);
  add({ id: 'red', kind: 'red', payout: 1, pockets: all.filter((p) => colorOf(p) === 'red') });
  add({ id: 'black', kind: 'black', payout: 1, pockets: all.filter((p) => colorOf(p) === 'black') });
  add({ id: 'even', kind: 'even', payout: 1, pockets: all.filter((p) => Number(p) % 2 === 0) });
  add({ id: 'odd', kind: 'odd', payout: 1, pockets: all.filter((p) => Number(p) % 2 === 1) });
  add({ id: 'low', kind: 'low', payout: 1, pockets: range(1, 18) });
  add({ id: 'high', kind: 'high', payout: 1, pockets: range(19, 36) });

  return spots;
}

function addSplit(add: (s: Spot) => void, a: number, b: number): void {
  const lo = Math.min(a, b);
  const hi = Math.max(a, b);
  add({ id: `sp:${lo}-${hi}`, kind: 'split', payout: 17, pockets: [String(lo), String(hi)] });
}

export const SPOTS: Map<string, Spot> = buildSpots();

export function getSpot(id: string): Spot | undefined {
  return SPOTS.get(id);
}

/** Settle one bet against the winning pocket. Throws on an unknown spot id. */
export function settleSpot(spotId: string, amount: number, winning: Pocket): RouletteSettlement {
  const spot = SPOTS.get(spotId);
  if (!spot) throw new RangeError(`unknown roulette spot '${spotId}'`);
  if (spot.pockets.includes(winning)) {
    const net = amount * spot.payout;
    return { won: true, net, payout: amount + net };
  }
  return { won: false, net: -amount, payout: 0 };
}
