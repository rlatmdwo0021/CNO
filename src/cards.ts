// Card values and the shoe (multi-deck card source).

import type { Card, CardSource, Rank, Suit } from './types.ts';
import { secureRng, type Rng } from './rng.ts';

const SUITS: Suit[] = ['S', 'H', 'D', 'C'];
const RANKS: Rank[] = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

/**
 * Baccarat card value: A=1, 2-9 face value, 10/J/Q/K = 0.
 */
export function cardValue(card: Card): number {
  switch (card.rank) {
    case 'A':
      return 1;
    case '10':
    case 'J':
    case 'Q':
    case 'K':
      return 0;
    default:
      return Number(card.rank);
  }
}

/** Baccarat hand value: sum of card values, mod 10 (0-9). */
export function handValue(cards: Card[]): number {
  return cards.reduce((sum, c) => sum + cardValue(c), 0) % 10;
}

/** Build one ordered 52-card deck. */
export function buildDeck(): Card[] {
  const deck: Card[] = [];
  for (const suit of SUITS) {
    for (const rank of RANKS) {
      deck.push({ rank, suit });
    }
  }
  return deck;
}

/**
 * Multi-deck shoe. Standard baccarat uses 8 decks. A cut-card depth marks
 * when the shoe should be reshuffled before the next round.
 */
export class Shoe implements CardSource {
  private cards: Card[] = [];
  private pos = 0;
  private readonly cutDepth: number;
  private readonly decks: number;
  private readonly rng: Rng;

  constructor(
    decks = 8,
    rng: Rng = secureRng,
    /** Fraction of the shoe to use before reshuffle (e.g. 0.8 = last 20% reserved). */
    cutPenetration = 0.8,
  ) {
    this.decks = decks;
    this.rng = rng;
    this.cutDepth = Math.floor(decks * 52 * cutPenetration);
    this.shuffle();
  }

  /** Rebuild and shuffle all decks (Fisher-Yates). */
  shuffle(): void {
    const cards: Card[] = [];
    for (let i = 0; i < this.decks; i++) cards.push(...buildDeck());
    for (let i = cards.length - 1; i > 0; i--) {
      const j = this.rng.nextInt(i + 1);
      [cards[i], cards[j]] = [cards[j], cards[i]];
    }
    this.cards = cards;
    this.pos = 0;
  }

  draw(): Card {
    if (this.pos >= this.cards.length) {
      throw new Error('Shoe exhausted; call shuffle() before drawing.');
    }
    return this.cards[this.pos++];
  }

  /** True once the cut card is reached — reshuffle before the next round. */
  needsShuffle(): boolean {
    return this.pos >= this.cutDepth;
  }

  remaining(): number {
    return this.cards.length - this.pos;
  }
}
