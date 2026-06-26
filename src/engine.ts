// Server-authoritative baccarat engine (Punto Banco rules).
//
// The engine is the single source of truth: given a card source it deals a
// full round and resolves bets. Clients only animate the result.

import { cardValue, handValue } from './cards.ts';
import type {
  Bet,
  BetSettlement,
  Card,
  CardSource,
  HandState,
  Outcome,
  RoundResult,
} from './types.ts';

/** Net profit multiplier per winning unit staked (stake returned separately). */
export const PAYOUTS = {
  player: 1, // 1:1
  banker: 0.95, // 1:1 minus 5% commission
  tie: 8, // 8:1
  playerPair: 11, // 11:1
  bankerPair: 11, // 11:1
} as const;

function makeHand(cards: Card[]): HandState {
  return {
    cards,
    value: handValue(cards),
    pair: cards.length >= 2 && cards[0].rank === cards[1].rank,
    natural: cards.length === 2 && handValue(cards) >= 8,
  };
}

/**
 * Banker's third-card decision. Evaluated on the banker's TWO-card total and,
 * if the player drew, the value of the player's third card.
 *
 * Standard Punto Banco table:
 *   Banker 0-2: always draw
 *   Banker 3: draw unless player's third card = 8
 *   Banker 4: draw if player's third card in 2-7
 *   Banker 5: draw if player's third card in 4-7
 *   Banker 6: draw if player's third card in 6-7
 *   Banker 7: stand
 * If the player stood (no third card): banker draws on 0-5, stands on 6-7.
 */
export function bankerShouldDraw(
  bankerTwoCardValue: number,
  playerThirdCard: Card | undefined,
): boolean {
  if (playerThirdCard === undefined) {
    return bankerTwoCardValue <= 5;
  }
  const t = cardValue(playerThirdCard); // 0-9
  switch (bankerTwoCardValue) {
    case 0:
    case 1:
    case 2:
      return true;
    case 3:
      return t !== 8;
    case 4:
      return t >= 2 && t <= 7;
    case 5:
      return t >= 4 && t <= 7;
    case 6:
      return t >= 6 && t <= 7;
    default: // 7 (and any natural handled before this is called)
      return false;
  }
}

/**
 * Deal one complete round from the given card source.
 * Draw order matches a real table: P1, B1, P2, B2, then any third cards.
 */
export function playRound(source: CardSource): RoundResult {
  // Real-table deal order is interleaved: Player, Banker, Player, Banker.
  const p1 = source.draw();
  const b1 = source.draw();
  const p2 = source.draw();
  const b2 = source.draw();
  const player: Card[] = [p1, p2];
  const banker: Card[] = [b1, b2];

  const playerNatural = handValue(player) >= 8;
  const bankerNatural = handValue(banker) >= 8;

  // A natural on either side ends the round immediately — no draws.
  if (!playerNatural && !bankerNatural) {
    let playerThird: Card | undefined;
    if (handValue(player) <= 5) {
      playerThird = source.draw();
      player.push(playerThird);
    }
    // Banker decision uses its two-card total and the player's third card.
    if (bankerShouldDraw(handValue(banker), playerThird)) {
      banker.push(source.draw());
    }
  }

  const playerHand = makeHand(player);
  const bankerHand = makeHand(banker);
  const outcome: Outcome =
    playerHand.value > bankerHand.value
      ? 'player'
      : bankerHand.value > playerHand.value
        ? 'banker'
        : 'tie';

  return { player: playerHand, banker: bankerHand, outcome };
}

/**
 * Resolve a single bet against a round result.
 *  - won=true  → payout = stake + winnings
 *  - won=false → payout = 0 (stake lost)
 *  - won=undefined (push) → payout = stake returned
 *
 * Note: on a Tie, player/banker bets PUSH (stake returned), they don't lose.
 */
export function settleBet(bet: Bet, result: RoundResult): BetSettlement {
  const { outcome, player, banker } = result;
  const stake = bet.amount;

  const win = (multiplier: number): BetSettlement => ({
    bet,
    won: true,
    net: Math.round(stake * multiplier),
    payout: stake + Math.round(stake * multiplier),
  });
  const lose = (): BetSettlement => ({ bet, won: false, net: -stake, payout: 0 });
  const push = (): BetSettlement => ({ bet, won: undefined, net: 0, payout: stake });

  switch (bet.type) {
    case 'player':
      if (outcome === 'tie') return push();
      return outcome === 'player' ? win(PAYOUTS.player) : lose();
    case 'banker':
      if (outcome === 'tie') return push();
      return outcome === 'banker' ? win(PAYOUTS.banker) : lose();
    case 'tie':
      return outcome === 'tie' ? win(PAYOUTS.tie) : lose();
    case 'playerPair':
      return player.pair ? win(PAYOUTS.playerPair) : lose();
    case 'bankerPair':
      return banker.pair ? win(PAYOUTS.bankerPair) : lose();
  }
}

/** Resolve a list of bets. */
export function settleBets(bets: Bet[], result: RoundResult): BetSettlement[] {
  return bets.map((bet) => settleBet(bet, result));
}
