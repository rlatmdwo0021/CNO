// Core domain types for the baccarat engine.
// Kept framework-agnostic so the same rules can run on the Node backend
// and (compiled) be reused by the web client.

export type Suit = 'S' | 'H' | 'D' | 'C'; // Spades, Hearts, Diamonds, Clubs
export type Rank =
  | 'A' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '10' | 'J' | 'Q' | 'K';

export interface Card {
  rank: Rank;
  suit: Suit;
}

/** Who wins a baccarat round. */
export type Outcome = 'player' | 'banker' | 'tie';

/** Bet markets a player can wager on. */
export type BetType =
  | 'player'
  | 'banker'
  | 'tie'
  | 'playerPair'
  | 'bankerPair';

export interface Bet {
  type: BetType;
  /** Stake in coins (integer). */
  amount: number;
}

/** A single side's hand after all draws are resolved. */
export interface HandState {
  cards: Card[];
  /** Baccarat value (sum of card values mod 10), 0-9. */
  value: number;
  /** First two cards share a rank. */
  pair: boolean;
  /** Two-card 8 or 9 (no third card is drawn). */
  natural: boolean;
}

/** Full, server-authoritative outcome of one round. */
export interface RoundResult {
  player: HandState;
  banker: HandState;
  outcome: Outcome;
}

/** Resolution of a single bet against a round result. */
export interface BetSettlement {
  bet: Bet;
  /** true win, false loss, undefined = push (stake returned). */
  won: boolean | undefined;
  /** Net coin change for this bet (negative = lost stake). On push, 0. */
  net: number;
  /** Coins returned to the player's wallet (stake + winnings, or stake on push). */
  payout: number;
}

/** A source of cards. Real play uses Shoe; tests use a scripted source. */
export interface CardSource {
  draw(): Card;
}
