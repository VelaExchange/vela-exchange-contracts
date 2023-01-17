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

describe("FastPriceFeed", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let btcPriceFeed

    before(async function () {
        btcPriceFeed = await deployContract("FastPriceFeed", [])
    });

    it("setAdmin", async () => {
        await expect(btcPriceFeed.connect(user0).setAdmin(user1.address, true))
            .to.be.revertedWith("PriceFeed: forbidden")
        await btcPriceFeed.connect(wallet).setAdmin(user1.address, true)
        expect(await btcPriceFeed.isAdmin(user1.address)).eq(true)
    })

    it("setDescription", async () => {
        await expect(btcPriceFeed.connect(user0).setDescription('BTC/USD'))
            .to.be.revertedWith("PriceFeed: forbidden")
        await btcPriceFeed.connect(user1).setDescription('BTC/USD')
        expect(await btcPriceFeed.description()).eq('BTC/USD')
    })

    it("setLatestAnswer", async () => {
        await expect(btcPriceFeed.connect(user0).setLatestAnswer(toChainlinkPrice(60000)))
            .to.be.revertedWith("PriceFeed: forbidden")
        await btcPriceFeed.connect(user1).setLatestAnswer(toChainlinkPrice(60000))
        const answer = await btcPriceFeed.latestAnswer()
        expect(parseFloat(ethers.utils.formatUnits(answer, 8))).eq(60000)
    })

    it("getRoundData", async () => {
        const roundId = 1
        const roundData = await btcPriceFeed.getRoundData(roundId)
        const answer = roundData[1]
        const latestAt = roundData[2]
    })

    it ("aggregator", async () => {
        const aggregator = await btcPriceFeed.aggregator()
    })
    
    it("latestRound", async () => {
        const roundData = await btcPriceFeed.latestRound()
    })
});