require("dotenv").config({ path: "./.env" });
require("@nomiclabs/hardhat-waffle");
// require("@nomiclabs/hardhat-etherscan")
require("metis-sourcecode-verify");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("solidity-coverage");
require("hardhat-watcher");
require("hardhat-abi-exporter");

const deploymentAccount = process.env.DEPLOYMENT_ACCOUNT_KEY;
const bsc_deploy_key = process.env.BSC_DEPLOY_KEY;
const bsc_test_deploy_key = process.env.BSC_TESTNET_DEPLOY_KEY;
const chainInstance = process.env.CHAIN_INSTANCE;
const etherscan_api_key = process.env.API_KEY;

module.exports = {
  abiExporter: {
    path: "./abis",
    clear: true,
    flat: true,
    // pretty: true,
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    ethereum: {
      url: "https://mainnet.infura.io/v3/149e969a221349be9b2857c1cb9090ef",
      chainId: 1,
      accounts: [`${process.env.ETHEREUM_MAINNET_KEY}`],
    },
    bsc_test: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: [bsc_test_deploy_key],
    },
    arbitrum_one: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: [`${process.env.ARBITRUM_ONE_KEY}`],
    },
    arbitrum_test: {
      url: "https://rinkeby.arbitrum.io/rpc",
      chainId: 421611,
      accounts: [`${process.env.ARBITRUM_TEST_KEY}`],
    },
    arbitrum_goerli: {
      // url: "https://arb-goerli.g.alchemy.com/v2/D0axyS3VDhXeL7lj0edbCBQWGK2xBANK",
      url: "https://goerli-rollup.arbitrum.io/rpc",
      chainId: 421613,
      accounts: [`${process.env.ARBITRUM_TEST_KEY}`],
    },
    matic_test: {
      url: "https://rpc-mumbai.maticvigil.com/",
      chainId: 80001,
      accounts: [`${process.env.MATIC_TESTNET_KEY}`],
      gasPrice: 35000000000,
      saveDeployments: true,
    },
    metis_test: {
      url: "https://rpc-mumbai.maticvigil.com/",
      chainId: 80001,
      accounts: [`${process.env.MATIC_TESTNET_KEY}`],
      gasPrice: 35000000000,
      saveDeployments: true,
    },
    metis_main: {
      url: "https://andromeda.metis.io/?owner=1088",
      chainId: 1088,
      accounts: [`${process.env.METIS_MAINNET_KEY}`],
    },
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: true,
  },
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 360000,
  },
  etherscan: {
    // apiKey:  'JR2C4YFMCBVYYNN1I6KN7HSXU7WJ4BJDQJ' //etherscan_api_key
    apiKey: "S17S94J937UD7NIPEM68FCIHSNHUQJ919P", // arbiscan
    // apiKey:  'QBBAP13HDC5CHXE3HEVRA1KVQ46JRXX6YR' //etherscan_api_key
  },
  watcher: {
    compile: {
      tasks: ["compile"],
      files: ["./contracts"],
      verbose: true,
    },
  },
};
