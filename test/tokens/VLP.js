/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { zeroAddress, expandDecimals } = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js")

use(solidity)

describe("VLP", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let vlp;
    let operator
    const amount = expandDecimals('1000', 6)

    before(async function () {
        vlp = await deployContract('VLP', [])
        let usdc = await deployContract("BaseToken", ["USD Coin", "USDC", expandDecimals('10000000', 6)])
        let vusd = await deployContract('VUSD', ['Vested USD', 'VUSD', 0]);
        operator = await deployContract('ExchangeOperators', [])
        let Vault = await deployContract("Vault", [
            operator.address,
            vlp.address,
            vusd.address
        ]);
        let priceManager = await deployContract("PriceManager", [
            operator.address
        ]);
        vaultPriceFeed = (await ethers.getContractFactory("VaultPriceFeed")).attach(await priceManager.priceFeed())
        let usdcPriceFeed = await deployContract("FastPriceFeed", [])
        await usdcPriceFeed.setLatestAnswer(toChainlinkPrice(1))
        await vaultPriceFeed.setTokenConfig(usdc.address, usdcPriceFeed.address, 8)
        await priceManager.setTokenConfig(
            usdc.address,
            6,
            100 * 10000,
        );
        let vestingDuration = 6 * 30 * 24 * 60 * 60
        let PositionVault = await deployContract("PositionVault", []);
        let vela = await deployContract('MintableBaseToken', ["Vela Exchange", "VELA", 0])
        let eVela = await deployContract('eVELA', [])
        let tokenFarm = await deployContract('TokenFarm', [vestingDuration, eVela.address, vela.address, vlp.address, operator.address])
        let settingsManager = await deployContract("SettingsManager",
          [
            PositionVault.address,
            operator.address,
            vusd.address,
            tokenFarm.address
          ]
        );
        await settingsManager.setEnableStaking(usdc.address, true);
        //await settingsManager.setEnableUnstaking(usdc.address, true);
        await vlp.initialize(Vault.address, settingsManager.address);
        await Vault.setVaultSettings(
            priceManager.address,
            settingsManager.address,
            PositionVault.address,
        );
        await vusd.transferOwnership(Vault.address);
        await vlp.transferOwnership(Vault.address);

        await usdc.connect(wallet).approve(Vault.address,  amount);
        await Vault.stake(wallet.address, usdc.address, amount);
    });

    it ("id", async () => {
        expect(await vlp.id()).eq('VLP')
    })

    it ("cannot transfer before cooldown", async () => {
        await expect(vlp.transfer(user1.address, amount))
          .to.be.revertedWith("cooldown duration not yet passed");
    })

    it ("can transfer after cooldown", async () => {
        const passTime = 60 * 60 * 24 * 365
        await ethers.provider.send('evm_increaseTime', [passTime]);
        vlp.transfer(user1.address, amount);
    })

});
