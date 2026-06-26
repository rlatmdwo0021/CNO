import { test } from 'node:test';
import assert from 'node:assert/strict';

import { playRound, settleBet, settleBets, bankerShouldDraw } from '../src/engine.ts';
import { handValue, cardValue } from '../src/cards.ts';
import { scriptByRank, card } from '../src/testing.ts';
import type { Rank } from '../src/types.ts';

// Draw order in every script: P1, B1, P2, B2, [P3], [B3].

test('card values: A=1, 10/face=0, others face value', () => {
  assert.equal(cardValue(card('A')), 1);
  assert.equal(cardValue(card('10')), 0);
  assert.equal(cardValue(card('K')), 0);
  assert.equal(cardValue(card('7')), 7);
});

test('hand value is sum mod 10', () => {
  assert.equal(handValue([card('7'), card('8')]), 5); // 15 -> 5
  assert.equal(handValue([card('K'), card('9')]), 9);
  assert.equal(handValue([card('5'), card('5')]), 0); // 10 -> 0
});

test('natural 9 beats natural 8, no third cards', () => {
  // P: 4+5=9, B: 5+3=8
  const r = playRound(scriptByRank(['4', '5', '5', '3']));
  assert.equal(r.player.value, 9);
  assert.equal(r.banker.value, 8);
  assert.equal(r.player.cards.length, 2);
  assert.equal(r.banker.cards.length, 2);
  assert.equal(r.player.natural, true);
  assert.equal(r.outcome, 'player');
});

test('player stands on 6-7, banker draws on 0-5', () => {
  // P: 3+4=7 (stands). B: 2+3=5 -> draws because player stood.
  // B third card = 9 -> banker 5+9=14 -> 4. Player 7 wins.
  const r = playRound(scriptByRank(['3', '2', '4', '3', '9']));
  assert.equal(r.player.cards.length, 2);
  assert.equal(r.banker.cards.length, 3);
  assert.equal(r.player.value, 7);
  assert.equal(r.banker.value, 4);
  assert.equal(r.outcome, 'player');
});

test('player draws on 0-5', () => {
  // P: 2+3=5 -> draws. B: 3+3=6 -> with player third, banker 6 draws only on 6/7.
  // Player third = K(0) -> player 5. Banker 6 stands (third card 0). Banker wins 6>5.
  const r = playRound(scriptByRank(['2', '3', '3', '3', 'K']));
  assert.equal(r.player.cards.length, 3);
  assert.equal(r.player.value, 5);
  assert.equal(r.banker.cards.length, 2);
  assert.equal(r.banker.value, 6);
  assert.equal(r.outcome, 'banker');
});

// --- bankerShouldDraw rule table (banker drew after a player third card) ---

test('banker third-card rule table', () => {
  // [bankerTwoCardValue, playerThirdRank, expectedDraw]
  const cases: Array<[number, Rank, boolean]> = [
    [0, 'A', true],
    [2, 'K', true],
    [3, '8', false], // banker 3 stands only vs player third 8
    [3, '7', true],
    [4, 'A', false], // banker 4 draws vs 2-7
    [4, '2', true],
    [4, '8', false],
    [5, '3', false], // banker 5 draws vs 4-7
    [5, '4', true],
    [6, '5', false], // banker 6 draws vs 6-7
    [6, '6', true],
    [7, '6', false], // banker 7 always stands
  ];
  for (const [bankerVal, thirdRank, expected] of cases) {
    assert.equal(
      bankerShouldDraw(bankerVal, card(thirdRank)),
      expected,
      `banker ${bankerVal} vs player third ${thirdRank}`,
    );
  }
});

test('banker stands on 6-7 when player stood (no third card)', () => {
  assert.equal(bankerShouldDraw(6, undefined), false);
  assert.equal(bankerShouldDraw(5, undefined), true);
});

// --- settlement ---

test('player bet wins 1:1', () => {
  const r = playRound(scriptByRank(['4', '5', '5', '3'])); // player 9 wins
  const s = settleBet({ type: 'player', amount: 100 }, r);
  assert.equal(s.won, true);
  assert.equal(s.net, 100);
  assert.equal(s.payout, 200);
});

test('banker bet wins with 5% commission', () => {
  const r = playRound(scriptByRank(['2', '3', '3', '3', 'K'])); // banker wins
  const s = settleBet({ type: 'banker', amount: 100 }, r);
  assert.equal(s.won, true);
  assert.equal(s.net, 95); // 0.95 commission
  assert.equal(s.payout, 195);
});

test('player/banker bets PUSH on a tie', () => {
  // P: 5+4=9, B: 4+5=9 -> tie, both naturals.
  const r = playRound(scriptByRank(['5', '4', '4', '5']));
  assert.equal(r.outcome, 'tie');
  const p = settleBet({ type: 'player', amount: 100 }, r);
  const b = settleBet({ type: 'banker', amount: 100 }, r);
  assert.equal(p.won, undefined);
  assert.equal(p.payout, 100); // stake returned
  assert.equal(b.payout, 100);
});

test('tie bet wins 8:1 on tie, loses otherwise', () => {
  const tieRound = playRound(scriptByRank(['5', '4', '4', '5']));
  const win = settleBet({ type: 'tie', amount: 100 }, tieRound);
  assert.equal(win.net, 800);
  assert.equal(win.payout, 900);

  const nonTie = playRound(scriptByRank(['4', '5', '5', '3']));
  const lose = settleBet({ type: 'tie', amount: 100 }, nonTie);
  assert.equal(lose.won, false);
  assert.equal(lose.payout, 0);
});

test('player pair side bet pays 11:1', () => {
  // P: 7,7 (pair) ... B: 9,K -> banker 9 natural, ends round.
  const r = playRound(scriptByRank(['7', '9', '7', 'K']));
  assert.equal(r.player.pair, true);
  const s = settleBet({ type: 'playerPair', amount: 100 }, r);
  assert.equal(s.net, 1100);
  assert.equal(s.payout, 1200);
});

test('settleBets resolves multiple bets at once', () => {
  const r = playRound(scriptByRank(['4', '5', '5', '3'])); // player wins, no pairs
  const results = settleBets(
    [
      { type: 'player', amount: 50 },
      { type: 'banker', amount: 50 },
      { type: 'tie', amount: 10 },
    ],
    r,
  );
  assert.equal(results[0].payout, 100); // player win
  assert.equal(results[1].payout, 0); // banker lose
  assert.equal(results[2].payout, 0); // tie lose
});
