/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { toUsd, expandDecimals, getBlockTime, bigNumberify, zeroAddress} = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js");

use(solidity)

describe("TokenFarm", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let vlp;
    let vela;
    let eVela;
    let tokenFarm;
    let vestingDuration
    let complexRewardPerSec1;
    let complexRewardPerSec2;
    let complexRewardPerSec3;
    let rewardPerSec1
    let rewardPerSec2
    let rewardPerSec3
    let endTimestamp1
    let endTimestamp2
    let endTimestamp3

    before(async function () {
        vestingDuration = 6 * 30 * 24 * 60 * 60
        unbondingPeriod = 14 * 24 * 60 * 60 
        vlp = await deployContract('VLP', [])
        vela = await deployContract('MintableBaseToken', ["Vela Exchange", "VELA", 0])
        eVela = await deployContract('eVELA', [])
        tokenFarm = await deployContract('TokenFarm', [vestingDuration, eVela.address, vela.address])
        await eVela.transferOwnership(tokenFarm.address)
        await vela.transferOwnership(wallet.address);
        const owner = await vela.owner()
        console.log("owner : ", owner, wallet.address)
        await vela.connect(wallet).mint(wallet.address, expandDecimals(10000000, 18)); // mint vela Token
        await vela.connect(wallet).approve(tokenFarm.address,  expandDecimals('10000000', 18)); // VELA approve
        await tokenFarm.depositVelaForVesting(expandDecimals('10000000', 18))
        await vlp.transferOwnership(wallet.address)
        await vlp.connect(wallet).mint(wallet.address, expandDecimals(100000, 18)); // mint eVELA
        let vusd = await deployContract('vUSDC', ['Vested USD', 'VUSD', 0]);
        let vault = await deployContract("Vault", [
            vlp.address,
            vusd.address
        ]);
        let PositionVault = await deployContract("PositionVault", []);
        let settingsManager = await deployContract("SettingsManager",
          [
            PositionVault.address,
            vusd.address,
            tokenFarm.address
          ]
        );
        await vlp.initialize(vault.address, settingsManager.address);
    });

    it ("deploy ComplexRewardPerSec and add pool info to tokenFarm", async () => {
        const pId1 = 0
        const pId2 = 1
        const pId3 = 2
        const currentTimestamp = await getBlockTime(provider);
        endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
        endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
        endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24 
        rewardPerSec1 = expandDecimals(8267, 12)
        rewardPerSec2 = expandDecimals(3858, 12)
        rewardPerSec3 = expandDecimals(3858, 12)
        await vela.connect(wallet).mint(wallet.address, expandDecimals(100000, 18)); // mint vela Token
        await vela.connect(wallet).mint(user0.address, expandDecimals(100, 18)); // mint vela Token
        await vela.connect(wallet).mint(user1.address, expandDecimals(100, 18)); // mint vela Token
        await expect(deployContract("ComplexRewarderPerSec", [
            zeroAddress,
            tokenFarm.address
        ])).to.be.revertedWith("constructor: reward token must be a valid contract")
        await expect(deployContract("ComplexRewarderPerSec", [
            eVela.address,
            zeroAddress
        ])).to.be.revertedWith("constructor: FarmDistributor must be a valid contract")
        const vusd = await deployContract('vUSDC', ['Vested USD', 'VUSD', 0])
        await expect(deployContract("ComplexRewarderPerSec", [
            vusd.address,
            tokenFarm.address
        ])).to.be.revertedWith("constructor: reward token decimals must be inferior to 30")        
        complexRewardPerSec1 = await deployContract("ComplexRewarderPerSec", [
            eVela.address,
            tokenFarm.address
        ])
        complexRewardPerSec2 = await deployContract("ComplexRewarderPerSec", [
            eVela.address,
            tokenFarm.address
        ])
        complexRewardPerSec3 = await deployContract("ComplexRewarderPerSec", [
            eVela.address,
            tokenFarm.address
        ])
        const amount = String(ethers.constants.MaxUint256)
        await eVela.connect(wallet).approve(complexRewardPerSec1.address,  amount); // VLP approve
        await eVela.connect(wallet).approve(complexRewardPerSec2.address,  amount); // VELA approve
        await eVela.connect(wallet).approve(complexRewardPerSec3.address,  amount); // eVELA approve
        await complexRewardPerSec1.add(pId1, currentTimestamp)
        await expect(complexRewardPerSec1.add(pId1, currentTimestamp)).to.be.revertedWith("pool already exists")
        await complexRewardPerSec2.add(pId2, currentTimestamp)
        await complexRewardPerSec3.add(pId3, currentTimestamp)
        expect(await complexRewardPerSec1.currentEndTimestamp(pId1)).eq(0)
        expect(await complexRewardPerSec1.poolRewardsPerSec(pId1)).eq(0)
        await complexRewardPerSec1.addRewardInfo(
            pId1,
            endTimestamp1,
            rewardPerSec1
        )
        await complexRewardPerSec2.addRewardInfo(
            pId2,
            endTimestamp2,
            rewardPerSec2
        )
        await complexRewardPerSec3.addRewardInfo(
            pId3,
            endTimestamp3,
            rewardPerSec3
        )
        await tokenFarm.add(
            vlp.address,
            [complexRewardPerSec1.address],
            true
        )
        await tokenFarm.add(
            vela.address,
            [complexRewardPerSec2.address],
            true
        )
        await tokenFarm.add(
            eVela.address,
            [complexRewardPerSec3.address],
            false
        )
        await expect(tokenFarm.add(
            zeroAddress,
            [complexRewardPerSec3.address],
            false
        )).to.be.revertedWith("add: LP token must be a valid contract")
        await expect(tokenFarm.add(
            eVela.address,
            [zeroAddress],
            false
        )).to.be.revertedWith("add: rewarder must be contract")
        await expect(tokenFarm.add(
            eVela.address,
            [
                complexRewardPerSec1.address,
                complexRewardPerSec2.address,
                complexRewardPerSec3.address,
                complexRewardPerSec1.address,
                complexRewardPerSec2.address,
                complexRewardPerSec3.address,
                complexRewardPerSec1.address,
                complexRewardPerSec2.address,
                complexRewardPerSec3.address,
                complexRewardPerSec1.address,
                complexRewardPerSec2.address
            ],
            false
        )).to.be.revertedWith("add: too many rewarders")
    })

    it("Set RewardTierInfo", async () => {
        const levels = [
          expandDecimals('1000', 18),
          expandDecimals('5000', 18),
          expandDecimals('10000', 18),
          expandDecimals('25000', 18),
          expandDecimals('50000', 18),
          expandDecimals('100000', 18),
          expandDecimals('250000', 18),
          expandDecimals('500000', 18),
          expandDecimals('1000000', 18)
        ]
        const percents = [
          (100 - 2) * 1000,
          (100 - 3) * 1000,
          (100 - 5) * 1000,
          (100 - 10) * 1000,
          (100 - 15) * 1000,
          (100 - 20) * 1000,
          (100 - 30) * 1000,
          (100 - 40) * 1000,
          (100 - 50) * 1000
        ]
        await tokenFarm.updateRewardTierInfo(levels, percents);
        const tierLevelOne = await tokenFarm.tierLevels(0)
        const tierPercentOne = await tokenFarm.tierPercents(0)
        const tierLevelNine = await tokenFarm.tierLevels(8)
        const tierPercentNine = await tokenFarm.tierPercents(8)
        expect(parseFloat(ethers.utils.formatUnits(tierLevelOne, 18))).eq(1000)
        expect(tierPercentOne.toNumber()).eq(98000)
        expect(parseFloat(ethers.utils.formatUnits(tierLevelNine, 18))).eq(1000000)
        expect(tierPercentNine.toNumber()).eq(50000)
    })    

    it ("checking startTimestamp", async () => {
        const passTime = 60 * 60 * 24 * 60
        await ethers.provider.send('evm_increaseTime', [-1 * passTime]);
        await ethers.provider.send('evm_mine');
        const poolRewardsPerSec = await tokenFarm.poolRewardsPerSec(0)
        expect(poolRewardsPerSec.rewardsPerSec[0]).eq(0)
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        const poolRewardsPerSec2 = await tokenFarm.poolRewardsPerSec(0)
        expect(poolRewardsPerSec2.rewardsPerSec[0]).gt(0)
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        const poolRewardsPerSec3 = await tokenFarm.poolRewardsPerSec(0)
        expect(poolRewardsPerSec3.rewardsPerSec[0]).eq(0)
        await ethers.provider.send('evm_increaseTime', [-1 * passTime]);
        await ethers.provider.send('evm_mine');
    })

    it("deposit with pId = 1, enableLock = true ", async () => {
        const pId = 1
        const amount = expandDecimals('100', 18)
        await expect(tokenFarm.deposit(pId, amount))
            .to.be.revertedWith("BoringERC20: TransferFrom failed");
        await vela.approve(tokenFarm.address, amount);
        await tokenFarm.deposit(pId, amount)
    })

    it ("withdraw with lock = false", async () => {
        const pId = 0
        const bigAmount = expandDecimals('10000', 18)
        await expect(tokenFarm.withdraw(pId, bigAmount))
            .to.be.revertedWith("withdraw: user amount not enough");
    })

    it ("withdraw with lock = true", async () => {
        const pId = 1
        const account = wallet.address
        const passTime = 60 * 10
        const amount = expandDecimals('10', 18)
        const amount2 = expandDecimals('105', 18)
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        await expect(tokenFarm.pendingTokens(
            4,
            account
        )).to.be.revertedWith("Pool does not exist")
        const pendingTokens = await tokenFarm.pendingTokens(
            pId,
            account
        )
        await expect(tokenFarm.withdraw(pId, amount2))
            .to.be.revertedWith("withdraw: user amount not enough")
        if (pendingTokens.amounts[0].gte(bigNumberify(0))) {
            await expect(tokenFarm.emergencyWithdraw(pId))
            .to.be.revertedWith("didn't pass cooldownDuration")
            await expect(tokenFarm.withdraw(pId, amount))
                .to.be.revertedWith("didn't pass cooldownDuration")
        }
        const passTime2 = 60 * 60 * 24 * 7
        await ethers.provider.send('evm_increaseTime', [passTime2]);
        await ethers.provider.send('evm_mine');
        const poolTotalLp = await tokenFarm.poolTotalLp(pId)
        const userInfo = await tokenFarm.userInfo(pId, account)
        if (poolTotalLp.gte(amount) && poolTotalLp.gte(userInfo.amount) && userInfo.amount.gte(amount)) {
            await tokenFarm.withdraw(pId, amount)
        }
    })

    it ("emergencyWithdraw", async () => {
        const pId = 1
        await tokenFarm.emergencyWithdraw(pId)
    })

    it ("poolRewardsPerSec", async () => {
        const pId = 1
        const poolRewardsPerSec = await tokenFarm.poolRewardsPerSec(pId)
        expect(poolRewardsPerSec.rewardsPerSec[0]).eq(rewardPerSec2)
    })

    it ("poolLength", async () => {
        expect(await tokenFarm.poolLength()).eq(3)
    })

    it ("poolRewarders", async () => {
        const pId = 1
        const poolRewarders = await tokenFarm.poolRewarders(pId)
        expect(poolRewarders[0]).eq(complexRewardPerSec2.address)
    })

    it ("after expiring the reward Info endtime", async () => {
        expect(await complexRewardPerSec1.currentEndTimestamp(0)).eq(endTimestamp1)
    })

    it ("getTier check", async () => {
        const pId = 1
        const amount_level_one = expandDecimals('5001', 18)
        await vela.approve(tokenFarm.address, amount_level_one)
        await tokenFarm.deposit(pId, amount_level_one)
        expect(await tokenFarm.getTier(pId, wallet.address)).eq((100 - 3) * 1000)
    })

    it ("depositVesting", async () => {
        const eVelaBalanceBefore = await eVela.balanceOf(wallet.address)
        const amount = expandDecimals('100', 18)
        await eVela.approve(tokenFarm.address, amount)
        await expect(tokenFarm.withdrawVesting()).to.be.revertedWith("Vester: vested amount is zero")
        await expect(tokenFarm.depositVesting(0))
            .to.be.revertedWith("Vester: invalid _amount")
        await tokenFarm.depositVesting(amount)
        expect(await tokenFarm.claimable(wallet.address)).eq(0)
        expect(await eVela.balanceOf(wallet.address)).eq(eVelaBalanceBefore.sub(amount))
    })


    it ("updateVestingDuration", async () => {
        const vestingDuration = 365 * 24 * 60 * 60
        const maxVestingDuration = 705 * 24 * 60 * 60
        await expect(tokenFarm.updateVestingDuration(maxVestingDuration))
            .to.be.revertedWith("vesting duration exceeds max")
        await tokenFarm.updateVestingDuration(vestingDuration)
    })

    it ("increase time after depositVesting", async () => {
        const passTime = 60 * 60 * 24 * 30 * 12
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
    })

    it ("Claim", async () => {
        const passTime = 60 * 60 * 24 * 20
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        await tokenFarm.connect(wallet).claim()
    })

    it ("withdrawVesting", async () => {
        const beforeVelaBalance = await vela.balanceOf(wallet.address)
        const vestedAmount = await tokenFarm.getVestedAmount(wallet.address)
        const totalVested = await tokenFarm.getTotalVested(wallet.address)
        expect(await tokenFarm.claimable(wallet.address)).lte(vestedAmount)
        const passTime = 60 * 60 * 24 * 365
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        expect(await tokenFarm.claimable(user0.address)).eq(0)
        const claimableAmount = await tokenFarm.claimable(wallet.address)
        if (claimableAmount.eq(vestedAmount) && totalVested.gte(vestedAmount)) {
            await tokenFarm.withdrawVesting()
            expect(await vela.balanceOf(wallet.address)).eq(beforeVelaBalance.add(vestedAmount))
        }
    })

    it("deposit with pId = 0, enableLock = true ", async () => {
        const pId = 0
        const amount = expandDecimals('1000', 18)
        await expect(tokenFarm.deposit(pId, amount))
            .to.be.revertedWith("BoringERC20: TransferFrom failed");
        await vlp.approve(tokenFarm.address, amount);
        await tokenFarm.deposit(pId, amount)
    })

    it ("getTimeElapsed 1", async () => {
        const from = 100
        const to = 200
        const endTimestamp = 150
        expect(await complexRewardPerSec1.getTimeElapsed(
            from,
            to,
            endTimestamp
        )).eq(endTimestamp-from)
    })

    it ("getTimeElapsed 2 ", async () => {
        const from = 100
        const to = 150
        const endTimestamp = 200
        expect(await complexRewardPerSec1.getTimeElapsed(
            from,
            to,
            endTimestamp
        )).eq(endTimestamp-to)
    })

    it ("getTimeElapsed 3", async () => {
        const from = 200
        const to = 100
        const endTimestamp = 150
        expect(await complexRewardPerSec1.getTimeElapsed(
            from,
            to,
            endTimestamp
        )).eq(0)
    })

    it ("massUpdatePools", async () => {
        await complexRewardPerSec1.massUpdatePools()
    })

    it ("updatePool", async () => {
        const pId = 0
        await complexRewardPerSec1.updatePool(pId)
    })

    it ("withdraw", async () => {
        const pId = 0
        const amount = expandDecimals('100', 18)
        await expect(tokenFarm.withdraw(pId, amount))
            .to.be.revertedWith("didn't pass cooldownDuration")
    })

    it ("withdraw after passing cooldown duration", async () => {
        const pId = 0
        const passTime = 60 * 60 * 24 * 365
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        const amount = expandDecimals('100', 18)
        const beforeBalance = await vlp.balanceOf(wallet.address)
        await tokenFarm.withdraw(pId, amount)
        expect(await vlp.balanceOf(wallet.address)).eq(
            beforeBalance.add(amount)
        )
        await ethers.provider.send('evm_increaseTime', [-1 * passTime]);
    })

    it ("depositVesting", async () => {
        const eVelaBalanceBefore = await eVela.balanceOf(tokenFarm.address)
        const amount = expandDecimals('100', 18)
        await eVela.approve(tokenFarm.address, amount)
        await tokenFarm.depositVesting(amount)
        expect(await eVela.balanceOf(tokenFarm.address))
            .eq(eVelaBalanceBefore.add(amount))
    })

    it ("increase time after depositVesting", async () => {
        const passTime = 60 * 60 * 24
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
    })

    it("Set RewardTierInfo", async () => {
        const levels = [
          expandDecimals('1000', 18),
          expandDecimals('5000', 18),
          expandDecimals('10000', 18),
          expandDecimals('25000', 18),
          expandDecimals('50000', 18),
          expandDecimals('100000', 18),
          expandDecimals('250000', 18),
          expandDecimals('500000', 18),
          expandDecimals('1000000', 18)
        ]
        const percents = [
            (100 - 2) * 1000,
            (100 - 3) * 1000,
            (100 - 5) * 1000,
            (100 - 10) * 1000,
            (100 - 15) * 1000,
            (100 - 20) * 1000,
            (100 - 30) * 1000,
            (100 - 40) * 1000,
            (100 - 50) * 1000
        ]
        await expect(tokenFarm.updateRewardTierInfo(
            [expandDecimals('1000', 18)], 
            [
                (100 - 2) * 1000,
                (100 - 3) * 1000
            ])).to.be.revertedWith("the length should the same");
        await expect(tokenFarm.updateRewardTierInfo(
            [
                expandDecimals('1500', 18),
                expandDecimals('1000', 18)
            ], 
            [
                (100 - 2) * 1000,
                (100 - 3) * 1000
            ])).to.be.revertedWith("levels not sorted");
        await expect(tokenFarm.updateRewardTierInfo(
            [
                expandDecimals('1000', 18),
                expandDecimals('1500', 18)
            ], 
            [
                (120) * 1000,
                (100 - 3) * 1000
            ])).to.be.revertedWith("percents exceed 100%");
        await tokenFarm.updateRewardTierInfo(levels, percents);
        const tierLevelOne = await tokenFarm.tierLevels(0)
        const tierPercentOne = await tokenFarm.tierPercents(0)
        const tierLevelNine = await tokenFarm.tierLevels(8)
        const tierPercentNine = await tokenFarm.tierPercents(8)
        expect(parseFloat(ethers.utils.formatUnits(tierLevelOne, 18))).eq(1000)
        expect(tierPercentOne.toNumber()).eq(98000)
        expect(parseFloat(ethers.utils.formatUnits(tierLevelNine, 18))).eq(1000000)
        expect(tierPercentNine.toNumber()).eq(50000)
    })

    it ("updateCooldownDuration", async () => {
        const cooldownDuration = 1 * 60 * 60
        const maxCooldownDuration = 60 * 60 * 24 * 7 * 5;
        await expect(tokenFarm.updateCooldownDuration(maxCooldownDuration))
            .to.be.revertedWith("cooldown duration exceeds max")
        await tokenFarm.updateCooldownDuration(cooldownDuration)
    })


    it ("harvestMany", async () => {
        const pIdList = [0, 1, 2]
        const maxPIdList = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 
            11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 
            21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 
            31 
        ]
        await expect(tokenFarm.harvestMany(maxPIdList))
            .to.be.revertedWith("harvest many: too many pool ids")
        await tokenFarm.harvestMany(pIdList)
    })

    it ("set", async () => {
        const pId = 0
        const rewarders = [complexRewardPerSec1.address]
        const maxRewarders = [ 
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
            complexRewardPerSec1.address, 
            complexRewardPerSec1.address,
        ]
        await expect(tokenFarm.set(pId, maxRewarders))
            .to.be.revertedWith("set: too many rewarders")
        await expect(tokenFarm.set(pId, [zeroAddress]))
            .to.be.revertedWith("set: rewarder must be contract")
        await tokenFarm.set(pId, rewarders)
    })


    it ("emergencyRewardWithdraw", async () => {
        const amount = expandDecimals('10', 18)
        const pId = 2
        await eVela.connect(wallet).approve(
            tokenFarm.address,  amount); // eVELA approve
        await tokenFarm.deposit(pId, amount)
        complexRewardPerSec3.emergencyRewardWithdraw(
            pId,
            0,
            wallet.address
        )
        await expect(complexRewardPerSec3.emergencyRewardWithdraw(
            pId,
            amount,
            wallet.address
        )).to.be.revertedWith("emergency reward withdraw: not enough reward token")
        await complexRewardPerSec3.emergencyWithdraw(
            amount,
            wallet.address
        )
    })

    it ("ComplexRewardPerSec onVelaReward", async () => {
        const pid = 1
        const user = wallet.address
        const amount = expandDecimals('10', 18)
        await expect(complexRewardPerSec1.onVelaReward(pid, user, amount))
            .to.be.revertedWith("only Distributor can call this function")
    })

    it ("ComplexRewardPerSec addRewardInfo", async () => {
        const currentTimestamp = await getBlockTime(provider);
        const passTime = 60 * 60 * 24 * 30
        await ethers.provider.send('evm_increaseTime', [passTime]);
        await ethers.provider.send('evm_mine');
        const pId = 0
        await expect(complexRewardPerSec1.addRewardInfo(
            pId,
            currentTimestamp + passTime,
            rewardPerSec1
        )).to.be.revertedWith("add reward info: reward period ended")        
    })

    it ("ComplexRewardPerSec addRewardInfo bad new endTimestamp", async ()=> {
        const currentTimestamp = await getBlockTime(provider);
        const endTimestamp = currentTimestamp + 30 * 60 * 60 * 24
        const rewardPerSec = expandDecimals(3858, 12)
        const pId = 4
        const complexRewardPerSec4 = await deployContract("ComplexRewarderPerSec", [
            eVela.address,
            tokenFarm.address
        ])
        const amount = String(ethers.constants.MaxUint256)
        await eVela.connect(wallet).approve(complexRewardPerSec4.address,  amount); // VLP approve
        await complexRewardPerSec4.add(pId, currentTimestamp)
        await complexRewardPerSec4.addRewardInfo(
            pId,
            endTimestamp,
            rewardPerSec
        )
        await expect(complexRewardPerSec4.addRewardInfo(
            pId,
            endTimestamp - 60,
            rewardPerSec
        )).to.be.revertedWith("add reward info: bad new endTimestamp")
    })

    it ("deposit with convert", async () => {
        const amount = expandDecimals('100', 18)
        expect( (await tokenFarm.poolInfo(2)).lpToken ).equal(eVela.address) //pool id=2 for eVela
        await vela.approve(tokenFarm.address, amount)
        let eVELA_balance_before = await eVela.balanceOf(tokenFarm.address)
        expect(tokenFarm.depositWithConvert(2, 0)).to.be.revertedWith("zero amount")
        expect(tokenFarm.depositWithConvert(1, amount)).to.be.revertedWith("target pool not esVELA")
        await tokenFarm.depositWithConvert(2, amount)
        let eVELA_balance_after = await eVela.balanceOf(tokenFarm.address)
        expect(eVELA_balance_after.sub(eVELA_balance_before)).eq(amount)
    })
});