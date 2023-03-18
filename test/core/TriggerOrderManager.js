/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { toUsd, expandDecimals, getBlockTime, zeroAddress } = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js")

use(solidity)

describe("TriggerOrderManager", function () {
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
        await expect(deployContract("TriggerOrderManager",
          [
            zeroAddress,
            priceManager.address,
            settingsManager.address
          ]
        )).to.be.revertedWith("positionVault address is invalid")
        await expect(deployContract("TriggerOrderManager",
          [
            PositionVault.address,
            zeroAddress,
            settingsManager.address
          ]
        )).to.be.revertedWith("priceManager address is invalid")
        await expect(deployContract("TriggerOrderManager",
          [
            PositionVault.address,
            priceManager.address,
            zeroAddress
          ]
        )).to.be.revertedWith("settingsManager address is invalid")
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
        //====================== Vault Initialize ==============
        await Vault.setVaultSettings(
          priceManager.address,
          settingsManager.address,
          PositionVault.address
        )
        await PositionVault.initialize(
          priceManager.address,
          settingsManager.address,
          triggerOrderManager.address,
          Vault.address,
          VaultUtils.address
        );
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
        await vlpPriceFeed.setLatestAnswer(toChainlinkPrice(16))
        await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eth.address, ethPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(gbp.address, gbpPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eur.address, eurPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(doge.address, dogePriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(jpy.address, jpyPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(usdc.address, usdcPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(usdt.address, usdtPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(vlp.address, vlpPriceFeed.address, 8)
        const tokens = [
         {
           name: "btc",
           address: btc.address,
           decimals: 18,
           isForex: false,
           priceFeed: btcPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "eth",
           address: eth.address,
           decimals: 18,
           isForex: false,
           priceFeed: ethPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "doge",
           address: doge.address,
           decimals: 18,
           isForex: false,
           priceFeed: dogePriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "gbp",
           address: gbp.address,
           decimals: 18,
           isForex: true,
           priceFeed: gbpPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         },
         {
           name: "eur",
           address: eur.address,
           decimals: 18,
           isForex: true,
           priceFeed: eurPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         },
         {
           name: "jpy",
           address: jpy.address,
           decimals: 18,
           isForex: true,
           priceFeed: jpyPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         },
         {
           name: "usdc",
           address: usdc.address,
           decimals: 18,
           isForex: true,
           priceFeed: usdcPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "usdt",
           address: usdt.address,
           decimals: 18,
           isForex: true,
           priceFeed: usdtPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         }
        ];
        for (const token of tokens) {
         await priceManager.setTokenConfig(
           token.address,
           token.decimals,
           token.maxLeverage,
           token.isForex
         );
       }
        await vlp.transferOwnership(Vault.address); // transferOwnership
     // await VaultUtils.setDepositFee(depositFee);
     // await VaultUtils.setStakingFee(stakingFee);
    });

    it("approve Stable Coins for Vault ", async () => {
     await usdt.connect(wallet).approve(Vault.address, expandDecimals('10000000', 18)); // approve USDT
     await usdc.connect(wallet).approve(Vault.address, expandDecimals('10000000', 18)); // approve USDC
    })

    it ("add Vault as admin", async () => {
     await vusd.transferOwnership(Vault.address); // addAdmin vault
    })

    it ("deploy ComplexRewardPerSec and add pool info to tokenFarm", async () => {
     const pId1 = 0
     const pId2 = 1
     const pId3 = 2
     const currentTimestamp = await getBlockTime(provider);
     const endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
     const endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
     const endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24
     const rewardPerSec1 = expandDecimals(8267, 12)
     const rewardPerSec2 = expandDecimals(3858, 12)
     const rewardPerSec3 = expandDecimals(3858, 12)
     await vela.transferOwnership(wallet.address);
     await eVela.transferOwnership(tokenFarm.address); // transferOwnership
     await vela.connect(wallet).mint(wallet.address, expandDecimals(10000000, 18)); // mint vela Token
     await vela.connect(wallet).approve(tokenFarm.address,  expandDecimals('1000000', 18)); // VELA approve
     await tokenFarm.depositVelaForVesting(expandDecimals('1000000', 18))
     const complexRewardPerSec1 = await deployContract("ComplexRewarderPerSec", [
         eVela.address,
         tokenFarm.address
     ])
     const complexRewardPerSec2 = await deployContract("ComplexRewarderPerSec", [
         eVela.address,
         tokenFarm.address
     ])
     const complexRewardPerSec3 = await deployContract("ComplexRewarderPerSec", [
         eVela.address,
         tokenFarm.address
     ])
     const amount = String(ethers.constants.MaxUint256)
     await eVela.connect(wallet).approve(complexRewardPerSec1.address,  amount); // VLP approve
     await eVela.connect(wallet).approve(complexRewardPerSec2.address,  amount); // VELA approve
     await eVela.connect(wallet).approve(complexRewardPerSec3.address,  amount); // eVELA approve
     await complexRewardPerSec1.add(pId1, currentTimestamp)
     await complexRewardPerSec2.add(pId2, currentTimestamp)
     await complexRewardPerSec3.add(pId3, currentTimestamp)
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
         false
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
       (100 - 2) * 100,
       (100 - 3) * 100,
       (100 - 5) * 100,
       (100 - 10) * 100,
       (100 - 15) * 100,
       (100 - 20) * 100,
       (100 - 30) * 100,
       (100 - 40) * 100,
       (100 - 50) * 100
     ]
     await tokenFarm.updateRewardTierInfo(levels, percents);
     const tierLevelOne = await tokenFarm.tierLevels(0)
     const tierPercentOne = await tokenFarm.tierPercents(0)
     const tierLevelNine = await tokenFarm.tierLevels(8)
     const tierPercentNine = await tokenFarm.tierPercents(8)
     expect(parseFloat(ethers.utils.formatUnits(tierLevelOne, 18))).eq(1000)
     expect(tierPercentOne.toNumber()).eq(9800)
     expect(parseFloat(ethers.utils.formatUnits(tierLevelNine, 18))).eq(1000000)
     expect(tierPercentNine.toNumber()).eq(5000)
    })

    it("set LiquidateThreshod for VaultUtils", async () => {
     const BTCLiquidateThreshold = 990000;
     const BTCMaxOpenInterest = expandDecimals('10000000000', 30)
     const BTCLongFundingRateFactor = 100;
     const BTCShortFundingRateFactor = 100;
     const BTCLongMarginFeeBasisPoints = 80;
     const BTCShortMarginFeeBasisPoints = 80;
     const ETHLiquidateThreshold = 990000;
     const ETHMaxOpenInterest = expandDecimals('10000000000', 30)
     const ETHLongFundingRateFactor = 100;
     const ETHShortFundingRateFactor = 100;
     const ETHLongMarginFeeBasisPoints = 80;
     const ETHShortMarginFeeBasisPoints = 80;
     const GBPLiquidateThreshold = 997000;
     const GBPMaxOpenInterest = expandDecimals('10000000000', 30)
     const GBPLongFundingRateFactor = 100;
     const GBPShortFundingRateFactor = 100;
     const GBPLongMarginFeeBasisPoints = 8;
     const GBPShortMarginFeeBasisPoints = 8;
     const EURLiquidateThreshold = 997000;
     const EURMaxOpenInterest = expandDecimals('10000000000', 30)
     const EURLongFundingRateFactor = 100;
     const EURShortFundingRateFactor = 100;
     const EURLongMarginFeeBasisPoints = 8;
     const EURShortMarginFeeBasisPoints = 8;
     const JPYLiquidateThreshold = 997000;
     const JPYMaxOpenInterest = expandDecimals('10000000000', 30)
     const JPYLongFundingRateFactor = 100;
     const JPYShortFundingRateFactor = 100;
     const JPYLongMarginFeeBasisPoints = 8;
     const JPYShortMarginFeeBasisPoints = 8;
     const DOGELiquidateThreshold = 990000;
     const DOGEMaxOpenInterest = expandDecimals('10000000000', 30)
     const DOGELongFundingRateFactor = 100;
     const DOGEShortFundingRateFactor = 100;
     const DOGELongMarginFeeBasisPoints = 80;
     const DOGEShortMarginFeeBasisPoints = 80;
     const LONGMaxOpenInterest = expandDecimals('1000000000000', 30)
     const SHORTMaxOpenInterest = expandDecimals('1000000000000', 30)
     const USERMaxOpenInterest = expandDecimals('10000000000', 30)
     await settingsManager.setLiquidateThreshold(BTCLiquidateThreshold, btc.address);
     await settingsManager.setMaxOpenInterestPerAsset(btc.address, BTCMaxOpenInterest);
     await settingsManager.setFundingRateFactor(btc.address, true, BTCLongFundingRateFactor);
     await settingsManager.setFundingRateFactor(btc.address, false, BTCShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(btc.address, true, BTCLongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(btc.address, false, BTCShortMarginFeeBasisPoints);
     await settingsManager.setLiquidateThreshold(ETHLiquidateThreshold, eth.address);
     await settingsManager.setMaxOpenInterestPerAsset(eth.address, ETHMaxOpenInterest);
     await settingsManager.setFundingRateFactor(eth.address, true, ETHLongFundingRateFactor);
     await settingsManager.setFundingRateFactor(eth.address, false, ETHShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(eth.address, true, ETHLongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(eth.address, false, ETHShortMarginFeeBasisPoints);
     await settingsManager.setLiquidateThreshold(DOGELiquidateThreshold, doge.address);
     await settingsManager.setMaxOpenInterestPerAsset(doge.address, DOGEMaxOpenInterest);
     await settingsManager.setFundingRateFactor(doge.address, true, DOGELongFundingRateFactor);
     await settingsManager.setFundingRateFactor(doge.address, false, DOGEShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(doge.address, true, DOGELongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(doge.address, false, DOGEShortMarginFeeBasisPoints);
     await settingsManager.setLiquidateThreshold(GBPLiquidateThreshold, gbp.address);
     await settingsManager.setMaxOpenInterestPerAsset(gbp.address, GBPMaxOpenInterest);
     await settingsManager.setFundingRateFactor(gbp.address, true, GBPLongFundingRateFactor);
     await settingsManager.setFundingRateFactor(gbp.address, false, GBPShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(gbp.address, true, GBPLongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(gbp.address, false, GBPShortMarginFeeBasisPoints);
     await settingsManager.setLiquidateThreshold(EURLiquidateThreshold, eur.address);
     await settingsManager.setMaxOpenInterestPerAsset(eur.address, EURMaxOpenInterest);
     await settingsManager.setFundingRateFactor(eur.address, true, EURLongFundingRateFactor);
     await settingsManager.setFundingRateFactor(eur.address, false, EURShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(eur.address, true, EURLongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(eur.address, false, EURShortMarginFeeBasisPoints);
     await settingsManager.setLiquidateThreshold(JPYLiquidateThreshold, jpy.address);
     await settingsManager.setFundingRateFactor(jpy.address, true, JPYLongFundingRateFactor);
     await settingsManager.setFundingRateFactor(jpy.address, false, JPYShortFundingRateFactor);
     await settingsManager.setMarginFeeBasisPoints(jpy.address, true, JPYLongMarginFeeBasisPoints);
     await settingsManager.setMarginFeeBasisPoints(jpy.address, false, JPYShortMarginFeeBasisPoints);
     await settingsManager.setMaxOpenInterestPerUser(USERMaxOpenInterest);
     await settingsManager.setEnableDeposit(usdt.address, true)
     await settingsManager.setEnableStaking(usdt.address, true)
     await settingsManager.setEnableUnstaking(usdt.address, true)
     await settingsManager.setEnableDeposit(usdc.address, true)
     await settingsManager.setEnableStaking(usdc.address, true)
     await settingsManager.setEnableUnstaking(usdc.address, true)
   })

    it("Stake Stable Coins for Vault ", async () => {
     const amount = expandDecimals('100000', 18)
     const vlpBalanceBeforeStake = await vlp.balanceOf(wallet.address)
     const usdtBalanceBeforeStake = await usdt.balanceOf(wallet.address)
     expect(parseFloat(ethers.utils.formatUnits(vlpBalanceBeforeStake, 18))).eq(0)
     expect(parseFloat(ethers.utils.formatUnits(usdtBalanceBeforeStake, 18))).eq(10000000.0)
     await Vault.stake(wallet.address, usdt.address, amount);
     const vlpBalanceAfterStake = await vlp.balanceOf(wallet.address)
     const usdtBalanceAfterStake = await usdt.balanceOf(wallet.address)
    //  expect(parseFloat(ethers.utils.formatUnits(vlpBalanceAfterStake, 18))).eq(6062.5)
     // liquidity fee = 0.3%
     // amountAfterFee = 100000 * 99.7% = 99700 USDT (1USDT = 1usd)
     // VLP Price = 16usd
     // so vlpAmount = 99700 / 16 = 6,231.25
     expect(parseFloat(ethers.utils.formatUnits(usdtBalanceAfterStake, 18))).eq(9900000.0)
     // usdAmount = 10000000 - 100000 = 9900000.0
    })

    it("deposit Stable Coins for Vault ", async () => {
     await usdt.connect(wallet).approve(Vault.address, expandDecimals('100000', 18)); // approve USDT
     await usdc.connect(wallet).approve(Vault.address, expandDecimals('100000', 18)); // approve USDC
     await Vault.deposit(wallet.address, usdt.address, expandDecimals('100000', 18)); // deposit USDT
     await Vault.deposit(wallet.address, usdc.address, expandDecimals('100000', 18)); // deposit USDC
   })

   it ("vlpBalance", async () => {
     const vlpBalanceOf = await vlp.balanceOf(wallet.address)
   })

   // note: this test is completely duplicated from another test in this file
   //    but it is needed for the other tests to not fail
   it ("increasePosition for TakeProfit", async () => {
    const indexToken = btc.address;
    const amountIn = expandDecimals('100', 30)
    const toUsdAmount = expandDecimals('1000', 30)
    const isLong = true
    const takeProfit = '0.0'
    const stopLoss = '0.0'
    const positionType = 0
    const referAddress = ethers.constants.AddressZero;
    const orderType = 0 // M
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
     const passTime = 60 * 60 * 24
     await ethers.provider.send('evm_increaseTime', [passTime]);
     await ethers.provider.send('evm_mine');
   })

   it ("setLatestAnswer for BTC", async () => {
    const lastBtcPrice = await priceManager.getLastPrice(btc.address)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57002'))
   })

   it ("addTriggerOrders 1", async () => {
      const indexToken = btc.address;
      const isLong = true
      const posId = 0
      const isTPs = [
        true,
        false
      ]
      const prices = [
        expandDecimals('57500', 30),
        expandDecimals('54000', 30)
      ]
      const amountPercents = [
        50000,
        100000
      ]
      const newTriggerGasFee = expandDecimals('1', 16)
      await expect(settingsManager.setTriggerGasFee(expandDecimals('1', 18)))
        .to.be.revertedWith("trigger gas fee exceed max")
      await settingsManager.setTriggerGasFee(newTriggerGasFee)
      await expect(triggerOrderManager.addTriggerOrders(
        indexToken,
        isLong,
        posId,
        isTPs,
        prices,
        amountPercents,
        {from: wallet.address, value: 0}
      )).to.be.revertedWith("invalid triggerGasFee")
      await triggerOrderManager.addTriggerOrders(
        indexToken,
        isLong,
        posId,
        isTPs,
        prices,
        amountPercents,
        {from: wallet.address, value: newTriggerGasFee})
      await settingsManager.setTriggerGasFee(0)
   })

   it ("getTriggerOrderInfo", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 0
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo (
      account,
      indexToken,
      isLong,
      posId)
    console.log('triggerOrderInfo: ', triggerOrderInfo.status.toString())
    const triggers = triggerOrderInfo.triggers
    for (let i = 0; i < triggers.length; i++) {
      console.log("i : ", i, triggers[i].isTP, triggers[i].price.toString(), triggers[i].createdAt.toString(), triggers[i].status.toString())
    }
  })

  it ("set PositionManager", async () => {
    await settingsManager.setPositionManager(wallet.address, true)
  })

  it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58000'))
  })

  it ("triggerPosition 1", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 0
    await PositionVault.triggerPosition(
      account,
      indexToken,
      isLong,
      posId)
  })

  it ("getTriggerOrderInfo", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 0
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo (
      account,
      indexToken,
      isLong,
      posId)
  })

  it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58500'))
  })

  it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
  })

  it ("increasePosition for StopLoss", async () => {
    const indexToken = btc.address;
    const amountIn = expandDecimals('100', 30)
    const toUsdAmount = expandDecimals('1000', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    const orderType = 0 // M
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
     const passTime = 60 * 60 * 24
     await ethers.provider.send('evm_increaseTime', [passTime]);
     await ethers.provider.send('evm_mine');
   })

   it ("addTriggerOrders 2", async () => {
      const indexToken = btc.address;
      const isLong = true
      const posId = 1
      const isTPs = [
        true,
        false
      ]
      const prices = [
        expandDecimals('57500', 30),
        expandDecimals('54000', 30)
      ]
      const amountPercents = [
        50000,
        100000
      ]
      await triggerOrderManager.addTriggerOrders(
        indexToken,
        isLong,
        posId,
        isTPs,
        prices,
        amountPercents,
        {from: wallet.address, value: 0}
        )
   })

   it ("getTriggerOrderInfo", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 1
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo (
      account,
      indexToken,
      isLong,
      posId)
   })

  it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('52000'))
  })

  it ("triggerPosition 4", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 1
    await PositionVault.triggerPosition(
      account,
      indexToken,
      isLong,
      posId)
  })

  it ("getTriggerOrderInfo", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 1
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo (
      account,
      indexToken,
      isLong,
      posId)
  })

  it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
  })

  // note: this test is completely duplicated from another test in this file
  //    but it is needed for the other tests to not fail
  it ("increasePosition for StopLoss", async () => {
    const indexToken = btc.address;
    const amountIn = expandDecimals('100', 30)
    const toUsdAmount = expandDecimals('1000', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    const orderType = 0 // M
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
     const passTime = 60 * 60 * 24
     await ethers.provider.send('evm_increaseTime', [passTime]);
     await ethers.provider.send('evm_mine');
   })

   it ("addTriggerOrders 3", async () => {
      const indexToken = btc.address;
      const isLong = true
      const posId = 2
      const isTPs = [
        true,
        false
      ]
      const prices = [
        expandDecimals('57500', 30),
        expandDecimals('54000', 30)
      ]
      const amountPercents = [
        50000,
        100000
      ]
      await triggerOrderManager.addTriggerOrders(
        indexToken,
        isLong,
        posId,
        isTPs,
        prices,
        amountPercents,
        {from: wallet.address, value: 0}
        )
   })

   it ("cancelTriggerOrder", async () => {
    const indexToken = btc.address;
    const isLong = true
    const posId = 2
    const orderId = 1
    await triggerOrderManager.cancelTriggerOrder (
      indexToken,
      isLong,
      posId,
      orderId
      )
   })

   it ("cancelPositionTrigger", async () => {
    const indexToken = btc.address;
    const isLong = true
    const posId = 2
    const triggerOrderInfo = await triggerOrderManager.cancelPositionTrigger (
      indexToken,
      isLong,
      posId)
   })

   it ("getTriggerOrderInfo", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 2
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo (
      account,
      indexToken,
      isLong,
      posId)
   })

   it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58500'))
   })

   it ("triggerPosition 5", async () => {
      const account = wallet.address
      const indexToken = btc.address;
      const isLong = true
      const posId = 1
      await expect(PositionVault.triggerPosition(
        account,
        indexToken,
        isLong,
        posId))
        .to.be.revertedWith("TriggerOrder not Open")
   })

   it ("validateTPSLTriggers for Long", async () => {
    const account = wallet.address
    const token = btc.address
    const isLong = true
    const posId = 2
    expect(await triggerOrderManager.validateTPSLTriggers(account, token, isLong, posId))
      .eq(false)
   })

   it ("validateTPSLTriggers for Short", async () => {
    const account = wallet.address
    const token = btc.address
    const isLong = false
    const posId = 4
     expect(await triggerOrderManager.validateTPSLTriggers(account, token, isLong, posId))
        .eq(false)
   })

   it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
   })

   it ("addTriggerOrdersData with wrong orders or invalid data for Long", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = true
    const pId = 2
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('57500', 30),
      expandDecimals('54000', 30),
      expandDecimals('58500', 30),
      expandDecimals('55000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await expect(triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )).to.be.revertedWith("triggerOrder data are incorrect")
   })

   it ("addTriggerOrdersData with position size = 0 for Long", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = true
    const pId = 4
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('57500', 30),
      expandDecimals('54000', 30),
      expandDecimals('58500', 30),
      expandDecimals('55000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await expect(triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )).to.be.revertedWith("position size should be greater than zero")
   })

   it ("addTriggerOrdersData for Long", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = true
    const pId = 2
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('57500', 30),
      expandDecimals('58000', 30),
      expandDecimals('58500', 30),
      expandDecimals('55000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo(
      account,
      indexToken,
      isLong,
      pId
    )
   })

   it ("triggerPosition trigger not ready for Long", async () => {
    const account = wallet.address
    const token = btc.address
    const isLong = true
    const posId = 2
    await expect(PositionVault.triggerPosition(
      account,
      token,
      isLong,
      posId
    )).to.be.revertedWith("TriggerOrder not Open")
   })

   it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
   })

   it ("increasePosition for Short", async () => {
    const indexToken = btc.address;
    const amountIn = expandDecimals('100', 30)
    const toUsdAmount = expandDecimals('1000', 30)
    const isLong = false
    const referAddress = ethers.constants.AddressZero;
    const orderType = 0 // M
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )

     const lastPosId = await PositionVault.lastPosId()
   })

   it ("addTriggerOrdersData with wrong orders or invalid for Short", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 3
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('56500', 30),
      expandDecimals('56000', 30),
      expandDecimals('59500', 30),
      expandDecimals('58000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await expect(triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )).to.be.revertedWith("triggerOrder data are incorrect")
   })

   it ("addTriggerOrdersData with position size = 0 for Short", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 4
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('57500', 30),
      expandDecimals('54000', 30),
      expandDecimals('58500', 30),
      expandDecimals('55000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await expect(triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )).to.be.revertedWith("position size should be greater than zero")
   })

   it ("addTriggerOrdersData for Short", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 3
    const isTPs = [
      true,
      true,
      true,
      false
    ]
    const prices = [
      expandDecimals('56500', 30),
      expandDecimals('56000', 30),
      expandDecimals('55500', 30),
      expandDecimals('58000', 30),
    ]
    const amountPercents = [
      20000,
      10000,
      10000,
      30000
    ]
    await triggerOrderManager.addTriggerOrders(
      indexToken,
      isLong,
      pId,
      isTPs,
      prices,
      amountPercents,
      {from: wallet.address, value: 0}
    )
    const triggerOrderInfo = await triggerOrderManager.getTriggerOrderInfo(
      account,
      indexToken,
      isLong,
      pId
    )
   })

   it ("triggerPosition trigger not ready for Short", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 3
    await expect(PositionVault.triggerPosition(
      account,
      indexToken,
      isLong,
      pId
    )).to.be.revertedWith("trigger not ready")
   })
   it ("setLatestAnswer for BTC", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56200'))
   })

   it ("validateTPSL for Short after rising price", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 3
    expect(await triggerOrderManager.validateTPSLTriggers(account, indexToken, isLong, pId))
      .eq(true)
   })


   it ("executeTriggerOrders for Short", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = false
    const pId = 3
    const passTime = 60 * 60 * 2
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    await PositionVault.triggerPosition(
      account,
      indexToken,
      isLong,
      pId
    )
   })
});
