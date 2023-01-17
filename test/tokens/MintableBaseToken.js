/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { zeroAddress, expandDecimals } = require("../../scripts/shared/utilities.js")

use(solidity)

describe("MintableBaseToken", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let btc;

    before(async function () {
        btc = await await deployContract("MintableBaseToken", ["Bitcoin", "BTC", expandDecimals('0', 18)])
    });

    it("setGov", async () => {
        await expect(btc.connect(user0).setGov(user1.address))
          .to.be.revertedWith("Governable: forbidde")
    
        expect(await btc.gov()).eq(wallet.address)
    
        await expect(btc.connect(wallet).setGov(zeroAddress))
          .to.be.revertedWith("Governable: zero address is invalid")
  
        await btc.setGov(user0.address)
        expect(await btc.gov()).eq(user0.address)
    
        await btc.connect(user0).setGov(user1.address)
        expect(await btc.gov()).eq(user1.address)
    })

    it ("setMinter", async () => {
        await expect(btc.connect(wallet).setMinter(user2.address, true))
            .to.be.revertedWith('Governable: forbidden')
        await btc.connect(user1).setMinter(user2.address, true)
        await btc.connect(user1).setMinter(user2.address, true)
        await expect(btc.connect(user1).setMinter(user2.address, true)).to.be.revertedWith("cant exceed max count")
    })

    it("mint", async () => {
        const amount = expandDecimals('1000', 18)
        await expect(btc.connect(user3).mint(user1.address, amount))
          .to.be.revertedWith('MintableBaseToken: forbidden')
        await expect(btc.connect(user2).mint(zeroAddress, amount))
          .to.be.revertedWith('BaseToken: mint to the zero address')
        await btc.connect(user2).mint(user1.address, amount)
    }) 

    it("burn", async () => {
        const amount = expandDecimals('1000', 18)
        const bigAmount = expandDecimals('10000', 18)
        await expect(btc.connect(user3).burn(user1.address, amount))
          .to.be.revertedWith('MintableBaseToken: forbidden')
        await expect(btc.connect(user2).burn(zeroAddress, amount))
          .to.be.revertedWith('BaseToken: burn from the zero address')
        await expect(btc.connect(user2).burn(user1.address, bigAmount))
          .to.be.revertedWith('BaseToken: burn amount exceeds balance')
        await btc.connect(user2).burn(user1.address, amount)
    }) 
});