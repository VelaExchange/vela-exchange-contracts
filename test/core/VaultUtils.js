/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { toUsd, expandDecimals, getBlockTime } = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js")

use(solidity)

describe("VaultUtils", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let Vault;
    let VaultUtils;
    let vusd;
    let vlp;
    let vela;
    let eVela;
    let PositionVault;
    let priceManager;
    let settingsManager;
    let triggerOrderManager;
    let tokenFarm;
    let vestingDuration
    let btc
    let eth
    let doge
    let gbp
    let eur
    let jpy
    let usdc
    let usdt
    let btcPriceFeed
    let ethPriceFeed
    let dogePriceFeed
    let gbpPriceFeed
    let eurPriceFeed
    let jpyPriceFeed
    let usdcPriceFeed
    let usdtPriceFeed
    let vlpPriceFeed
    let vaultPriceFeed
    let cooldownDuration
    let feeRewardBasisPoints // FeeRewardBasisPoints 70%

    before(async function () {
        btc = await deployContract("BaseToken", ["Bitcoin", "BTC", 0])
        btcPriceFeed = await deployContract("FastPriceFeed", [])
    
        eth = await deployContract("BaseToken", ["Ethereum", "ETH", 0])
        ethPriceFeed = await deployContract("FastPriceFeed", [])
    
        doge = await deployContract("BaseToken", ["Dogecoin", "DOGE", 0])
        dogePriceFeed = await deployContract("FastPriceFeed", [])

        gbp = await deployContract("BaseToken", ["Pound Sterling", "GBP", 0])
        gbpPriceFeed = await deployContract("FastPriceFeed", [])

        eur = await deployContract("BaseToken", ["Euro", "EUR", 0])
        eurPriceFeed = await deployContract("FastPriceFeed", [])

        jpy = await deployContract("BaseToken", ["Japanese Yan", "JPY", 0])
        jpyPriceFeed = await deployContract("FastPriceFeed", [])

        usdt = await deployContract("BaseToken", ["Tether USD", "USDT", expandDecimals('10000000', 18)])
        usdtPriceFeed = await deployContract("FastPriceFeed", [])

        usdc = await deployContract("BaseToken", ["USD Coin", "USDC", expandDecimals('10000000', 18)])
        usdcPriceFeed = await deployContract("FastPriceFeed", [])
        vlpPriceFeed = await deployContract("FastPriceFeed", [])
        vusd = await deployContract('vUSDC', ['Vested USD', 'VUSD', 0])
        vlp = await deployContract('VLP', [])
        vestingDuration = 6 * 30 * 24 * 60 * 60
        unbondingPeriod = 14 * 24 * 60 * 60 
        cooldownDuration = 86400
        liquidationFeeUsd = toUsd(0) // _liquidationFeeUsd
        fundingInterval = 1 * 60 * 60 // fundingInterval = 8 hours
        fundingRateFactor = 100 //  fundingRateFactor
        feeRewardBasisPoints = 70000 // FeeRewardBasisPoints 70%
        depositFee = 3000
        stakingFee = 3000
        vela = await deployContract('MintableBaseToken', ["Vela Exchange", "VELA", 0])
        eVela = await deployContract('eVELA', [])
        tokenFarm = await deployContract('TokenFarm', [vestingDuration, eVela.address, vela.address])
        vaultPriceFeed = await deployContract("VaultPriceFeed", [])
        Vault = await deployContract("Vault", [
           vlp.address,
           vusd.address
        ]);
        PositionVault = await deployContract("PositionVault", [])        
        priceManager = await deployContract("PriceManager", [
          vaultPriceFeed.address
        ])
        settingsManager = await deployContract("SettingsManager",
          [
            PositionVault.address,
            vusd.address,
            tokenFarm.address
          ]
        )
        triggerOrderManager = await deployContract("TriggerOrderManager",
          [
            PositionVault.address,
            priceManager.address,
            settingsManager.address
          ]
        )
        VaultUtils = await deployContract("VaultUtils", [
          PositionVault.address,
          priceManager.address,
          settingsManager.address
        ]);
    });

});