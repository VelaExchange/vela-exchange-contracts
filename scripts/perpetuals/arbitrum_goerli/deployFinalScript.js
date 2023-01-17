const {
    deployContract,
    contractAt,
    sendTxn,
  } = require("../../shared/helpers");
  const {
    expandDecimals,
    getBlockTime
  } = require("../../shared/utilities");
  const { ethers } = require("ethers");
  
  function toUsd(value) {
    const normalizedValue = parseInt(value * Math.pow(10, 10));
    return ethers.BigNumber.from(normalizedValue).mul(
      ethers.BigNumber.from(10).pow(20)
    );
  }
  
  async function main() {
    //================== Deploy Process =========================
    //============ Input Data =================
    const name = "Vested USDC";
    const symbol = "VUSDC";
    const initialSupply = 0;
    const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
    
    // 1. deploy VUSD
    // const vUSDC = await deployContract('vUSDC', [name, symbol, initialSupply])
    const vUSDC = await contractAt('vUSDC', '0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79')
    
    // 2. deploy VLP
    // const vlp = await deployContract("VLP", [])
    const vlp = await contractAt('VLP', '0x020F88c59222241378B23325fdCFEc4ea3fF5199')

    // 3. deploy VELA
    const trustedFarwarder = "0xdc39780a90EDFc0bB3Bb2437486356e5625944B1"
    // const vela = await deployContract('Vela', [trustedFarwarder])
    const vela = await contractAt('Vela', '0x22B1E7E25ce22251DAf656B7c85b0fcc16d8aF8D')
    
    // 4. deploy EVELA
    // const eVela = await deployContract("eVELA", []);
    const eVela = await contractAt('eVELA', '0x1fd018999420dAb0f98032e8831C0A735f55EDd0')

    // 5. deploy TokenFarm
    const vestingDuration = 6 * 30 * 24 * 60 * 60;
    const unbondingPeriod = 14 * 24 * 60 * 60;
    const cooldownDuration = 86400
    const liquidationFeeUsd = 0 // _liquidationFeeUsd
    const fundingInterval = 1 * 60 * 60 // fundingInterval = 8 hours
    const fundingRateFactor = 100 //  fundingRateFactor
    const feeRewardBasisPoints = 70000 // FeeRewardBasisPoints 70%
    const depositFee = 3000
    const stakingFee = 3000
    const tokenFarm = await deployContract("TokenFarm", [
      vestingDuration,
      eVela.address,
      vela.address,
    ]);
    // const tokenFarm = await contractAt("TokenFarm", "0x5b31A7543843746CFC00fa9305c878ecDC244B02")
    // 6. deploy VaultPriceFeed
    // const vaultPriceFeed = await deployContract("VaultPriceFeed", []);
    const vaultPriceFeed = await contractAt("VaultPriceFeed", '0xb665E8E6F2031b143458866a940ec0E8BF58c34A');
    const tokens = [
        {
          name: "btc",
          address: "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 30 * 10000
        },
        {
          name: "eth",
          address: "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0xa142374C993c434C424A63390118451e5b396b57",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 30 * 10000
        },
        {
          name: "gbp",
          address: "0x02311940c23D524Be839b958464B18084E127523",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0x1675E6462580F6cCBfaB781958554D5990A9bbfe",
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "eur",
          address: "0x3a25e25A0059cd08C974a8672250E22012Fb1260",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c",
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "jpy",
          address: "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04",
          decimals: 18,
          priceDecimals: 8,
          address: "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04",
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "doge",
          address: "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14",
          marginFeeBasisPoints: 80, // 0.08% 8 / 100000
          maxLeverage: 30 * 10000
        },
        {
          name: "usdc",
          address: "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b",
          decimals: 6,
          priceDecimals: 8,
          priceFeed: "0x1692Bdd32F31b831caAc1b0c9fAF68613682813b",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "usdt",
          address: "0x1d51eEcc9b82b63cb5630adB44a195200e25c123",
          decimals: 6,
          priceDecimals: 8,
          priceFeed: "0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "vlp",
          address: "0x020F88c59222241378B23325fdCFEc4ea3fF5199",
          priceFeed: "0x8045E2C156A35a110DAc2D220a63fe749cD5CFDd",
          decimals: 18,
          priceDecimals: 8,
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 100 * 10000
        }
    ];

    // for (const token of tokens) {
    //     await sendTxn(
    //         vaultPriceFeed.setTokenConfig(
    //           token.address,
    //           token.priceFeed,
    //           token.priceDecimals,
    //         ),
    //         `vaultPriceFeed.setTokenConfig(${token.name}) ${token.address}`
    //     );
    // }

    // 7. Deploy  Vault
    const vault = await deployContract("Vault", [
      vlp.address,
      vUSDC.address,
      tokenFarm.address,
      vaultPriceFeed.address
    ]);
    // const vault = await contractAt("Vault", "0x2C24ffBeD47A94aBAdC00942f60F67ED435B21a5")

    // 8. Deploy VaultUtils
    const vaultUtils = await deployContract("VaultUtils", [
      vault.address,
      vUSDC.address,
      tokenFarm.address
    ]);
    // const vaultUtils = await contractAt("VaultUtils", "0x943A7cF486Df55b3C9f3960a42cdBCDD3F9Ea268")
    for (const token of tokens) {
      await sendTxn(
        vault.setTokenConfig(
          token.address,
          token.decimals,
          token.maxLeverage,
        ),
        `vault.setTokenConfig(${token.name}) ${token.address}, ${token.decimals}`
      );
    }
    await sendTxn(vault.setVaultSettings(
      cooldownDuration,    // setCooldownDuration
      feeRewardBasisPoints, // FeeRewardBasisPoints 70%
      vaultUtils.address // set vaultUtils address"
    ), "setVaultSettings")
  
    await sendTxn(vlp.setMinter(vault.address, true), "vlp SetMinter");
    await sendTxn(vault.setManager(account, true), "setPositionManager");
    const btc = await contractAt(
        "BaseToken",
        "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec"
    );
    const eth = await contractAt(
        "BaseToken",
        "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17"
    );
    const usdc = await contractAt(
        "BaseToken",
        "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b"
    );
    const usdt = await contractAt(
        "BaseToken",
        "0x1d51eEcc9b82b63cb5630adB44a195200e25c123"
    );
    const gbp = await contractAt(
        "BaseToken",
        "0x02311940c23D524Be839b958464B18084E127523"
    );
    const eur = await contractAt(
        "BaseToken",
        "0x3a25e25A0059cd08C974a8672250E22012Fb1260"
    );
    const jpy = await contractAt(
        "BaseToken",
        "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04"
    );
    const doge = await contractAt(
    "BaseToken",
    "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD"
    )
    const vlp_contract = await contractAt(
      "BaseToken",
      "0x020F88c59222241378B23325fdCFEc4ea3fF5199"
    )
    const ethLastPrice = await vault.getLastPrice(eth.address);
    console.log(
      "ETH maxPrice: ",
      ethers.utils.formatUnits(ethLastPrice, 30)
    );
    const btcLastPrice = await vault.getLastPrice(btc.address);
    console.log(
      "BTC lastPrice: ",
      ethers.utils.formatUnits(btcLastPrice, 30)
    );
    const usdtLastPrice = await vault.getLastPrice(usdt.address);
    console.log(
      "USDT lastPrice: ",
      ethers.utils.formatUnits(usdtLastPrice, 30)
    );
    const usdcLastPrice = await vault.getLastPrice(usdc.address);
    console.log(
      "USDC lastPrice: ",
      ethers.utils.formatUnits(usdcLastPrice, 30)
    );
    const gbpLastPrice = await vault.getLastPrice(gbp.address);
    console.log(
      "GBP lastPrice: ",
      ethers.utils.formatUnits(gbpLastPrice, 30)
    );
    const eurLastPrice = await vault.getLastPrice(eur.address);
    console.log(
      "EUR lastPrice: ",
      ethers.utils.formatUnits(eurLastPrice, 30)
    );
    const jpyLastPrice = await vault.getLastPrice(jpy.address);
    console.log(
      "JPY lastPrice: ",
      ethers.utils.formatUnits(jpyLastPrice, 30)
    );
    const dogeLastPrice = await vault.getLastPrice(doge.address);
    console.log(
      "DOGE lastPrice: ",
      ethers.utils.formatUnits(dogeLastPrice, 30)
    );

    const vlpLastPrice = await vault.getLastPrice(vlp_contract.address);
    console.log(
      "VLP lastPrice: ",
      ethers.utils.formatUnits(vlpLastPrice, 30)
    );
    // await sendTxn(
    //   vUSDC.mint(vault.address, expandDecimals("1000000", 30)),
    //   "usdc mint"
    // );
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
    const LONGMaxBorrowAmount = expandDecimals('1000000000000', 30)
    const SHORTMaxBorrowAmount = expandDecimals('1000000000000', 30)
    const USERMaxBorrowAmount = expandDecimals('10000000000', 30)
    await sendTxn(
      vaultUtils.setLiquidateThreshold(BTCLiquidateThreshold, btc.address),
      "setLiquidateThreshold for BTC"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(btc.address, BTCMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for BTC"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(btc.address, true, BTCLongFundingRateFactor),
    //   "setFundingRateFactor Long for BTC"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(btc.address, false, BTCShortFundingRateFactor),
    //   "setFundingRateFactor Short for BTC"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(btc.address, true, BTCLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for BTC Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(btc.address, false, BTCShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for BTC Short"
    );
    await sendTxn(
      vaultUtils.setLiquidateThreshold(ETHLiquidateThreshold, eth.address),
      "setLiquidateThreshold for ETH"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(eth.address, ETHMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for ETH"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(eth.address, true, ETHLongFundingRateFactor),
    //   "setFundingRateFactor Long for ETH"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(eth.address, false, ETHShortFundingRateFactor),
    //   "setFundingRateFactor Short for ETH"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(eth.address, true, ETHLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for ETH Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(eth.address, false, ETHShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for ETH Short"
    );
    await sendTxn(
      vaultUtils.setLiquidateThreshold(DOGELiquidateThreshold, doge.address),
      "setLiquidateThreshold for DOGE"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(doge.address, DOGEMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for DOGE"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(doge.address, true, DOGELongFundingRateFactor),
    //   "setFundingRateFactor Long for DOGE"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(doge.address, false, DOGEShortFundingRateFactor),
    //   "setFundingRateFactor Short for DOGE"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(doge.address, true, DOGELongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for DOGE Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(doge.address, false, DOGEShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for DOGE Short"
    );
    await sendTxn(
      vaultUtils.setLiquidateThreshold(GBPLiquidateThreshold, gbp.address),
      "setLiquidateThreshold for GBP"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(gbp.address, GBPMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for GBP"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(gbp.address, true, GBPLongFundingRateFactor),
    //   "setFundingRateFactor Long for GBP"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(gbp.address, false, GBPShortFundingRateFactor),
    //   "setFundingRateFactor Short for GBP"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(gbp.address, true, GBPLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for GBP Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(gbp.address, false, GBPShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for GBP Short"
    );
    await sendTxn(
      vaultUtils.setLiquidateThreshold(EURLiquidateThreshold, eur.address),
      "setLiquidateThreshold for EUR"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(eur.address, EURMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for EUR"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(eur.address, true, EURLongFundingRateFactor),
    //   "setFundingRateFactor Long for EUR"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(eur.address, false, EURShortFundingRateFactor),
    //   "setFundingRateFactor Short for EUR"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(eur.address, true, EURLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for EUR Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(eur.address, false, EURShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for EUR Short"
    );
    await sendTxn(
      vaultUtils.setLiquidateThreshold(JPYLiquidateThreshold, jpy.address),
      "setLiquidateThreshold for BTC"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerAsset(jpy.address, JPYMaxBorrowAmount),
    //   "setLiquidateThreshold for BTC"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(jpy.address, true, JPYLongFundingRateFactor),
    //   "setFundingRateFactor Long for JPY"
    // );
    // await sendTxn(
    //   vaultUtils.setFundingRateFactor(jpy.address, false, JPYShortFundingRateFactor),
    //   "setFundingRateFactor Short for JPY"
    // );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(jpy.address, true, JPYLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for JPY Long"
    );
    await sendTxn(
      vaultUtils.setMarginFeeBasisPoints(jpy.address, false, JPYShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for JPY Short"
    );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerSide(true, LONGMaxBorrowAmount),
    //   "setMaxBorrowAmountPerSide for Long"
    // );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerSide(false, SHORTMaxBorrowAmount),
    //   "setMaxBorrowAmountPerSide for Short"
    // );
    // await sendTxn(
    //   vaultUtils.setMaxBorrowAmountPerUser(USERMaxBorrowAmount),
    //   "setMaxBorrowAmountPerUser"
    // );
    // await sendTxn(
    //   vaultUtils.setEnableDeposit(usdt.address, true),
    //   "setEnableDeposit for USDT"
    // );
    // await sendTxn(
    //   vaultUtils.setEnableStaking(usdt.address, true),
    //   "setEnableStaking for USDT"
    // );
    await sendTxn(
      vaultUtils.setEnableDeposit(usdc.address, true),
      "setEnableDeposit for USDC"
    );
    await sendTxn(
      vaultUtils.setEnableStaking(usdc.address, true),
      "setEnableStaking for USDC"
    );
    await sendTxn(vUSDC.addAdmin(vault.address), 'vusd addAdmin')
    await sendTxn(vUSDC.addAdmin(vaultUtils.address), 'vusd addAdmin')
    const usdcBalance = await usdc.balanceOf(account)
    console.log("usdcBalance : ", ethers.utils.formatUnits(usdcBalance, 6))
    // await sendTxn(
    //   usdt.approve(vault.address, expandDecimals("1000000", 6)),
    //   "approve USDT"
    // );
    await sendTxn(
      usdc.approve(vault.address, expandDecimals("1000000", 6)),
      "approve USDC"
    );
    // await sendTxn(
    //   vault.deposit(usdt.address, expandDecimals("1000000", 6)),
    //   "deposit USDT"
    // );
    await sendTxn(
      vault.deposit(account, usdc.address, expandDecimals("1000000", 6)),
      "deposit USDC"
    );
    const isNative = false
    const pId1 = 0
    const pId2 = 1
    const pId3 = 2
    const currentTimestamp = 1670553346 //await getBlockTime(provider);
    const endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
    const endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
    const endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24 
    const rewardPerSec1 = expandDecimals(8267, 12)
    const rewardPerSec2 = expandDecimals(3858, 12)
    const rewardPerSec3 = expandDecimals(3858, 12)
    await sendTxn(eVela.setMinter(account, true), "set Minter");
    await sendTxn(eVela.mint(account, expandDecimals(10000000, 18)), "mint eVELA"); // mint eVELA
    const complexRewardPerSec1 = await deployContract("ComplexRewarderPerSec", [
        eVela.address,
        tokenFarm.address,
        isNative
    ])
    // const complexRewardPerSec1 = await contractAt('ComplexRewarderPerSec', '0x40befA12fACecF7C2287173CE0C46f9A14ad2572')
    const complexRewardPerSec2 = await deployContract("ComplexRewarderPerSec", [
        eVela.address,
        tokenFarm.address,
        isNative
    ])
    // const complexRewardPerSec2 = await contractAt('ComplexRewarderPerSec', '0x6d1dC1807D40049cA787768Bd9833968df42F3D8')
    const complexRewardPerSec3 = await deployContract("ComplexRewarderPerSec", [
        eVela.address,
        tokenFarm.address,
        isNative
    ])
    // const complexRewardPerSec3 = await contractAt('ComplexRewarderPerSec', '0x31888975C1516AF891e9Fc2Dc1b739d764Bce0e0')
    const amount = String(ethers.constants.MaxUint256)
    await eVela.setMinter(tokenFarm.address, true);
    await sendTxn(eVela.approve(complexRewardPerSec1.address,  amount), "Approve eVELA"); // VLP approve
    await sendTxn(eVela.approve(complexRewardPerSec2.address,  amount), "Approve eVELA"); // VELA approve
    await sendTxn(eVela.approve(complexRewardPerSec3.address,  amount), "Approve eVELA"); // eVELA approve
    await sendTxn(complexRewardPerSec1.add(pId1, currentTimestamp), "add pID1");
    await sendTxn(complexRewardPerSec2.add(pId2, currentTimestamp), "add pID2");
    await sendTxn(complexRewardPerSec3.add(pId3, currentTimestamp), "add pID3");
    await sendTxn(complexRewardPerSec1.addRewardInfo(
        pId1,
        endTimestamp1,
        rewardPerSec1
    ), "add RewardInfo 1");
    await sendTxn(complexRewardPerSec2.addRewardInfo(
        pId2,
        endTimestamp2,
        rewardPerSec2
    ), "add RewardInfo 2");
    await sendTxn(complexRewardPerSec3.addRewardInfo(
        pId3,
        endTimestamp3,
        rewardPerSec3
    ), "add RewardInfo 3");
    await sendTxn(tokenFarm.add(
        vlp.address,
        [complexRewardPerSec1.address],
        true
    ), "add Reward 1");
    await sendTxn(tokenFarm.add(
        vela.address,
        [complexRewardPerSec2.address],
        true
    ), "add Reward 2");
    await sendTxn(tokenFarm.add(
        eVela.address,
        [complexRewardPerSec3.address],
        false
    ), "add Reward 3");    
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
    await sendTxn(tokenFarm.updateRewardTierInfo(levels, percents), "updateRewardTierInfo");
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  