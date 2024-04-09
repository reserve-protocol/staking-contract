import "tsconfig-paths/register";
import type { HardhatUserConfig } from "hardhat/config";
import type { SolcUserConfig } from "hardhat/types";

import { parseEther } from "viem";

import "@nomicfoundation/hardhat-toolbox-viem";
import "hardhat-contract-sizer";

const MNEMONIC = "test test test test test test test test test test test junk";

const COMPILER_OPTIONS: SolcUserConfig[] = [
  {
    version: "0.8.24",
    settings: {
      evmVersion: "paris",
      optimizer: {
        enabled: true,
        runs: 200,
      },
      // viaIR: true,
      metadata: {
        bytecodeHash: "none",
      },
    },
  },
];

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
  },
  networks: {
    hardhat: {
      // loggingEnabled: true,
      forking: {
        url: "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      },
      accounts: {
        mnemonic: MNEMONIC,
        accountsBalance: parseEther("1000").toString(),
      },
    },
    local: {
      url: "http://localhost:8545",
      timeout: 0,
      accounts: {
        mnemonic: MNEMONIC,
      },
    },
    ethereum: {
      url: "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      accounts: {
        mnemonic: MNEMONIC,
      },
    },
  },
  solidity: {
    compilers: COMPILER_OPTIONS,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
};

export default config;
