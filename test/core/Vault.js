/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle")
const { ethers, upgrades } = require("hardhat");

const { deployContract } = require("../../scripts/shared/helpers.js")
const { toUsd, expandDecimals, getBlockTime, bigNumberify, zeroAddress } = require("../../scripts/shared/utilities.js")
const { toChainlinkPrice } = require("../../scripts/shared/chainlink.js")

use(solidity)

describe("Vault", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
    let trustForwarder;
    let Vault;
    let VaultUtils;
    let vusd;
    let vlp;
    let vela;
    let eVela;
    let priceManager;
    let settingsManager;
    let triggerOrderManager;
    let feeManagerAddress;
    let positionManagerAddress;
    let tokenFarm;
    let vestingDuration

    let btc
    let eth
    let doge
    let gbp
    let eur
    let jpy
    let usdc

    let depositFee
    let stakingFee

    let BASIS_POINTS_DIVISOR;
    let PRICE_PRECISION;
    let btcPriceFeed
    let ethPriceFeed
    let dogePriceFeed
    let gbpPriceFeed
    let eurPriceFeed
    let jpyPriceFeed
    let usdcPriceFeed
    let vaultPriceFeed
    let cooldownDuration
    let feeRewardBasisPoints // FeeRewardBasisPoints 70%

    before(async function () {
        trustForwarder = user3.address
        positionManagerAddress = user1.address
        feeManagerAddress = user3.address
        BASIS_POINTS_DIVISOR = 100000
        PRICE_PRECISION = expandDecimals ('1', 30)
        vestingDuration = 6 * 30 * 24 * 60 * 60
        unbondingPeriod = 14 * 24 * 60 * 60 
        cooldownDuration = 86400
        liquidationFeeUsd = toUsd(0) // _liquidationFeeUsd
        fundingInterval = 1 * 60 * 60 // fundingInterval = 8 hours
        fundingRateFactor = 100 //  fundingRateFactor
        feeRewardBasisPoints = 70000 // FeeRewardBasisPoints 70%
        depositFee = 300  // 0.3%
        stakingFee = 300  // 0.3%
        btc = await deployContract("BaseToken", ["Bitcoin", "BTC", expandDecimals('10', 18)])
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

        usdc = await deployContract("BaseToken", ["USD Coin", "USDC", expandDecimals('10000000', 18)])
        usdcPriceFeed = await deployContract("FastPriceFeed", [])

        vlpPriceFeed = await deployContract("FastPriceFeed", [])
        vusd = await deployContract('vUSDC', ['Vested USD', 'VUSD', 0])
        vlp = await deployContract('VLP', [])
        vela = await deployContract('Vela', [trustForwarder])
        eVela = await deployContract('eVELA', [])
        tokenFarm = await deployContract('TokenFarm', [vestingDuration, eVela.address, vela.address])
        vaultPriceFeed = await deployContract("VaultPriceFeed", [])
        Vault = await deployContract("Vault", [
           vlp.address,
           vusd.address,
           tokenFarm.address
        ]);
        priceManager = await deployContract("PriceManager", [
          vaultPriceFeed.address
        ])
        settingsManager = await deployContract("SettingsManager",
          [
            Vault.address,
            vusd.address
          ]
        )
        triggerOrderManager = await deployContract("TriggerOrderManager",
          [
            Vault.address,
            priceManager.address
          ]
        )
        await expect(deployContract("VaultUtils", [
          zeroAddress,
          vusd.address,
          tokenFarm.address,
          priceManager.address,
          settingsManager.address
        ])).to.be.revertedWith("vault address is invalid");
        await expect(deployContract("VaultUtils", [
          Vault.address,
          zeroAddress,
          tokenFarm.address,
          priceManager.address,
          settingsManager.address
        ])).to.be.revertedWith("vUSD address is invalid");
        await expect(deployContract("VaultUtils", [
          Vault.address,
          vusd.address,
          zeroAddress,
          priceManager.address,
          settingsManager.address
        ])).to.be.revertedWith("tokenFarm address is invalid");
        VaultUtils = await deployContract("VaultUtils", [
          Vault.address,
          vusd.address,
          tokenFarm.address,
          priceManager.address,
          settingsManager.address
       ]);
        //====================== Vault Initialize ==============
        await Vault.setVaultSettings(
          priceManager.address,
          settingsManager.address,
          triggerOrderManager.address,
          VaultUtils.address,
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
        await usdcPriceFeed.setLatestAnswer(toChainlinkPrice(1))
        await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eth.address, ethPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(gbp.address, gbpPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(eur.address, eurPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(doge.address, dogePriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(jpy.address, jpyPriceFeed.address, 8)
        await vaultPriceFeed.setTokenConfig(usdc.address, usdcPriceFeed.address, 8)
        const tokens = [
         {
           name: "btc",
           address: btc.address,
           decimals: 18,
           priceFeed: btcPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "eth",
           address: eth.address,
           decimals: 18,
           priceFeed: ethPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "doge",
           address: doge.address,
           decimals: 18,
           priceFeed: dogePriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 30 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },
         {
           name: "gbp",
           address: gbp.address,
           decimals: 18,
           priceFeed: gbpPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         },
         {
           name: "eur",
           address: eur.address,
           decimals: 18,
           priceFeed: eurPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         },    
         {
           name: "jpy",
           address: jpy.address,
           decimals: 18,
           priceFeed: jpyPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 8, // 0.008% 80 / 100000
         }, 
         {
           name: "usdc",
           address: usdc.address,
           decimals: 18,
           priceFeed: usdcPriceFeed.address,
           priceDecimals: 8,
           maxLeverage: 100 * 10000,
           marginFeeBasisPoints: 80, // 0.08% 80 / 100000
         },    
        ];
        for (const token of tokens) {
         await priceManager.setTokenConfig(
           token.address,
           token.decimals,
           token.maxLeverage,
         );
       }
        await vlp.setMinter(Vault.address, true); // vlp SetMinter
        await settingsManager.setPositionManager(positionManagerAddress, true);
        await settingsManager.setDepositFee(depositFee);
        await settingsManager.setStakingFee(stakingFee);
    });

    it ("add Vault and VaultUtils as admin", async () => {
     await vusd.addAdmin(Vault.address); // addAdmin vault
     await vusd.addAdmin(VaultUtils.address); // addAdmin vaultUtils
    })

    it ("Vault Initialize by settingsManager", async () => {
      //=======================================================
      const BTCLiquidateThreshold = 99000;
      const BTCMaxBorrowAmount = expandDecimals('10000000000', 30)
      const BTCLongFundingRateFactor = 100;
      const BTCShortFundingRateFactor = 100;
      const BTCLongMarginFeeBasisPoints = 80;
      const BTCShortMarginFeeBasisPoints = 80;
      const ETHLiquidateThreshold = 99000;
      const ETHMaxBorrowAmount = expandDecimals('10000000000', 30)
      const ETHLongFundingRateFactor = 100;
      const ETHShortFundingRateFactor = 100;
      const ETHLongMarginFeeBasisPoints = 80;
      const ETHShortMarginFeeBasisPoints = 80;
      const GBPLiquidateThreshold = 99700;
      const GBPMaxBorrowAmount = expandDecimals('10000000000', 30)
      const GBPLongFundingRateFactor = 100;
      const GBPShortFundingRateFactor = 100;
      const GBPLongMarginFeeBasisPoints = 8;
      const GBPShortMarginFeeBasisPoints = 8;
      const EURLiquidateThreshold = 99700;
      const EURMaxBorrowAmount = expandDecimals('10000000000', 30)
      const EURLongFundingRateFactor = 100;
      const EURShortFundingRateFactor = 100;
      const EURLongMarginFeeBasisPoints = 8;
      const EURShortMarginFeeBasisPoints = 8;
      const JPYLiquidateThreshold = 99700;
      const JPYMaxBorrowAmount = expandDecimals('10000000000', 30)
      const JPYLongFundingRateFactor = 100;
      const JPYShortFundingRateFactor = 100;
      const JPYLongMarginFeeBasisPoints = 8;
      const JPYShortMarginFeeBasisPoints = 8;
      const DOGELiquidateThreshold = 99000;
      const DOGEMaxBorrowAmount = expandDecimals('10000000000', 30)
      const DOGELongFundingRateFactor = 100;
      const DOGEShortFundingRateFactor = 100;
      const DOGELongMarginFeeBasisPoints = 80;
      const DOGEShortMarginFeeBasisPoints = 80;
      const LONGMaxBorrowAmount = expandDecimals('1000000000000', 30)  // $1000,000,000,000
      const SHORTMaxBorrowAmount = expandDecimals('1000000000000', 30) // $1000,000,000,000
      const USERMaxBorrowAmount = expandDecimals('10000', 30) // $10000
      await settingsManager.setLiquidateThreshold(BTCLiquidateThreshold, btc.address);
      await settingsManager.setMarginFeeBasisPoints(btc.address, true, BTCLongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(btc.address, false, BTCShortMarginFeeBasisPoints);
      await settingsManager.setLiquidateThreshold(ETHLiquidateThreshold, eth.address);
      await settingsManager.setMarginFeeBasisPoints(eth.address, true, ETHLongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(eth.address, false, ETHShortMarginFeeBasisPoints);
      await settingsManager.setLiquidateThreshold(DOGELiquidateThreshold, doge.address);
      await settingsManager.setMarginFeeBasisPoints(doge.address, true, DOGELongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(doge.address, false, DOGEShortMarginFeeBasisPoints);
      await settingsManager.setLiquidateThreshold(GBPLiquidateThreshold, gbp.address);
      await settingsManager.setMarginFeeBasisPoints(gbp.address, true, GBPLongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(gbp.address, false, GBPShortMarginFeeBasisPoints);
      await settingsManager.setLiquidateThreshold(EURLiquidateThreshold, eur.address);
      await settingsManager.setMarginFeeBasisPoints(eur.address, true, EURLongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(eur.address, false, EURShortMarginFeeBasisPoints);
      await settingsManager.setLiquidateThreshold(JPYLiquidateThreshold, jpy.address);
      await settingsManager.setMarginFeeBasisPoints(jpy.address, true, JPYLongMarginFeeBasisPoints);
      await settingsManager.setMarginFeeBasisPoints(jpy.address, false, JPYShortMarginFeeBasisPoints);
      await settingsManager.setMaxBorrowAmountPerSide(true, LONGMaxBorrowAmount);
      await settingsManager.setMaxBorrowAmountPerSide(false, SHORTMaxBorrowAmount);
      await settingsManager.setMaxBorrowAmountPerUser(USERMaxBorrowAmount);
      await settingsManager.setEnableDeposit(usdc.address, true);
      await settingsManager.setEnableStaking(usdc.address, true);
      await settingsManager.setFeeManager(feeManagerAddress);
      await settingsManager.setMaxBorrowAmountPerAsset(btc.address, BTCMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(btc.address, true, BTCLongFundingRateFactor);
      await settingsManager.setFundingRateFactor(btc.address, false, BTCShortFundingRateFactor);
      await settingsManager.setMaxBorrowAmountPerAsset(eth.address, ETHMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(eth.address, true, ETHLongFundingRateFactor);
      await settingsManager.setFundingRateFactor(eth.address, false, ETHShortFundingRateFactor);
      await settingsManager.setMaxBorrowAmountPerAsset(doge.address, DOGEMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(doge.address, true, DOGELongFundingRateFactor);
      await settingsManager.setFundingRateFactor(doge.address, false, DOGEShortFundingRateFactor);
      await settingsManager.setMaxBorrowAmountPerAsset(gbp.address, GBPMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(gbp.address, true, GBPLongFundingRateFactor);
      await settingsManager.setFundingRateFactor(gbp.address, false, GBPShortFundingRateFactor);
      await settingsManager.setMaxBorrowAmountPerAsset(eur.address, EURMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(eur.address, true, EURLongFundingRateFactor);
      await settingsManager.setFundingRateFactor(eur.address, false, EURShortFundingRateFactor);
      await settingsManager.setMaxBorrowAmountPerAsset(jpy.address, JPYMaxBorrowAmount);
      await settingsManager.setFundingRateFactor(jpy.address, true, JPYLongFundingRateFactor);
      await settingsManager.setFundingRateFactor(jpy.address, false, JPYShortFundingRateFactor);
    })

    it ("deploy ComplexRewardPerSec and add pool info to tokenFarm", async () => {
     const pId1 = 0
     const pId2 = 1
     const pId3 = 2
     const currentTimestamp = await getBlockTime(provider);
     const endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
     const endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
     const endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24 
     const rewardPerSec1 = expandDecimals(8267, 12) // 10k
     const rewardPerSec2 = expandDecimals(3858, 12) // 10k
     const rewardPerSec3 = expandDecimals(3858, 12) // 10k
     await eVela.setMinter(tokenFarm.address, true);
     await eVela.setMinter(wallet.address, true);
     await eVela.mint(wallet.address, expandDecimals(1000000, 18)); // mint eVELA     
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
    })

    it ("setFundingInterval", async () => {
      const fundingInterval = 1 * 60 * 60;
      await settingsManager.setFundingInterval(fundingInterval)
    })

    it("deposit with General Token", async () => {
      const amount = expandDecimals('1', 18)
      const collateralDeltaUsd = await priceManager.tokenToUsd(btc.address, amount);
      await btc.connect(wallet).approve(Vault.address,  amount); // approve BTC
      await expect(Vault.deposit(wallet.address, btc.address, amount))
        .to.be.revertedWith("deposit not allowed"); // deposit BTC
   })

    it("deposit with Stable Coins", async () => {
      const amount = expandDecimals('1000', 18)
      const collateralDeltaUsd = await priceManager.tokenToUsd(usdc.address, amount);
      await usdc.connect(wallet).approve(Vault.address,  amount); // approve USDC
      await Vault.deposit(wallet.address, usdc.address, amount); // deposit USDC
      expect(await vusd.balanceOf(wallet.address)).eq(collateralDeltaUsd.mul(bigNumberify(BASIS_POINTS_DIVISOR).sub(bigNumberify(depositFee))).div(bigNumberify(BASIS_POINTS_DIVISOR)))
   })

   it("depositFor with Stable Coins", async () => {
    const amount = expandDecimals('1000', 18)
    const originalVLPBalance = await vusd.balanceOf(wallet.address)
    const collateralDeltaUsd = await priceManager.tokenToUsd(usdc.address, amount);
    await usdc.connect(wallet).approve(Vault.address,  amount); // approve USDC
    await expect(Vault.connect(user1).deposit(wallet.address, usdc.address, amount))
    .to.be.revertedWith("Vault: zero amount not allowed for deposit"); // deposit USDC
    await settingsManager.connect(wallet).delegate([user1.address, user0.address])
    expect(await settingsManager.checkDelegation(wallet.address, user1.address))
      .eq(true)
    await Vault.connect(user1).deposit(wallet.address, usdc.address, amount); // deposit USDC
    expect(await vusd.balanceOf(wallet.address)).eq((collateralDeltaUsd.mul(bigNumberify(BASIS_POINTS_DIVISOR).sub(bigNumberify(depositFee))).div(bigNumberify(BASIS_POINTS_DIVISOR))).add(originalVLPBalance))
    await settingsManager.connect(wallet).undelegate([user1.address, user0.address])
  })

   it("stake with General Token", async () => {
    const amount = expandDecimals('1', 18)
    const collateralDeltaUsd = await priceManager.tokenToUsd(btc.address, amount);
    await btc.connect(wallet).approve(Vault.address,  amount); // stake BTC
    await expect(Vault.stake(wallet.address, btc.address, amount))
      .to.be.revertedWith("stake not allowed"); // stake BTC
   })


   it("stake with Stable Coins ", async () => {
      const defaultVLPPrice = await Vault.getVLPPrice()
      const amount = expandDecimals('1000', 18)
      const collateralDeltaUsd = await priceManager.tokenToUsd(usdc.address, amount);
      await usdc.connect(wallet).approve(Vault.address, amount); // approve USDC
      await Vault.stake(wallet.address, usdc.address, amount); // deposit USDC
      // const priceMultiplier =  expandDecimals('1', 18).div(PRICE_PRECISION.mul(bigNumberify(BASIS_POINTS_DIVISOR)))
      const usdAmountAfterFee = collateralDeltaUsd.mul(bigNumberify(BASIS_POINTS_DIVISOR).sub(bigNumberify(stakingFee))).div(bigNumberify(BASIS_POINTS_DIVISOR))
      const vlpMintedAmount = usdAmountAfterFee.mul(defaultVLPPrice).mul(expandDecimals('1', 18)).div(PRICE_PRECISION.mul(bigNumberify(BASIS_POINTS_DIVISOR)))
      expect(await vlp.balanceOf(wallet.address)).eq(vlpMintedAmount)
   })

   it("stakeFor with Stable Coins", async () => {
    const amount = expandDecimals('1000', 18)
    const totalUSDC = await Vault.totalUSDC()
    const totalVLP = await Vault.totalVLP()
    expect(await Vault.getVLPPrice())
      .eq(bigNumberify(BASIS_POINTS_DIVISOR).mul(expandDecimals('1', 18)).mul(totalUSDC).div(totalVLP).div(PRICE_PRECISION))
    const originalVLPBalance = await vlp.balanceOf(wallet.address)
    const collateralDeltaUsd = await priceManager.tokenToUsd(usdc.address, amount);
    await usdc.connect(wallet).approve(Vault.address,  amount); // approve USDC
    await expect(Vault.connect(user1).stake(wallet.address, usdc.address, amount))
      .to.be.revertedWith("Vault: zero amount not allowed for stake"); // stake USDC
    await settingsManager.connect(wallet).delegate([user1.address, user0.address])
    expect(await settingsManager.checkDelegation(wallet.address, user1.address))
      .eq(true)
    await Vault.connect(user1).stake(wallet.address, usdc.address, amount); // stake USDC
    const usdAmountAfterFee = collateralDeltaUsd.mul(bigNumberify(BASIS_POINTS_DIVISOR).sub(bigNumberify(stakingFee))).div(bigNumberify(BASIS_POINTS_DIVISOR))
    const newVLPMintedAmount = usdAmountAfterFee.mul(totalVLP).div(totalUSDC)
    expect(await vlp.balanceOf(wallet.address)).eq(newVLPMintedAmount.add(originalVLPBalance))
   })

   it("withdraw with General Token", async () => {
      const amount = expandDecimals('10', 30)
      await expect(Vault.withdraw(btc.address, wallet.address, amount))
        .to.be.revertedWith("withdraw not allowed"); // deposit BTC
   })

  it("withdraw with Stable Coins", async () => {
    const vusdAmount = expandDecimals('100', 30)
    const orignalUSDCBalance = await usdc.balanceOf(wallet.address)
    const collateralToken = await priceManager.usdToToken(usdc.address, vusdAmount);
    await Vault.withdraw(usdc.address, wallet.address, vusdAmount)
    expect(await usdc.balanceOf(wallet.address)).eq(
      (collateralToken.mul(bigNumberify(BASIS_POINTS_DIVISOR).sub(bigNumberify(depositFee))).div(bigNumberify(BASIS_POINTS_DIVISOR))).add(orignalUSDCBalance))
  })

  it("unstake with General Token", async () => {
    const amount = expandDecimals('10', 18)
    await expect(Vault.unstake(btc.address, amount, wallet.address))
      .to.be.revertedWith("unstake not allowed"); // deposit BTC
  })

  it("unstake with Stable Coins", async () => {
    const vlpAmount = expandDecimals('10', 18)
    const orignalUSDCBalance = await usdc.balanceOf(wallet.address)
    // const collateralToken = await priceManager.usdToToken(usdc.address, vusdAmount);
    await expect(Vault.unstake(usdc.address, expandDecimals('10000', 18), wallet.address))
      .to.be.revertedWith("Vault: zero amount not allowed and cant exceed totalVLP")
    await expect(Vault.unstake(usdc.address, vlpAmount, wallet.address))
      .to.be.revertedWith("cooldown duration not yet passed")
    const totalUSDC = await Vault.totalUSDC()
    const totalVLP = await Vault.totalVLP()
    const usdAmount = vlpAmount.mul(totalUSDC).div(totalVLP)
    const usdAmountFee = usdAmount.mul(bigNumberify(stakingFee)).div(bigNumberify(BASIS_POINTS_DIVISOR));
    const usdAmountAfterFee = usdAmount.sub(usdAmountFee)
    const amountOut = await priceManager.usdToToken(
      usdc.address,
      usdAmountAfterFee
    );
    const passTime = 60 * 60 * 6
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    await Vault.unstake(usdc.address, vlpAmount, wallet.address)
    expect(await usdc.balanceOf(wallet.address)).eq(
      (amountOut).add(orignalUSDCBalance))
  })

  it ("Long IncreasePosition for Market Order", async () => {
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const orderType = 0 // M
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('59000'))
    await expect(Vault.connect(wallet).newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )).to.be.revertedWith("slippage exceeded")
     await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
     await Vault.connect(wallet).newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
     const passTime = 60 * 60 * 1
     await ethers.provider.send('evm_increaseTime', [passTime]);
     await ethers.provider.send('evm_mine');
   })

   it ("updateTriggerOrders", async () => {
      const indexToken = btc.address;
      const isLong = true
      const posId = 0
      const tpPrices = [
        expandDecimals('57500', 30),
        expandDecimals('58200', 30),
        expandDecimals('59000', 30)
      ]
      const tpAmountPercents = [
        50000,
        30000,
        20000
      ]
      const tpTriggeredAmounts = [
        0,
        0,
        0
      ]
      const slPrices = [
        expandDecimals('54000', 30)
      ]
      const slAmountPercents = [
        100000
      ]
      const slTriggeredAmounts = [
        0
      ]
      await triggerOrderManager.updateTriggerOrders(
        indexToken, 
        isLong, 
        posId, 
        tpPrices, 
        slPrices, 
        tpAmountPercents, 
        slAmountPercents,
        tpTriggeredAmounts,
        slTriggeredAmounts
      )
   })

   it ("addPosition", async () => {
     const account = wallet.address
     const indexToken = btc.address
     const isLong = true
     const posId = 0
     const amountIn = expandDecimals('10', 30)
     const toUsdAmount = expandDecimals('100', 30)
     await expect(Vault.confirmDelayTransaction(
      account,
      indexToken,
      isLong,
      posId)).to.be.revertedWith("order is still in delay pending")
     await Vault.addPosition(indexToken, isLong, posId, amountIn, toUsdAmount)
   })  

   it ("confirmDelayTransaction", async () => {
    const account = wallet.address
    const indexToken = btc.address
    const isLong = true
    const posId = 0
    const raise = false
    const positionInfo = await Vault.getPosition(wallet.address, indexToken, isLong, posId)
    const position = positionInfo[0]
    const order = positionInfo[1]
    const confirm = positionInfo[2]
    const confirmDelayStatus = confirm.confirmDelayStatus
    if (confirmDelayStatus) {
      await expect(Vault.connect(user0).confirmDelayTransaction(account, indexToken, isLong, posId))
        .to.be.revertedWith("not allowed")
      await expect(Vault.confirmDelayTransaction(
        account,
        indexToken,
        isLong,
        posId)).to.be.revertedWith("order is still in delay pending")
      const passTime = 60 * 2
      await ethers.provider.send('evm_increaseTime', [passTime]);
      await ethers.provider.send('evm_mine');
      const validateConfirmDelay = await VaultUtils.validateConfirmDelay(
        account,
        indexToken,
        isLong,
        posId,
        raise
      )
      if (validateConfirmDelay) {
        await Vault.confirmDelayTransaction(
          account,
          indexToken,
          isLong,
          posId)
      }
    }
  })

  it ("increasePosition for triggerPosition", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const orderType = 0 // M
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.connect(wallet).newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
     const lastPosId = await Vault.lastPosId()
     const posId = lastPosId.toNumber() - 1
    await expect(Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId)).to.be.revertedWith("trigger not ready")
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');      
   })

   it ("updateTriggerOrders for triggerPosition", async () => {
      const indexToken = btc.address;
      const isLong = true
      const lastPosId = await Vault.lastPosId()
      const posId = lastPosId.toNumber() - 1
      const tpPrices = [
        expandDecimals('57500', 30),
        expandDecimals('58200', 30),
        expandDecimals('59000', 30)
      ]
      const tpAmountPercents = [
        50000,
        30000,
        20000
      ]
      const tpTriggeredAmounts = [
        0,
        0,
        0
      ]
      const slPrices = [
        expandDecimals('54000', 30)
      ]
      const slAmountPercents = [
        100000
      ]
      const slTriggeredAmounts = [
        0
      ]
      await triggerOrderManager.updateTriggerOrders(
        indexToken, 
        isLong, 
        posId, 
        tpPrices, 
        slPrices, 
        tpAmountPercents, 
        slAmountPercents,
        tpTriggeredAmounts,
        slTriggeredAmounts
      )
   })

  it ("triggerPosition", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58000'))
    await Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId)
  })

  it ("addTrailingStop for Long with trailing type = percent", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const stepType = 1
    const stpPrice1 = expandDecimals('56500', 30)
    const stepAmount = 1000 // 1 %
    const triggerData0 = [
      expandDecimals('15', 30),
      expandDecimals('150', 30),
      stepType,
      stpPrice1,
      stepAmount
    ]
    const triggerData1 = [
      pendingCollateral,
      pendingSize,
      stepType,
      expandDecimals('57500', 30),
      stepAmount
    ]
    const triggerData2 = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      150000
    ]
    const triggerData = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      stepAmount
    ]
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData0))
      .to.be.revertedWith("trailing size should be smaller than position size")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData1))
      .to.be.revertedWith("invalid trailing data")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData2))
      .to.be.revertedWith("percent cant exceed 100%")
    await Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData)
    await expect(Vault.connect(user0).updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("updateTStop not allowed")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56950'))
    await expect(Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("price incorrect")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57600'))
    await Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )
    const validateTriggerBeforePriceChange = await VaultUtils.validateTrigger(
      account, 
      indexToken, 
      isLong,
      posId
    )
    if (validateTriggerBeforePriceChange) {
      await Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
    } else {
      await expect(Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
      ).to.be.revertedWith("trigger not ready")
    }
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56400'))
    await Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId
    )
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("addTrailingStop for Long with trailing type = amount", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const stepType = 0
    const stpPrice1 = expandDecimals('56700', 30)
    const stepAmount = expandDecimals('400', 30)
    const triggerData0 = [
      expandDecimals('15', 30),
      expandDecimals('150', 30),
      stepType,
      stpPrice1,
      stepAmount
    ]
    const triggerData1 = [
      pendingCollateral,
      pendingSize,
      stepType,
      expandDecimals('57500', 30),
      stepAmount
    ]
    const triggerData2 = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      expandDecimals('57200', 30)
    ]
    const triggerData = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      stepAmount
    ]
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData0))
      .to.be.revertedWith("trailing size should be smaller than position size")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData1))
      .to.be.revertedWith("invalid trailing data")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData2))
      .to.be.revertedWith("step amount cant exceed price")
    await Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData)
    await expect(Vault.connect(user0).updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("updateTStop not allowed")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56950'))
    await expect(Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("price incorrect")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57200'))
    await Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )
    const validateTriggerBeforePriceChange = await VaultUtils.validateTrigger(
      account, 
      indexToken, 
      isLong,
      posId
    )
    if (validateTriggerBeforePriceChange) {
      await Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
    } else {
      await expect(Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
      ).to.be.revertedWith("trigger not ready")
    }
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56500'))
    await Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId)
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("addTrailingStop for Short with trailing type = percent", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
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
     await btcPriceFeed.setLatestAnswer(toChainlinkPrice('55000'))
     await expect(Vault.newPositionOrder(
      indexToken, //_indexToken
      isLong,
      orderType,
      triggerPrices, //triggerPrices
      referAddress
     )).to.be.revertedWith("slippage exceeded")
     await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
     await Vault.newPositionOrder(
      indexToken, //_indexToken
      isLong,
      orderType,
      triggerPrices, //triggerPrices
      referAddress
    )
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const stepType = 1
    const stpPrice1 = expandDecimals('57500', 30)
    const stepAmount = 1000 // 1%
    const triggerData = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      stepAmount
    ]
    const triggerData0 = [
      expandDecimals('15', 30),
      expandDecimals('150', 30),
      stepType,
      stpPrice1,
      stepAmount
    ]
    const triggerData1 = [
      pendingCollateral,
      pendingSize,
      stepType,
      expandDecimals('56500', 30),
      stepAmount
    ]
    const triggerData2 = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      150000
    ]
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData0))
      .to.be.revertedWith("trailing size should be smaller than position size")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData1))
      .to.be.revertedWith("invalid trailing data")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData2))
      .to.be.revertedWith("percent cant exceed 100%")
    await Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData)
    await expect(Vault.connect(user0).updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("updateTStop not allowed")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57050'))
    await expect(Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("price incorrect")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('55200'))
    await Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )
    const validateTriggerBeforePriceChange = await VaultUtils.validateTrigger(
      account, 
      indexToken, 
      isLong,
      posId
    )
    if (validateTriggerBeforePriceChange) {
      await Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
    } else {
      await expect(Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
      ).to.be.revertedWith("trigger not ready")
    }
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58500'))
    await Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId)
  })

  it ("addTrailingStop for Short with trailing type = Amount", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = false
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const stepType = 0
    const stpPrice1 = expandDecimals('57100', 30)
    const stepAmount = expandDecimals('400', 30)
    const triggerData0 = [
      expandDecimals('15', 30),
      expandDecimals('150', 30),
      stepType,
      stpPrice1,
      stepAmount
    ]
    const triggerData1 = [
      pendingCollateral,
      pendingSize,
      stepType,
      expandDecimals('56500', 30),
      stepAmount
    ]
    const triggerData = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      stepAmount
    ]
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData0))
      .to.be.revertedWith("trailing size should be smaller than position size")
    await expect(Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData1))
      .to.be.revertedWith("invalid trailing data")
    await Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData)
    await expect(Vault.connect(user0).updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("updateTStop not allowed")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57050'))
    await expect(Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )).to.be.revertedWith("price incorrect")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('56500'))
    await Vault.updateTrailingStop(
      account,
      indexToken,
      isLong,
      posId
    )
    const validateTriggerBeforePriceChange = await VaultUtils.validateTrigger(
      account, 
      indexToken, 
      isLong,
      posId
    )
    if (validateTriggerBeforePriceChange) {
      await Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
    } else {
      await expect(Vault.triggerPosition(
        account, 
        indexToken, 
        isLong, 
        posId)
      ).to.be.revertedWith("trigger not ready")
    }
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('58000'))
    await Vault.triggerPosition(
      account, 
      indexToken, 
      isLong, 
      posId)
  })

  it ("increasePosition for Limit -> Long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    const orderType = 1 // M
    const lmtPrice = expandDecimals('57500', 30)
    const stpPrice = 0
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices0 = [
      0,
      stpPrice,
      pendingCollateral,
      pendingSize
     ]
     const validatePosData = await VaultUtils.validatePosData(
      isLong,
      indexToken,
      orderType,
      triggerPrices0,
      false
     ) 
    if (validatePosData) {
      await Vault.newPositionOrder(
        indexToken, //_indexToken
        isLong,
        orderType,
        triggerPrices0, //triggerPrices
        referAddress
      )
    } else {
      await expect(Vault.newPositionOrder(
        indexToken, //_indexToken
        isLong,
        orderType,
        triggerPrices0, //triggerPrices
        referAddress
      )).to.be.revertedWith("invalid position data")
    }
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("increasePosition for Limit -> Short", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = false
    const referAddress = ethers.constants.AddressZero;
    const orderType = 1 // M
    const lmtPrice = expandDecimals('56500', 30)
    const stpPrice = 0
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices0 = [
      0,
      stpPrice,
      pendingCollateral,
      pendingSize
     ]
     const validatePosData = await VaultUtils.validatePosData(
      isLong,
      indexToken,
      orderType,
      triggerPrices0,
      false
     ) 
    if (validatePosData) {
      await Vault.newPositionOrder(
        indexToken, //_indexToken
        isLong,
        orderType,
        triggerPrices0, //triggerPrices
        referAddress
      )
    } else {
      await expect(Vault.newPositionOrder(
        indexToken, //_indexToken
        isLong,
        orderType,
        triggerPrices0, //triggerPrices
        referAddress
      )).to.be.revertedWith("invalid position data")
    }
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("increasePosition for Stop Market -> Long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    const orderType = 2 // Stop Market
    const lmtPrice = 0
    const stpPrice = expandDecimals('56500', 30)
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("increasePosition for Stop Market -> Short", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = false
    const referAddress = ethers.constants.AddressZero;
    const orderType = 2 // Stop Market
    const lmtPrice = 0
    const stpPrice = expandDecimals('57500', 30)
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("increasePosition for Stop Limit -> Long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    const orderType = 3 // Stop Market
    const lmtPrice = expandDecimals('57200', 30)
    const stpPrice = expandDecimals('56500', 30)
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices0 = [
      0,
      0,
      pendingCollateral,
      pendingSize
     ]
    await expect(Vault.newPositionOrder(
      indexToken, //_indexToken
      isLong,
      orderType,
      triggerPrices0, //triggerPrices
      referAddress
    )).to.be.revertedWith("invalid position data")
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })

  it ("increasePosition for Stop Limit -> Short", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000))   
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = false
    const referAddress = ethers.constants.AddressZero;
    const orderType = 3 // Stop Limit
    const lmtPrice = expandDecimals('56500', 30)
    const stpPrice = expandDecimals('57500', 30)
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices0 = [
      0,
      0,
      pendingCollateral,
      pendingSize
     ]
    await expect(Vault.newPositionOrder(
      indexToken, //_indexToken
      isLong,
      orderType,
      triggerPrices0, //triggerPrices
      referAddress
    )).to.be.revertedWith("invalid position data")
    const triggerPrices = [
      lmtPrice,
      stpPrice,
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const account = wallet.address
    await Vault.connect(user1).triggerPosition(account, indexToken, isLong, posId) 
    const passTime = 60 * 60 * 1
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
  })  
  
  it ("cancelPendingOrder", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const indexToken = btc.address;
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    await expect(Vault.cancelPendingOrder(indexToken, true, 0)).to.be.revertedWith("Not in Pending") 
    await Vault.cancelPendingOrder(indexToken, false, posId) 
  })

  it ("cancel for Trailing Stop", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const stepType = 1
    const stpPrice1 = expandDecimals('56500', 30)
    const stepAmount = 1000 // 1 %
    const triggerData = [
      pendingCollateral,
      pendingSize,
      stepType,
      stpPrice1,
      stepAmount
    ]
    await Vault.addTrailingStop(
      indexToken, 
      isLong, 
      posId, 
      triggerData)
    await Vault.cancelPendingOrder(indexToken, isLong, posId) 
  })

  it ("addCollateral", async () => {
    const indexToken = btc.address
    const isLong = true
    const posId = 0
    const isPlus = true
    const amount = expandDecimals('5', 30)
    await expect(Vault.addOrRemoveCollateral(indexToken, isLong, posId, isPlus, expandDecimals('1500', 30)))
      .to.be.revertedWith("position size should be greater than collateral")
    await Vault.addOrRemoveCollateral(indexToken, isLong, posId, isPlus, amount)
  })

  it ("remove collateral", async () => {
    const indexToken = btc.address
    const isLong = true
    const posId = 0
    const isPlus = false
    const amount = expandDecimals('5', 30)
    const positionInfo = await Vault.getPosition(wallet.address, indexToken, isLong, posId)
    const position = positionInfo[0]
    await expect(Vault.addOrRemoveCollateral(indexToken, isLong, posId, isPlus, position.collateral))
      .to.be.revertedWith("Vault: maxLeverage exceeded")
    await Vault.addOrRemoveCollateral(indexToken, isLong, posId, isPlus, amount)
  })

  it ("decreasePosition with full amount for Long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const sizeDelta = expandDecimals('100', 30)
    // await expect(Vault.decreasePosition(
    //   indexToken,
    //   0,
    //   isLong,
    //   posId
    // )).to.be.revertedWith("position size should be greather than zero")
    await expect(Vault.decreasePosition(
      indexToken,
      expandDecimals('1000', 30),
      isLong,
      posId
    )).to.be.revertedWith("borrowed amount exceed the bottom")
    await expect(Vault.decreasePosition(
      indexToken,
      sizeDelta,
      isLong,
      posId
    )).to.be.revertedWith("not allowed to close the position")
    await settingsManager.setCloseDeltaTime(0)
    await Vault.decreasePosition(
      indexToken,
      sizeDelta,
      isLong,
      posId
    )
  })

  it ("decreasePosition with partial amount for Long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const indexToken = btc.address;
    const isLong = true
    const posId = 0
    await Vault.decreasePosition(
      indexToken,
      expandDecimals('2', 30),
      isLong,
      posId
    )
  })

  it ("liquidatePosition for Long", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 0
    await expect(Vault.liquidatePosition(account, indexToken, isLong, posId))
      .to.be.revertedWith("not exceed or allowed")
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(43800))
    await expect(VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      true
    )).to.be.revertedWith("Vault: losses exceed collateral")
    const validateLiquidation = await VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      false
    )
    if (validateLiquidation[0].toNumber() > 0) {
      await Vault.liquidatePosition(account, indexToken, isLong, posId)
    }
  })


  it ("liquidatePosition for Long for checking  maxThreshold exceeded", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 1
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(51800)) 
    const validateLiquidation = await VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      false
    )
    await expect(VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      true
    )).to.be.revertedWith("Vault: maxThreshold exceeded")
    if (validateLiquidation[0].toNumber() == 2) { // Liquidate Max Threshold
      await Vault.liquidatePosition(account, indexToken, isLong, posId)
    } 
  })

  it ("create Market Order for testing liquidatePosition", async () => {
    const passTime = 60 * 60 * 18
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    await settingsManager.setReferEnabled(true);
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const orderType = 0 // M
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.connect(wallet).newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
   })
   
  it ("liquidatePosition for Long for checking fees exceed collateral", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 6
    const passTime = 60 * 60 * 12
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(52300)) 
    const validateLiquidation = await VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      false
    )
    await expect(VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      true
    )).to.be.revertedWith("Vault: fees exceed collateral")
    if (validateLiquidation[0].toNumber() == 2) { // Liquidate Max Threshold
      await Vault.liquidatePosition(account, indexToken, isLong, posId)
    } 
  })

  it ("create Market Order for testing liquidatePosition", async () => {
    const passTime = 60 * 60 * 18
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = ethers.constants.AddressZero;
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice('57000'))
    const expectedMarketPrice = await vaultPriceFeed.getLastPrice(indexToken);
    const slippage = 1000 // 1%
    const orderType = 0 // M
    const pendingCollateral = amountIn;
    const pendingSize = toUsdAmount;
    const triggerPrices = [
      expectedMarketPrice,
      slippage,
      pendingCollateral,
      pendingSize
     ]
     await Vault.connect(wallet).newPositionOrder(
      indexToken, //_indexToken
       isLong,
       orderType,
       triggerPrices, //triggerPrices
       referAddress
     )
   })  

   it ("liquidatePosition for Long liquidation fees exceed collateral ", async () => {
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 8
    const passTime = 60 * 60 * 12
    await ethers.provider.send('evm_increaseTime', [passTime]);
    await ethers.provider.send('evm_mine');
    const liquidateFeeUsd = expandDecimals('10', 30)
    await expect(settingsManager.setLiquidationFeeUsd(expandDecimals('160', 30))).to.be.revertedWith("liquidationFeeUsd should be smaller than MAX")
    await settingsManager.setLiquidationFeeUsd(liquidateFeeUsd)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(55220))
    const validateLiquidation = await VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      false
    )
    await expect(VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      true
    )).to.be.revertedWith("Vault: liquidation fees exceed collateral")
    if (validateLiquidation[0].toNumber() == 2) { // Liquidate Max Threshold
      await Vault.liquidatePosition(account, indexToken, isLong, posId)
    } 
  })   

  it ("validateLiquidation for non open position", async ()=>{
    const account = wallet.address
    const indexToken = btc.address;
    const isLong = true
    const posId = 10
    const validateLiquidation = await VaultUtils.validateLiquidation(
      account,
      indexToken,
      isLong,
      posId,
      true
    )
    expect(validateLiquidation[0]).eq(0)
  })

  it ("decreasePosition with full amount for Long", async () => {
    await settingsManager.setLiquidationFeeUsd(0)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = user0.address;
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
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const sizeDelta = expandDecimals('100', 30)
    await Vault.decreasePosition(
      indexToken,
      sizeDelta,
      isLong,
      posId
    )
  })


  it ("long market order for checking decreasePosition at quick price movement", async () => {
    const closeDeltaTime = 60 * 60 * 1
    await settingsManager.setCloseDeltaTime(closeDeltaTime)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = true
    const referAddress = user0.address;
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
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57500)) 
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const sizeDelta = expandDecimals('100', 30)
    await Vault.decreasePosition(
      indexToken,
      sizeDelta,
      isLong,
      posId
    )
  })

  it ("short market order for checking decreasePosition at quick price movement", async () => {
    const closeDeltaTime = 60 * 60 * 1
    await settingsManager.setCloseDeltaTime(closeDeltaTime)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(57000)) 
    const account = wallet.address
    const indexToken = btc.address;
    const amountIn = expandDecimals('10', 30)
    const toUsdAmount = expandDecimals('100', 30)
    const isLong = false
    const referAddress = user0.address;
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
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(56500)) 
    const lastPosId = await Vault.lastPosId()
    const posId = lastPosId.toNumber() - 1
    const sizeDelta = expandDecimals('100', 30)
    await Vault.decreasePosition(
      indexToken,
      sizeDelta,
      isLong,
      posId
    )
  })  
});