import { InMemoryWallet } from '../src/wallet.ts';
import { walletContract } from './walletContract.ts';

walletContract('memory', async (initial) => new InMemoryWallet(initial));
