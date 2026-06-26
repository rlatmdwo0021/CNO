// Baccarat roadmaps derived from round history.
//
// Two roads implemented here:
//  - Bead Plate (珠盤路): one cell per round, filled top-to-bottom then right.
//  - Big Road (大路):     P/B streaks run downward; a different result starts a
//                          new column; ties attach to the last cell; a streak
//                          that reaches the 6th row turns right ("dragon tail").
//
// Derived roads (Big Eye Boy / Small Road / Cockroach) build on the Big Road
// column structure and are a separate, careful follow-up.

import type { Outcome, RoundResult } from './types.ts';

export const ROAD_ROWS = 6;

/** Minimal per-round record the roads are built from. */
export interface RoundSummary {
  outcome: Outcome;
  playerPair: boolean;
  bankerPair: boolean;
}

export function summarize(result: RoundResult): RoundSummary {
  return {
    outcome: result.outcome,
    playerPair: result.player.pair,
    bankerPair: result.banker.pair,
  };
}

export interface BeadCell {
  row: number;
  col: number;
  outcome: Outcome;
  playerPair: boolean;
  bankerPair: boolean;
}

/** Bead plate: column-major fill, ROAD_ROWS rows per column. */
export function beadPlate(history: RoundSummary[]): { cols: number; cells: BeadCell[] } {
  const cells: BeadCell[] = history.map((h, i) => ({
    row: i % ROAD_ROWS,
    col: Math.floor(i / ROAD_ROWS),
    outcome: h.outcome,
    playerPair: h.playerPair,
    bankerPair: h.bankerPair,
  }));
  const cols = history.length === 0 ? 0 : Math.floor((history.length - 1) / ROAD_ROWS) + 1;
  return { cols, cells };
}

export interface BigRoadCell {
  row: number;
  col: number;
  outcome: 'player' | 'banker'; // ties never get their own cell
  ties: number; // ties that landed on top of this result
  playerPair: boolean;
  bankerPair: boolean;
}

interface Pos {
  row: number;
  col: number;
}

/**
 * Place a sequence of two-category items (e.g. player/banker, or red/blue) into
 * a 6-row grid the "big road" way: a run of the same category goes straight
 * down; a change starts a new column beside the run's origin; a run that hits
 * the bottom row turns right (dragon tail). Shared by the big road and the
 * three derived roads.
 */
export function layoutStreaks(seq: string[]): { cols: number; positions: Pos[] } {
  const positions: Pos[] = [];
  const occupied = new Set<string>();
  const key = (c: number, r: number) => `${c},${r}`;
  const isFree = (c: number, r: number) => !occupied.has(key(c, r));

  let last: string | null = null;
  let col = 0;
  let row = 0;
  let streakStartCol = 0;

  for (const item of seq) {
    if (last === null) {
      col = 0;
      row = 0;
      streakStartCol = 0;
    } else if (item === last) {
      if (row + 1 < ROAD_ROWS && isFree(col, row + 1)) {
        row = row + 1;
      } else {
        let c = col + 1;
        while (!isFree(c, row)) c += 1;
        col = c;
      }
    } else {
      col = streakStartCol + 1;
      row = 0;
      while (!isFree(col, row)) row += 1; // defensive: drop under any tail
      streakStartCol = col;
    }
    occupied.add(key(col, row));
    positions.push({ row, col });
    last = item;
  }

  const cols = positions.reduce((max, p) => Math.max(max, p.col + 1), 0);
  return { cols, positions };
}

/** Player/Banker sequence (ties removed) with per-result metadata. */
function extractPB(history: RoundSummary[]): {
  pb: ('player' | 'banker')[];
  meta: { ties: number; playerPair: boolean; bankerPair: boolean }[];
  leadingTies: number;
} {
  const pb: ('player' | 'banker')[] = [];
  const meta: { ties: number; playerPair: boolean; bankerPair: boolean }[] = [];
  let leadingTies = 0;
  for (const h of history) {
    if (h.outcome === 'tie') {
      if (meta.length > 0) meta[meta.length - 1].ties += 1;
      else leadingTies += 1;
      continue;
    }
    pb.push(h.outcome);
    meta.push({ ties: 0, playerPair: h.playerPair, bankerPair: h.bankerPair });
  }
  return { pb, meta, leadingTies };
}

/**
 * Big Road placement. Returns placed P/B cells (with row/col) plus the number
 * of leading ties that occurred before any P/B result.
 */
export function bigRoad(history: RoundSummary[]): {
  cols: number;
  cells: BigRoadCell[];
  leadingTies: number;
} {
  const { pb, meta, leadingTies } = extractPB(history);
  const { cols, positions } = layoutStreaks(pb);
  const cells: BigRoadCell[] = positions.map((p, i) => ({
    row: p.row,
    col: p.col,
    outcome: pb[i],
    ties: meta[i].ties,
    playerPair: meta[i].playerPair,
    bankerPair: meta[i].bankerPair,
  }));
  return { cols, cells, leadingTies };
}

// ---------------------------------------------------------------------------
// Derived roads: Big Eye Boy (k=1), Small Road (k=2), Cockroach (k=3).
//
// They don't track who won — they measure whether the big road is "regular".
// Each compares the big road's LOGICAL columns (streak lengths, ignoring the
// 6-row wrap / dragon tail) at an offset k, emitting red (regular) or blue
// (irregular), then lays that red/blue sequence out as its own road.
// ---------------------------------------------------------------------------

export type DerivedColor = 'red' | 'blue';
export interface DerivedCell {
  row: number;
  col: number;
  color: DerivedColor;
}
export interface DerivedRoad {
  cols: number;
  cells: DerivedCell[];
}

/** Logical big-road columns: streak lengths + each result's (col,row). */
function logicalColumns(pb: ('player' | 'banker')[]): {
  lengths: number[];
  coords: Pos[];
} {
  const lengths: number[] = [];
  const coords: Pos[] = [];
  let last: string | null = null;
  let col = -1;
  for (const s of pb) {
    if (s !== last) {
      col += 1;
      lengths[col] = 0;
    }
    lengths[col] += 1;
    coords.push({ col, row: lengths[col] - 1 });
    last = s;
  }
  return { lengths, coords };
}

/**
 * Build one derived road at offset k.
 * For each big-road entry, once the road has "started" (first entry at logical
 * (k,1) or (k+1,0)):
 *   - new column (row 0): red if the two preceding columns k apart are equal
 *     length, else blue.
 *   - deeper in a column (row r>=1): red if the column k back also reached this
 *     depth, else blue.
 */
function derivedRoad(pb: ('player' | 'banker')[], k: number): DerivedRoad {
  const { lengths, coords } = logicalColumns(pb);

  let startIdx = -1;
  for (let i = 0; i < coords.length; i++) {
    const { col, row } = coords[i];
    if ((col === k && row === 1) || (col === k + 1 && row === 0)) {
      startIdx = i;
      break;
    }
  }
  if (startIdx === -1) return { cols: 0, cells: [] };

  const marks: DerivedColor[] = [];
  for (let i = startIdx; i < coords.length; i++) {
    const { col: c, row: r } = coords[i];
    const red = r === 0 ? lengths[c - 1] === lengths[c - 1 - k] : lengths[c - k] >= r + 1;
    marks.push(red ? 'red' : 'blue');
  }

  const { cols, positions } = layoutStreaks(marks);
  return { cols, cells: positions.map((p, i) => ({ row: p.row, col: p.col, color: marks[i] })) };
}

/** All three derived roads from round history. */
export function derivedRoads(history: RoundSummary[]): {
  bigEye: DerivedRoad;
  small: DerivedRoad;
  cockroach: DerivedRoad;
} {
  const { pb } = extractPB(history);
  return {
    bigEye: derivedRoad(pb, 1),
    small: derivedRoad(pb, 2),
    cockroach: derivedRoad(pb, 3),
  };
}
