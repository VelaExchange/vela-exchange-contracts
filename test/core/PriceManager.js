/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { toUsd, expandDecimals, getBlockTime, zeroAddress} = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js")

use(solidity)

describe("PriceManager", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let vlp;
    let priceManager;
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
        vaultPriceFeed = await deployContract("VaultPriceFeed", [])
        priceManager = await deployContract("PriceManager", [
          vaultPriceFeed.address
        ])
        //================= PriceFeed Prices Initialization ==================
        await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
        await btcPriceFeed.setLatestAnswer(toChainlinkPrice(56300))
        await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))
        await ethPriceFeed.setLatestAnswer(toChainlinkPrice(4000))
        await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3920))
        await ethPriceFeed.setLatestAnswer(toChainlinkPrice(4180))
        await dogePriceFeed.setLatestAnswer(toChainlinkPrice(5))
        await gbpPriceFeed.setLatestAnswer(toChainlinkPrice(15))
        await eurPriceFeed.setLatestAnswer(toChainlinkPrice(1))
        await jpyPriceFeed.setLatestAnswer("1600000")  // 0.016
        await usdtPriceFeed.setLatestAnswer(toChainlinkPrice(1))
        await usdcPriceFeed.setLatestAnswer(toChainlinkPrice(1))
        await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eth.address, ethPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(gbp.address, gbpPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eur.address, eurPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(doge.address, dogePriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(jpy.address, jpyPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(usdc.address, usdcPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(usdt.address, usdtPriceFeed.address, 8)

        const cryptoMaxLeverage = 100 * 10000
        const forexMaxLeverage = 100 * 10000
        await expect(priceManager.setTokenConfig(zeroAddress, 18, cryptoMaxLeverage, true))
            .to.be.revertedWith("Address is wrong")
        await expect(priceManager.setTokenConfig(btc.address, 18, 1, true))
            .to.be.revertedWith("Max Leverage should be greater than Min Leverage")
        await priceManager.setTokenConfig(btc.address, 18, cryptoMaxLeverage, false)
        await expect(priceManager.setTokenConfig(btc.address, 18, cryptoMaxLeverage, false))
            .to.be.revertedWith("already initialized")
        await priceManager.setTokenConfig(eth.address, 18, cryptoMaxLeverage, false)
        await priceManager.setTokenConfig(gbp.address, 18, forexMaxLeverage, true)
        await priceManager.setTokenConfig(eur.address, 18, forexMaxLeverage, true)
        await priceManager.setTokenConfig(doge.address, 18, cryptoMaxLeverage, false)
        await priceManager.setTokenConfig(jpy.address, 18, forexMaxLeverage, false)
        await priceManager.setTokenConfig(usdc.address, 18, cryptoMaxLeverage, false)
        await priceManager.setTokenConfig(usdt.address, 18, cryptoMaxLeverage, false)
    });

    it ("getNextAveragePrice", async () => {
        const _indexToken = btc.address
        const _size = 1000
        const _averagePrice = 100
        const _isLong = true
        const _nextPrice = 150
        const _sizeDelta = 10
        const averagePrice = await priceManager.getNextAveragePrice(_indexToken, _size, _averagePrice, _isLong, _nextPrice, _sizeDelta)
        const _isLong2 = false
        const averagePrice2 = await priceManager.getNextAveragePrice(_indexToken, _size, _averagePrice, _isLong2, _nextPrice, _sizeDelta)
    })

    it ("getDelta", async () => {
        const _indexToken = btc.address
        const _size = 100
        const _averagePrice = 1000
        const _isLong = true
        const delta = await priceManager.getDelta(
            _indexToken, 
            _size,
            _averagePrice,
            _isLong) 
        const _isLong2 = false
        const delta2 = await priceManager.getDelta(
            _indexToken, 
            _size,
            _averagePrice,
            _isLong2) 
        await expect(priceManager.getDelta(
            _indexToken, 
            _size,
            0,
            _isLong2)).to.be.revertedWith("average price should be greater than zero") 
    })


    it ("usdToToken 0", async () => {
        const _indexToken = btc.address
        const usdAmount = 0
        const tokenAmount = await priceManager.usdToToken(
            _indexToken, 
            usdAmount) 
        expect(tokenAmount).eq(0)
    })

    it ("usdToToken not zero", async () => {
        const _indexToken = btc.address
        const usdAmount = 1000
        const tokenAmount = await priceManager.usdToToken(
            _indexToken, 
            usdAmount) 
        // expect(tokenAmount).eq(0)
    })


    it ("tokenToUsd 0", async () => {
        const _indexToken = btc.address
        const tokenAmount = 0
        const usdAmount = await priceManager.tokenToUsd(
            _indexToken, 
            tokenAmount) 
        expect(usdAmount).eq(0)
    })

    it ("tokenToUsd not zero", async () => {
        const _indexToken = btc.address
        const tokenAmount = 1000
        const usdAmount = await priceManager.tokenToUsd(
            _indexToken, 
            tokenAmount) 
        // expect(tokenAmount).eq(0)
    })

    it ("getLastPrice", async () => {
        const _indexToken = btc.address
        const lastPrice = await priceManager.getLastPrice(
            _indexToken) 
    })
});
