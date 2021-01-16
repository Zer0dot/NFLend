require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
const { ffmnemonic, alchemyProjectId, etherscanKey, infuraProjectId } = require("./secrets.json"); 

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    // mainnet: {
    //   url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyProjectId}`,
    //   gasPrice: 45000000000,
    //   gas: 3200000,
    //   accounts: { mnemonic: ffmnemonic }
    // },
    hardhat: {
      // forking: {
      //   url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyProjectId}`,
      //   blockNumber: 11449150
      // }
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${infuraProjectId}`,
      accounts: { mnemonic: ffmnemonic }
    }
  },

  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: etherscanKey
  }
};
