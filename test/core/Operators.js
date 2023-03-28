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

describe("Operators", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let operator
    before(async function () {
        operator = await deployContract("ExchangeOperators", [])
    });

    it ("operatorLevel", async () => {
        const operatorLevel = await operator.getOperatorLevel(user0.address)
        console.log("user0 operator Level: ", operatorLevel)

        await operator.transferOwnership(user0.address)
        const operatorLevel2 = await operator.getOperatorLevel(user0.address)
        console.log("user0 operator Level: ", operatorLevel2)

    })

    it("setOperatorLevel", async () => {
        await expect(operator.setOperator(user1.address, 2)).to.be.revertedWith("Not an operator")
        await operator.connect(user0).setOperator(user1.address, 2)
        await expect(operator.connect(user1).setOperator(user2.address, 3)).to.be.revertedWith("Invalid operator")
    })
});
