const HDWalletProvider = require('@truffle/hdwallet-provider');

const fs = require('fs');
const mnemonic = fs.readFileSync('.secret').toString().trim();

module.exports = {
  compilers: {
    solc: {
      version: '0.5.17',
      settings: {
        optimizer: {
          enabled: true,
          runs: 5000000
        }
      }
    }
  },
  networks: {
    ganache: {
      host: '127.0.0.1',
      port: 7545,
      network_id: '*'
    },
    development: {
      host: 'operavm',
      port: 7545,
      network_id: '4002'
    },
    test: {
      provider: () =>
        new HDWalletProvider(mnemonic, `https://rpc.testnet.fantom.network`),
      network_id: 4002
    },
    localhost: {
      host: '127.0.0.1',
      port: '8545',
      network_id: '*'
    }
  },

  plugins: ['truffle-plugin-verify', 'truffle-contract-size'],

  api_keys: {
    ftmscan: 'MUQSNKBT19M2IXGQ18DVDTB42NXWSWNVNV'
  }
};
