For deploying smart contracts, you can utilize the scripts in the scripts folder:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat run --network network_name scripts/arbitrum_goerli/deployFinalVault.js
npx hardhat run --network network_name scripts/arbitrum_goerli/deployVaultPriceFeed.js
npx hardhat run --network network_name scripts/arbitrum_goerli/deployVela.js
npx hardhat help
```

A complete list of scripts can be found in the scripts folder:

/scripts/arbitrum for Arbitrum Mainnet

/scripts/arbitrum_goerli for Arbitrum Goerli Testnet

# VELA EXCHANGE

A complete breakdown of our exchange functionality and all contract addresses, functionality and more can be found in our [Gitbook](https://vela-exchange.gitbook.io/vela-knowledge-base/)

## Deployed Contracts

All contracts deployed to Arbitrum Mainnet are detailed at in our [Mainnet Contract Addresses](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-addresses/mainnet)

All contracts deployed to Arbitrum Goerli are detailed at in our [Testnet Contract Addresses](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-addresses/testnet)

## Contract Folders

### Access
The access contracts hold constants for configuration used throughout Vela Exchange as well as the Governable contract which sets up ownership and allows the ability to set admin roles and call admin functions. Detailed explanations and code can be found in the [Access Section](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-functions/access).

### Core
The core contracts hold - you guessed it - the core functionality of Vela Exchange. Our vault contract gives traders the ability to deposit, withdraw, open and close positions, and more. Liquidity providers can call functions to stake and unstake stable tokens, thereby minting VLP. Various settings contracts control the settings and configurations for the vault, pricing feeds for assets, and contracts allowing for the opening and triggering of orders. To see code examples and more detail please visit the [Core Section](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-functions/core).

### Oracle
Vela Exchange asset pricing is based on our own FastPriceFeed, which we operate internally. Asset prices are pulled from the latest data sources and published on chain in real time. You can view our [Oracle Section](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-functions/oracle/fastpricefeed) for more information.

### Staking
In addition to staking in our vault to provide liquidity, we provide various staking options for the VELA token, eVELA and more to earn more rewards and get reduced trading fees. You can see the details on our TokenFarm contract in the [Staking Section](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-functions/staking).

### Tokens
The Vela token ecosystem consists of the VELA token as well as our VLP token for liquidity providers, eVELA for vesting VELA tokens over time, and vUSD which is the collateral token for trading. You can see all of our contract info on the various tokens in our [Tokens Section](https://vela-exchange.gitbook.io/vela-knowledge-base/developers/contract-functions/tokens).
