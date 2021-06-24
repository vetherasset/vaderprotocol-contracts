require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
const secret = require("./.secret.json");

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});


module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    mainnet: {
      url: secret.mainnet.url,
      accounts: [secret.privateKey]
    },
    ropsten: {
      url: secret.ropsten.url,
      accounts: [secret.privateKey]
    },
    kovan: {
      url: secret.kovan.url,
      accounts: [secret.privateKey]
    },
    rinkeby: {
      url: secret.rinkeby.url,
      accounts: [secret.privateKey]
    }
  },
  solidity: {
    version: "0.8.3",
    settings: {
      optimizer: {
        enabled: true
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 20000
  },
  etherscan: {
    apiKey: secret.etherscanKey
  },
}
