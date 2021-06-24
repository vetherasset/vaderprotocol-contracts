require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

const networks = { hardhat: {} };
const etherscan = {};
try {
  const secret = require("./.secret.json");
  for (const network in secret.networks) {
    networks[network] = {
      url: secret.networks[network].url,
      accounts: [secret.privateKey]
    };
  }
  etherscan.apiKey = secret.etherscanKey;
} catch (e) {
  console.log("Couldn't find .secret.json file. You will need it when you deploy contracts");
}

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});


module.exports = {
  defaultNetwork: "hardhat",
  networks,
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
  etherscan
}
