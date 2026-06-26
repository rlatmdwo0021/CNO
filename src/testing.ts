// Test helpers: a card source that deals a predefined script of cards,
// so rounds are fully deterministic and individual rules can be asserted.

import type { Card, CardSource, Rank } from './types.ts';

/** Parse "K", "7", "10", "A" into a Card (suit is cosmetic for value tests). */
export function card(rank: Rank, suit: Card['suit'] = 'S'): Card {
  return { rank, suit };
}

/**
 * A CardSource that draws cards in a fixed order. The draw order the engine
 * uses is: Player1, Banker1, Player2, Banker2, [PlayerThird], [BankerThird].
 */
export class ScriptedShoe implements CardSource {
  private pos = 0;
  private readonly cards: Card[];
  constructor(cards: Card[]) {
    this.cards = cards;
  }

  draw(): Card {
    if (this.pos >= this.cards.length) {
      throw new Error('ScriptedShoe ran out of cards');
    }
    return this.cards[this.pos++];
  }
}

/** Build a scripted shoe from ranks, laid out in engine draw order. */
export function scriptByRank(ranks: Rank[]): ScriptedShoe {
  return new ScriptedShoe(ranks.map((r) => card(r)));
}
