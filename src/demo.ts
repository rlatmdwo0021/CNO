// End-to-end demo: a table with two players betting over several rounds,
// driven through the full state machine with live wallet balances.
// Run: npm run demo   (or: node src/demo.ts 8)

import { Shoe } from './cards.ts';
import { seededRng } from './rng.ts';
import { InMemoryWallet } from './wallet.ts';
import { Table, type TableLimits } from './round.ts';
import type { Bet, BetType, Card } from './types.ts';

const fmt = (cards: Card[]) => cards.map((c) => c.rank + c.suit).join(' ');
const coins = (n: number) => n.toLocaleString();

const rounds = Number(process.argv[2] ?? 8);

const wallet = new InMemoryWallet({ alice: 1000, bob: 1000 });
const shoe = new Shoe(8, seededRng(2026));
const limits: TableLimits = { minBet: 10, maxBet: 500 };
const table = new Table(shoe, wallet, limits);

// A tiny scripted "strategy" so the demo is deterministic: each player favors
// a market and a stake. (Real clients send these over WebSocket.)
const plan: Array<{ player: string; type: BetType; amount: number }> = [
  { player: 'alice', type: 'player', amount: 100 },
  { player: 'bob', type: 'banker', amount: 100 },
];

console.log(`Table limits ${coins(limits.minBet)}–${coins(limits.maxBet)} | seeded shoe`);
console.log(
  `Start: alice ${coins(await wallet.getBalance('alice'))}, bob ${coins(await wallet.getBalance('bob'))}\n`,
);

for (let i = 0; i < rounds; i++) {
  const round = table.startRound();

  // --- betting window ---
  for (const p of plan) {
    const bet: Bet = { type: p.type, amount: p.amount };
    try {
      await round.placeBet(p.player, bet);
    } catch (err) {
      console.log(`  ${p.player} bet rejected: ${(err as Error).message}`);
    }
  }

  // --- lock + deal + settle ---
  round.lock();
  const { result, settled } = await round.settle();

  const betLines = settled
    .map((s) => {
      const tag = s.settlement.won === undefined ? 'push' : s.settlement.won ? 'WIN' : 'lose';
      const sign = s.settlement.net >= 0 ? '+' : '';
      return `${s.playerId} ${s.bet.type} ${tag}(${sign}${s.settlement.net})`;
    })
    .join('  ');

  console.log(
    `${round.id.padEnd(3)} P[${fmt(result.player.cards)}]=${result.player.value}  ` +
      `B[${fmt(result.banker.cards)}]=${result.banker.value}  => ${result.outcome.toUpperCase().padEnd(6)}  ` +
      betLines,
  );
}

console.log(
  `\nEnd:   alice ${coins(await wallet.getBalance('alice'))}, bob ${coins(await wallet.getBalance('bob'))}`,
);
console.log(
  `Ledger entries: alice ${(await wallet.getLedger('alice')).length}, bob ${(await wallet.getLedger('bob')).length}`,
);
