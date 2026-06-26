// Random number sources. The engine never calls Math.random() directly so
// that (a) production uses a cryptographically secure source and (b) tests
// can inject a deterministic, seeded source for reproducible rounds.

import { randomInt } from 'node:crypto';

export interface Rng {
  /** Float in [0, 1). */
  next(): number;
  /** Integer in [0, maxExclusive). */
  nextInt(maxExclusive: number): number;
}

/** Cryptographically secure RNG for real play. */
export const secureRng: Rng = {
  next(): number {
    // 53-bit float from two 32-bit secure draws.
    const hi = randomInt(0x100000000);
    const lo = randomInt(0x100000000);
    return (hi * 0x100000000 + lo) / 0x10000000000000000;
  },
  nextInt(maxExclusive: number): number {
    if (maxExclusive <= 0) throw new RangeError('maxExclusive must be > 0');
    return randomInt(maxExclusive);
  },
};

/**
 * Deterministic, seedable RNG (mulberry32). For tests and for a future
 * "provably fair" mode where a published seed reproduces the shuffle.
 */
export function seededRng(seed: number): Rng {
  let state = seed >>> 0;
  const next = (): number => {
    state |= 0;
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    nextInt(maxExclusive: number): number {
      if (maxExclusive <= 0) throw new RangeError('maxExclusive must be > 0');
      return Math.floor(next() * maxExclusive);
    },
  };
}
