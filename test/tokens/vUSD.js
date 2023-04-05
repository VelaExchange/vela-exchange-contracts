/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { zeroAddress, expandDecimals } = require("../../scripts/shared/utilities.js")

use(solidity)

describe("vUSD", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let vUSD;

    before(async function () {
        vUSD = await deployContract('VUSD', ['Vested USD', 'VUSD', 0])
    });

    it("transferOwnership", async () => {
        // await expect(vUSD.connect(user0).transferOwnership(user1.address))
        //   .to.be.revertedWith("Ownable: caller is not the owner")
    
        expect(await vUSD.owner()).eq(wallet.address)
    
        // await expect(vUSD.connect(wallet).transferOwnership(zeroAddress))
        //   .to.be.revertedWith("Ownable: new owner is the zero address")
  
        // await vUSD.transferOwnership(user0.address)
        // expect(await vUSD.owner()).eq(user0.address)
    
        // await vUSD.connect(user0).transferOwnership(user1.address)
        // expect(await vUSD.owner()).eq(user1.address)
    })

    // it ("mint", async () => {
    //     const amount = expandDecimals('1000', 30)
    //     await expect(vUSD.connect(user3).mint(user3.address, amount))
    //     .to.be.revertedWith('Ownable: caller is not the owner')
    //     await expect(vUSD.connect(user1).mint(zeroAddress, amount))
    //         .to.be.revertedWith('VUSD: mint to the zero address')
    //     await vUSD.connect(user1).mint(user3.address, amount)
    //     expect(await vUSD.balanceOf(user3.address)).eq(amount)
    // })

    // it ("burn", async () => {
    //     const amount = expandDecimals('1000', 30)
    //     await expect(vUSD.connect(user3).burn(user3.address, amount))
    //         .to.be.revertedWith('Ownable: caller is not the owner')
    //     await vUSD.connect(user1).burn(user3.address, amount)
    //     expect(await vUSD.balanceOf(user3.address)).eq(expandDecimals('0', 1))
    //     await expect(vUSD.connect(user1).burn(zeroAddress, amount))
    //         .to.be.revertedWith('VUSD: burn from the zero address')
    //     await expect(vUSD.connect(user1).burn(user3.address, amount))
    //         .to.be.revertedWith('VUSD: burn amount exceeds balance')
    // })

    // it("setInfo", async () => {
    //     const name = "vUSD"
    //     const symbol = "VUSD"
    //     await expect(vUSD.connect(user3).setInfo(name, symbol))
    //     .to.be.revertedWith('Ownable: caller is not the owner')
    //     await vUSD.connect(user1).setInfo(name, symbol)
    //     expect(await vUSD.name()).eq(name)
    //     expect(await vUSD.symbol()).eq(symbol)
    // })
});