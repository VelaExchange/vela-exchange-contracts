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
    let btcPriceId
    let ethPriceId
    let dogePriceId
    let gbpPriceId
    let eurPriceId
    let jpyPriceId
    let usdcPriceId
    let usdtPriceId
    let cooldownDuration
    let feeRewardBasisPoints // FeeRewardBasisPoints 70%
    let pyth
    before(async function () {
        btc = await deployContract("BaseToken", ["Bitcoin", "BTC", 0])
        btcPriceId = "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43"
        eth = await deployContract("BaseToken", ["Ethereum", "ETH", 0])
        ethPriceId = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
        doge = await deployContract("BaseToken", ["Dogecoin", "DOGE", 0])
        dogePriceId = "0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c"
        gbp = await deployContract("BaseToken", ["Pound Sterling", "GBP", 0])
        gbpPriceId = "0x84c2dde9633d93d1bcad84e7dc41c9d56578b7ec52fabedc1f335d673df0a7c1"
        eur = await deployContract("BaseToken", ["Euro", "EUR", 0])
        eurPriceId = "0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b"
        jpy = await deployContract("BaseToken", ["Japanese Yan", "JPY", 0])
        jpyPriceId = "0xef2c98c804ba503c6a707e38be4dfbb16683775f195b091252bf24693042fd52"
        usdt = await deployContract("BaseToken", ["Tether USD", "USDT", expandDecimals('10000000', 18)])
        usdc = await deployContract("BaseToken", ["USD Coin", "USDC", expandDecimals('10000000', 18)])
        usdcPriceId = "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a"
        usdtPriceId = "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b"
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

        priceManager = await deployContract("PriceManager", [
          pyth
        ])
        //================= PriceFeed Prices Initialization ==================
        const cryptoMaxLeverage = 100 * 10000
        const forexMaxLeverage = 100 * 10000
        await expect(priceManager.setTokenConfig(zeroAddress, 18, cryptoMaxLeverage, true, btcPriceId))
            .to.be.revertedWith("Address is wrong")
        await expect(priceManager.setTokenConfig(btc.address, 18, 1, true, btcPriceId))
            .to.be.revertedWith("Max Leverage should be greater than Min Leverage")
        await priceManager.setTokenConfig(btc.address, 18, cryptoMaxLeverage, false, btcPriceId)
        await expect(priceManager.setTokenConfig(btc.address, 18, cryptoMaxLeverage, false, btcPriceId))
            .to.be.revertedWith("already initialized")
        await priceManager.setTokenConfig(eth.address, 18, cryptoMaxLeverage, false, ethPriceId)
        await priceManager.setTokenConfig(gbp.address, 18, forexMaxLeverage, true, gbpPriceId)
        await priceManager.setTokenConfig(eur.address, 18, forexMaxLeverage, true, eurPriceId)
        await priceManager.setTokenConfig(doge.address, 18, cryptoMaxLeverage, false, dogePriceId)
        await priceManager.setTokenConfig(jpy.address, 18, forexMaxLeverage, false, jpyPriceId)
        await priceManager.setTokenConfig(usdc.address, 18, cryptoMaxLeverage, false, usdcPriceId)
        await priceManager.setTokenConfig(usdt.address, 18, cryptoMaxLeverage, false, usdtPriceId)
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
