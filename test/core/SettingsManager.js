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

describe("SettingsManager", function () {
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
    let closeDeltaTime
    let delayDeltaTime
    let depositFee
    let withdrawFee
    let stakingFee
    let unstakingFee

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
        closeDeltaTime = 2 * 60 * 60;
        delayDeltaTime = 10 * 60
        depositFee = 3000
        withdrawFee = 3000
        stakingFee = 3000
        unstakingFee = 3000
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
    });

    it ("setVaultSettings", async () => {
      const max_cooldown_duration = 49 * 24 * 60 * 60
      const minFeeBasisPoints = 40000
      const maxFeeBasisPoints = 110000
      await expect(settingsManager.setVaultSettings(max_cooldown_duration, feeRewardBasisPoints))
        .to.be.revertedWith("invalid cooldownDuration")
      await expect(settingsManager.setVaultSettings(cooldownDuration, minFeeBasisPoints))
        .to.be.revertedWith("feeRewardsBasisPoints not greater than min")
      await expect(settingsManager.setVaultSettings(cooldownDuration, maxFeeBasisPoints))
        .to.be.revertedWith("feeRewardsBasisPoints not smaller than max")
      await settingsManager.setVaultSettings(cooldownDuration, feeRewardBasisPoints)
    })

    it ("setCloseDeltaTime", async () => {
      const maxCloseDeltaTime = 25 * 60 * 60
      await expect(settingsManager.setCloseDeltaTime(maxCloseDeltaTime))
        .to.be.revertedWith("closeDeltaTime is bigger than max")
      await settingsManager.setCloseDeltaTime(closeDeltaTime)
    })

    it ("setDelayDeltaTime", async () => {
      const maxDelayDeltaTime = 25 * 60 * 60
      await expect(settingsManager.setDelayDeltaTime(maxDelayDeltaTime))
        .to.be.revertedWith("delayDeltaTime is bigger than max")
      await settingsManager.setDelayDeltaTime(delayDeltaTime)
    })

    it ("setDepositFee", async () => {
      await expect(settingsManager.setDepositFee(15000))
        .to.be.revertedWith("deposit fee is bigger than max")
      await settingsManager.setDepositFee(depositFee)
    })

    it ("setWithdrawFee", async () => {
      await expect(settingsManager.setWithdrawFee(15000))
        .to.be.revertedWith("withdraw fee is bigger than max")
      await settingsManager.setWithdrawFee(withdrawFee)
    })

    it ("setEnableDeposit", async () => {
      const token = usdt.address
      await settingsManager.setEnableDeposit(token, true)
    })

    it ("setEnableStaking", async () => {
      const token = usdt.address
      await settingsManager.setEnableStaking(token, true)
    })

    it ("setEnableUnstaking", async () => {
      const token = usdt.address
      await settingsManager.setEnableUnstaking(token, true)
    })

    it ("setFundingInterval", async () => {
      const fundingInterval = 2 * 60 * 60
      const minFundingInterval = 30 * 60
      const maxFundingInterval = 49 * 60 * 60
      await expect(settingsManager.setFundingInterval(minFundingInterval))
        .to.be.revertedWith("fundingInterval should be greater than MIN")
      await expect(settingsManager.setFundingInterval(maxFundingInterval))
        .to.be.revertedWith("fundingInterval should be smaller than MAX")

      await settingsManager.setFundingInterval(fundingInterval)
    })

    it ("setFundingRateFactor", async () => {
      const fundingRateFactor = 200
      const token = btc.address
      const isLong = true
      const maxfundingRateFactor = 12000
      await expect(settingsManager.setFundingRateFactor(token, isLong, maxfundingRateFactor))
        .to.be.revertedWith("fundingRateFactor should be smaller than MAX")
      await settingsManager.setFundingRateFactor(token, isLong, fundingRateFactor)
    })

    it ("setLiquidateThreshold", async () => {
      const newThreshold = 200
      const token = btc.address
      const maxThreshold = 120000
      await expect(settingsManager.setLiquidateThreshold(maxThreshold, token))
        .to.be.revertedWith("threshold should be smaller than MAX")
      await settingsManager.setLiquidateThreshold(newThreshold, token)
    })

    it ("setLiquidationFeeUsd", async () => {
      const liquidationFeeUsd = expandDecimals('2', 30)
      const maxLiquidationFeeUsd = expandDecimals('120', 30)
      await expect(settingsManager.setLiquidationFeeUsd(maxLiquidationFeeUsd))
        .to.be.revertedWith("liquidationFeeUsd should be smaller than MAX")
      await settingsManager.setLiquidationFeeUsd(liquidationFeeUsd)
    })

    it ("setMarginFeeBasisPoints", async () => {
      const btcMarginFeeBasisPoints = 80
      const ethMarginFeeBasisPoints = 80
      const dogeMarginFeeBasisPoints = 80
      const gbpMarginFeeBasisPoints = 8
      const eurMarginFeeBasisPoints = 8
      const jpyMarginFeeBasisPoints = 8
      await expect(settingsManager.setMarginFeeBasisPoints(btc.address, true, 5500))
        .to.be.revertedWith("marginFeeBasisPoints should be smaller than MAX")
      await settingsManager.setMarginFeeBasisPoints(btc.address, true, btcMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(btc.address, false, btcMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(eth.address, true, ethMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(eth.address, false, ethMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(doge.address, true, dogeMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(doge.address, false, dogeMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(gbp.address, true, gbpMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(gbp.address, false, gbpMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(eur.address, true, eurMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(eur.address, false, eurMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(jpy.address, true, jpyMarginFeeBasisPoints)
      await settingsManager.setMarginFeeBasisPoints(jpy.address, false, jpyMarginFeeBasisPoints)
    })

    it ("validatePosition", async () => {
      const _account = wallet.address
      const _indexToken = btc.address
      const _isLong = true
      const _size = 0
      const _collateral = 0
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        0,
        10
      )).to.be.revertedWith("collateral is not zero")
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        10,
        100
      )).to.be.revertedWith("position size should be greater than collateral")
      await settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        _size,
        _collateral
      )
      await settingsManager.setMaxOpenInterestPerSide(
        _isLong,
        10
      )
      await settingsManager.setMaxOpenInterestPerAsset(
        _indexToken,
        10
      )
      await settingsManager.setMaxOpenInterestPerUser(
        10
      )
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        100,
        10
      )).to.be.revertedWith("exceed max open interest per side")
      await settingsManager.setMaxOpenInterestPerSide(
        _isLong,
        100
      )
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        100,
        10
      )).to.be.revertedWith("exceed max open interest per asset per side")
      await settingsManager.setMaxOpenInterestPerAsset(
        _indexToken,
        100
      )
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        100,
        10
      )).to.be.revertedWith("exceed max open interest per user")
      await settingsManager.setMaxOpenInterestPerUser(
        100
      )
      await settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        100,
        50
      )
      await settingsManager.setMaxOpenInterestPerAssetPerSide(
        _indexToken,
        _isLong,
        10
      );
      await expect(settingsManager.validatePosition(
        _account,
        _indexToken,
        _isLong,
        100,
        10
      )).to.be.revertedWith("exceed max open interest per asset per side")
      settingsManager.validatePosition( // should not revert for the other side
        _account,
        _indexToken,
        !_isLong,
        100,
        10
      );
      await settingsManager.setMaxOpenInterestPerAssetPerSide(
        _indexToken,
        _isLong,
        100
      );
    })

    it ("setStakingFee", async () => {
      const fee = 100
      await expect(settingsManager.setStakingFee(15000))
        .to.be.revertedWith("staking fee is bigger than max")
      await settingsManager.setStakingFee(
        fee
      )
    })

    it ("setReferFee", async () => {
      const fee1 = 10000000; // greater than feeDivisor
      await expect(settingsManager.setReferFee(fee1))
        .to.be.revertedWith("fee should be smaller than feeDivider")
      const fee2 = 100; // greater than feeDivisor
      await settingsManager.setReferFee(fee2)
    })

    it ("setReferEnabled", async () => {
      const referEnabled = true
      await settingsManager.setReferEnabled(referEnabled)
    })

    it ("setAssetManagerWallet", async () => {
      await expect(settingsManager.connect(user2).setAssetManagerWallet(user0.address))
        .to.be.revertedWith("Ownable: caller is not the owner")
      await settingsManager.setAssetManagerWallet(user0.address)
    })

    it ("enableForexMarket", async () => {
      await expect(settingsManager.connect(user2).enableForexMarket(false))
        .to.be.revertedWith("not allowed to manage forex")
      await settingsManager.connect(user0).enableForexMarket(true)
    })

    it ("setFeeManager", async () => {
      await expect(settingsManager.connect(user2).setFeeManager(user0.address))
        .to.be.revertedWith("Ownable: caller is not the owner")
      await settingsManager.setFeeManager(user0.address)
    })

    it ("setBountyPercent", async () => {
      await expect(settingsManager.connect(user2).setBountyPercent(25000, 25000, 25000))
        .to.be.revertedWith("Ownable: caller is not the owner")
        await expect(settingsManager.setBountyPercent(50000, 50000, 1000))
        .to.be.revertedWith("invalid bountyPercent")
      await settingsManager.setBountyPercent(25000, 25000, 25000)
    })

    it ("enableMarketOrder", async () => {
      await expect(settingsManager.connect(user2).enableMarketOrder(true))
        .to.be.revertedWith("Ownable: caller is not the owner")
      await settingsManager.enableMarketOrder(true)
    })

    it ("getFundingFee", async () => {
      const _indexToken = btc.address
      const _isLong = true
      const _size = 1000
      const _entryFundingRate = 0
      const fundingFee = await settingsManager.getFundingFee(_indexToken, _isLong, _size, _entryFundingRate)
    })

    it ("getPositionFee", async () => {
      const _indexToken = btc.address
      const _isLong = true
      const _sizeDelta = 10000
      expect(await settingsManager.getPositionFee(_indexToken, _isLong, 0)).eq(0)
      expect(await settingsManager.getPositionFee(_indexToken, _isLong, _sizeDelta)).eq(8)
    })

    it ("delegate", async () => {
      await settingsManager.delegate(
        [user0.address,
        user1.address]
      )
      const allDelegates = await settingsManager.getDelegates(wallet.address)
    })

    it ("checkDelegation", async () => {
      expect(await settingsManager.checkDelegation(
        wallet.address,
        wallet.address
      )).eq(true)
      expect(await settingsManager.checkDelegation(
        wallet.address,
        user1.address
      )).eq(true)
    })

    it ("checkDelegation after undelegate", async () => {
      await settingsManager.undelegate(
        [
          user1.address
        ]
      )
      expect(await settingsManager.checkDelegation(
        wallet.address,
        user1.address
      )).eq(false)
    })

    it ("check onlyVault", async () => {
      const token = btc.address
      const sender = wallet.address
      const isLong = true
      const amount = expandDecimals('10', 30)
      await expect(settingsManager.decreaseOpenInterest(
        token,
        sender,
        isLong,
        amount
      )).to.be.revertedWith("Only vault has access")
    })
});
