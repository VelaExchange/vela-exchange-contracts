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
    const feeManagerAddress = "0x07D50fF33854C5836552987E9eAE05170ED5ed4D"
    const ownerAddress = "0x07D50fF33854C5836552987E9eAE05170ED5ed4D"
    const positionManagerAddress = "0x55D1f8d58549e622234DA0097Fc262eb331Be5b1"
    // 1. deploy VUSD
    // const vUSDC = await deployContract('vUSDC', [name, symbol, initialSupply])
    const vUSDC = await contractAt('vUSDC', '0xf44ef703FE8248Cd1b23BF9d8C1e0289F19BA9FE')
    
    // 2. deploy VLP
    // const vlp = await deployContract("VLP", [])
    const vlp = await contractAt('VLP', '0xEF1C7E526DB9406AB3cFbf3FA08394426561a92E')

    // 3. deploy VELA
    const vela = await contractAt('Vela', '0x088cd8f5eF3652623c22D48b1605DCfE860Cd704')
    
    // 4. deploy EVELA
    // const eVela = await deployContract("eVELA", []);
    const eVela = await contractAt('eVELA', '0xC76F05D49e8349B95b38750fb6a2E91719B6B3EC')

    // 5. deploy TokenFarm
    const vestingDuration = 365 * 24 * 60 * 60;
    const unbondingPeriod = 14 * 24 * 60 * 60;
    const cooldownDuration = 86400
    const liquidationFeeUsd = 0 // _liquidationFeeUsd
    const fundingInterval = 1 * 60 * 60 // fundingInterval = 8 hours
    const fundingRateFactor = 100 //  fundingRateFactor
    const feeRewardBasisPoints = 70000 // FeeRewardBasisPoints 70%
    const depositFee = 3000
    const stakingFee = 3000
    // const tokenFarm = await deployContract("TokenFarm", [
    //   vestingDuration,
    //   eVela.address,
    //   vela.address,
    // ]);
    const tokenFarm = await contractAt("TokenFarm", "0x54656fCD7cBf9F3b50D2eEa1f5af59feA3677206")
    // 6. deploy VaultPriceFeed
    // const vaultPriceFeed = await deployContract("VaultPriceFeed", []);
    const vaultPriceFeed = await contractAt("VaultPriceFeed", '0xF82D30B70405a3af72d10849d0D6E4554F2103F8');
    const tokens = [
        // {
        //   name: "btc",
        //   address: "0x61159e7Cb1F06476A217DaBDb5e03527aB69217A",
        //   decimals: 18,
        //   priceDecimals: 8,
        //   priceFeed: "0x6ED562a792214AC325F2682302bD690237c6c08E",
        //   marginFeeBasisPoints: 80, // 0.08% 80 / 100000
        //   maxLeverage: 30 * 10000
        // },
        // {
        //   name: "eth",
        //   address: "0xA6E249FFB81cF6f28aB021C3Bd97620283C7335f",
        //   decimals: 18,
        //   priceDecimals: 8,
        //   priceFeed: "0xE5ad377d9EBfFaA3dc1424AC2C8452F161377215",
        //   marginFeeBasisPoints: 80, // 0.08% 80 / 100000
        //   maxLeverage: 30 * 10000
        // },
        // {
        //   name: "gbp",
        //   address: "0xf34BF1185c190dab28ccF0Bb0BD22D312273D28b",
        //   decimals: 18,
        //   priceDecimals: 8,
        //   priceFeed: "0x8E6C73422032FcCAEb6ce2a4083EE389C40C08bE",
        //   marginFeeBasisPoints: 8, // 0.008% 8 / 100000
        //   maxLeverage: 100 * 10000
        // },
        // {
        //   name: "eur",
        //   address: "0xb04ed6FFE5f6A7a19B47d5a78f43C694901E449b",
        //   decimals: 18,
        //   priceDecimals: 8,
        //   priceFeed: "0xb4f7Fde31cE1e03F233d0b4c18D4000138C1Bf33",
        //   marginFeeBasisPoints: 8, // 0.008% 8 / 100000
        //   maxLeverage: 100 * 10000
        // },
        {
          name: "jpy",
          address: "0x194a51Dce44a2f9Faea3480459365F53bD7702F7",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0x707B8FE57cECCcCCd129f182285144C0D7437cD2",
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "doge",
          address: "0xD1C8Cb78887E1254df137f3Ebb9FADa152679eE4",
          decimals: 18,
          priceDecimals: 8,
          priceFeed: "0xb0311A44E541F6d0b491989a494C279BE8ece2EE",
          marginFeeBasisPoints: 80, // 0.08% 8 / 100000
          maxLeverage: 30 * 10000
        },
        {
          name: "usdc",
          address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
          decimals: 6,
          priceDecimals: 8,
          priceFeed: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 100 * 10000
        },
        {
          name: "usdt",
          address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
          decimals: 6,
          priceDecimals: 8,
          priceFeed: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          maxLeverage: 100 * 10000
        },
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
    // const vault = await deployContract("Vault", [
    //   vlp.address,
    //   vUSDC.address,
    //   tokenFarm.address,
    //   vaultPriceFeed.address
    // ]);
    const vault = await contractAt("Vault", "0x4C72071Bb8F2924b56Aa1Aa3f500A7467eeeDd6C")
    // const priceManager = await deployContract("PriceManager", [
    //     vaultPriceFeed.address
    //   ])
    const priceManager = await contractAt("PriceManager", "0xF230C50115445A402487aeaA78acDd9D4C5b362D")
    // const settingsManager = await deployContract("SettingsManager",
    //     [
    //       vault.address,
    //       vUSDC.address
    //     ]
    //   )
    const settingsManager = await contractAt("SettingsManager", "0xB645c7A0706576bDC68C1530E1BE2758b79D6081")
    // const triggerOrderManager = await deployContract("TriggerOrderManager",
    //     [
    //       vault.address,
    //       priceManager.address
    //     ]
    //   )
    const triggerOrderManager = await contractAt("TriggerOrderManager",
      "0x2091964bAd4f1D2DdeB78b94910dD49Bc6Fd4Da9"
    )
    // 8. Deploy VaultUtils
    // const vaultUtils = await deployContract("VaultUtils", [
    //   vault.address,
    //   vUSDC.address,
    //   tokenFarm.address,
    //   priceManager.address,
    //   settingsManager.address
    // ]);
    const vaultUtils = await contractAt("VaultUtils", "0xef755855834a1d57EB98DC5f1DB91027500ce54e")
    // await sendTxn(vault.setVaultSettings(
    //     priceManager.address,    // setCooldownDuration
    //     settingsManager.address, // FeeRewardBasisPoints 70%
    //     triggerOrderManager.address, // set vaultUtils address"
    //     vaultUtils.address
    //   ), "setVaultSettings")    
    for (const token of tokens) {
      await sendTxn(
        priceManager.setTokenConfig(
          token.address,
          token.decimals,
          token.maxLeverage,
        ),
        `priceManager.setTokenConfig(${token.name}) ${token.address}, ${token.decimals}`
      );
    }

  
    await sendTxn(vlp.setMinter(vault.address, true), "vlp SetMinter");
    await sendTxn(vault.setManager(positionManagerAddress, true), "setPositionManager");
    const btc = await contractAt(
      "BaseToken",
      "0x61159e7Cb1F06476A217DaBDb5e03527aB69217A"
    );
    const eth = await contractAt(
      "BaseToken",
      "0xA6E249FFB81cF6f28aB021C3Bd97620283C7335f"
    );
    const gbp = await contractAt(
      "BaseToken",
      "0xf34BF1185c190dab28ccF0Bb0BD22D312273D28b"
    );
    const eur = await contractAt(
      "BaseToken",
      "0xb04ed6FFE5f6A7a19B47d5a78f43C694901E449b"
    );
    const jpy = await contractAt(
      "BaseToken",
      "0x194a51Dce44a2f9Faea3480459365F53bD7702F7"
    );
    const doge = await contractAt(
      "BaseToken",
      "0xD1C8Cb78887E1254df137f3Ebb9FADa152679eE4"
    )
    const usdc = await contractAt(
      "BaseToken",
      "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
    );
    const usdt = await contractAt(
      "BaseToken",
      "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
    );

    const ethLastPrice = await priceManager.getLastPrice(eth.address);
    console.log(
      "ETH maxPrice: ",
      ethers.utils.formatUnits(ethLastPrice, 30)
    );
    const btcLastPrice = await priceManager.getLastPrice(btc.address);
    console.log(
      "BTC lastPrice: ",
      ethers.utils.formatUnits(btcLastPrice, 30)
    );
    const usdtLastPrice = await priceManager.getLastPrice(usdt.address);
    console.log(
      "USDT lastPrice: ",
      ethers.utils.formatUnits(usdtLastPrice, 30)
    );
    const usdcLastPrice = await priceManager.getLastPrice(usdc.address);
    console.log(
      "USDC lastPrice: ",
      ethers.utils.formatUnits(usdcLastPrice, 30)
    );
    const gbpLastPrice = await priceManager.getLastPrice(gbp.address);
    console.log(
      "GBP lastPrice: ",
      ethers.utils.formatUnits(gbpLastPrice, 30)
    );
    const eurLastPrice = await priceManager.getLastPrice(eur.address);
    console.log(
      "EUR lastPrice: ",
      ethers.utils.formatUnits(eurLastPrice, 30)
    );
    const jpyLastPrice = await priceManager.getLastPrice(jpy.address);
    console.log(
      "JPY lastPrice: ",
      ethers.utils.formatUnits(jpyLastPrice, 30)
    );
    const dogeLastPrice = await priceManager.getLastPrice(doge.address);
    console.log(
      "DOGE lastPrice: ",
      ethers.utils.formatUnits(dogeLastPrice, 30)
    );
    await sendTxn(vUSDC.addAdmin(vault.address), "addAdmin vault");
    await sendTxn(vUSDC.addAdmin(vaultUtils.address), "addAdmin vaultUtils");
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
    const ETHLongFundingRateFactor = 75;
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
        settingsManager.setLiquidateThreshold(BTCLiquidateThreshold, btc.address),
      "setLiquidateThreshold for BTC"
    );
    // await sendTxn(
    //     settingsManager.setMaxBorrowAmountPerAsset(btc.address, BTCMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for BTC"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(btc.address, true, BTCLongFundingRateFactor),
    //   "setFundingRateFactor Long for BTC"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(btc.address, false, BTCShortFundingRateFactor),
    //   "setFundingRateFactor Short for BTC"
    // );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(btc.address, true, BTCLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for BTC Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(btc.address, false, BTCShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for BTC Short"
    );
    await sendTxn(
        settingsManager.setLiquidateThreshold(ETHLiquidateThreshold, eth.address),
      "setLiquidateThreshold for ETH"
    );
    // await sendTxn(
    //     settingsManager.setMaxBorrowAmountPerAsset(eth.address, ETHMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for ETH"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(eth.address, true, ETHLongFundingRateFactor),
    //   "setFundingRateFactor Long for ETH"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(eth.address, false, ETHShortFundingRateFactor),
    //   "setFundingRateFactor Short for ETH"
    // );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(eth.address, true, ETHLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for ETH Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(eth.address, false, ETHShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for ETH Short"
    );
    await sendTxn(
        settingsManager.setLiquidateThreshold(DOGELiquidateThreshold, doge.address),
      "setLiquidateThreshold for DOGE"
    );
    // await sendTxn(
    //   settingsManager.setMaxBorrowAmountPerAsset(doge.address, DOGEMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for DOGE"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(doge.address, true, DOGELongFundingRateFactor),
    //   "setFundingRateFactor Long for DOGE"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(doge.address, false, DOGEShortFundingRateFactor),
    //   "setFundingRateFactor Short for DOGE"
    // );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(doge.address, true, DOGELongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for DOGE Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(doge.address, false, DOGEShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for DOGE Short"
    );
    await sendTxn(
        settingsManager.setLiquidateThreshold(GBPLiquidateThreshold, gbp.address),
      "setLiquidateThreshold for GBP"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(gbp.address, true, GBPLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for GBP Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(gbp.address, false, GBPShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for GBP Short"
    );
    await sendTxn(
        settingsManager.setLiquidateThreshold(EURLiquidateThreshold, eur.address),
      "setLiquidateThreshold for EUR"
    );
    // await sendTxn(
    //   settingsManager.setMaxBorrowAmountPerAsset(gbp.address, GBPMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for GBP"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(gbp.address, true, GBPLongFundingRateFactor),
    //   "setFundingRateFactor Long for GBP"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(gbp.address, false, GBPShortFundingRateFactor),
    //   "setFundingRateFactor Short for GBP"
    // );
    // await sendTxn(
    //   settingsManager.setMaxBorrowAmountPerAsset(eur.address, EURMaxBorrowAmount),
    //   "setMaxBorrowAmountPerAsset for EUR"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(eur.address, true, EURLongFundingRateFactor),
    //   "setFundingRateFactor Long for EUR"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(eur.address, false, EURShortFundingRateFactor),
    //   "setFundingRateFactor Short for EUR"
    // );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(eur.address, true, EURLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for EUR Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(eur.address, false, EURShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for EUR Short"
    );
    await sendTxn(
        settingsManager.setLiquidateThreshold(JPYLiquidateThreshold, jpy.address),
      "setLiquidateThreshold for JPY"
    );
    // await sendTxn(
    //   settingsManager.setMaxBorrowAmountPerAsset(jpy.address, JPYMaxBorrowAmount),
    //   "setLiquidateThreshold for JPY"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(jpy.address, true, JPYLongFundingRateFactor),
    //   "setFundingRateFactor Long for JPY"
    // );
    // await sendTxn(
    //   settingsManager.setFundingRateFactor(jpy.address, false, JPYShortFundingRateFactor),
    //   "setFundingRateFactor Short for JPY"
    // );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(jpy.address, true, JPYLongMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for JPY Long"
    );
    await sendTxn(
        settingsManager.setMarginFeeBasisPoints(jpy.address, false, JPYShortMarginFeeBasisPoints),
      "setMarginFeeBasisPoints for JPY Short"
    );
    await sendTxn(
      settingsManager.setMaxBorrowAmountPerSide(true, LONGMaxBorrowAmount),
      "setMaxBorrowAmountPerSide for Long"
    );
    await sendTxn(
      settingsManager.setMaxBorrowAmountPerSide(false, SHORTMaxBorrowAmount),
      "setMaxBorrowAmountPerSide for Short"
    );
    await sendTxn(
      settingsManager.setMaxBorrowAmountPerUser(USERMaxBorrowAmount),
      "setMaxBorrowAmountPerUser"
    );
    // await sendTxn(
    //   settingsManager.setEnableDeposit(usdt.address, true),
    //   "setEnableDeposit for USDT"
    // );
    // await sendTxn(
    //   settingsManager.setEnableStaking(usdt.address, true),
    //   "setEnableStaking for USDT"
    // );
    await sendTxn(
        settingsManager.setEnableDeposit(usdc.address, true),
      "setEnableDeposit for USDC"
    );
    await sendTxn(
        settingsManager.setEnableStaking(usdc.address, true),
      "setEnableStaking for USDC"
    );
    await sendTxn(
      settingsManager.setFeeManager(feeManagerAddress),
      "setFeeManager"
    );
    // const usdcBalance = await usdc.balanceOf(account)
    // console.log("usdcBalance : ", ethers.utils.formatUnits(usdcBalance, 6))
    // await sendTxn(
    //   usdt.approve(vault.address, expandDecimals("1000000", 6)),
    //   "approve USDT"
    // );
    // await sendTxn(
    //   vault.deposit(usdt.address, expandDecimals("1000000", 6)),
    //   "deposit USDT"
    // );
    // await sendTxn(
    //   usdc.approve(vault.address, expandDecimals("1000000", 6)),
    //   "approve USDC"
    // );
    // await sendTxn(
    //   vault.deposit(account, usdc.address, expandDecimals("1000000", 6)),
    //   "deposit USDC"
    // );
    const isNative = false
    // const pId1 = 0
    // const pId2 = 1
    // const pId3 = 2
    // const currentTimestamp = 1672325017 //await getBlockTime(provider);
    // const endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
    // const endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
    // const endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24 
    // const rewardPerSec1 = expandDecimals(8267, 12)
    // const rewardPerSec2 = expandDecimals(3858, 12)
    // const rewardPerSec3 = expandDecimals(3858, 12)
    // await sendTxn(eVela.setMinter(account, true), "set Minter");
    // await sendTxn(eVela.mint(account, expandDecimals(10000000, 18)), "mint eVELA"); // mint eVELA
    // const complexRewardPerSec1 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    const complexRewardPerSec1 = await contractAt('ComplexRewarderPerSec', '0xDDE2cbe990363f9D527E2Ded308Bab5556a38aa9')
    // const complexRewardPerSec2 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    const complexRewardPerSec2 = await contractAt('ComplexRewarderPerSec', '0xBcaE45af56b37806915796012Bbf7DFa62697c7d')
    // const complexRewardPerSec3 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    const complexRewardPerSec3 = await contractAt('ComplexRewarderPerSec', '0xaA8bdDC5Fb7B995369658A724286a53935231a94')
    // const amount = String(ethers.constants.MaxUint256)
    // await eVela.setMinter(tokenFarm.address, true);
    await sendTxn(complexRewardPerSec1.add(pId1, currentTimestamp), "add pID1");
    await sendTxn(complexRewardPerSec2.add(pId2, currentTimestamp), "add pID2");
    await sendTxn(complexRewardPerSec3.add(pId3, currentTimestamp), "add pID3");
    // await sendTxn(eVela.approve(complexRewardPerSec1.address,  amount), "Approve eVELA"); // VLP approve
    // await sendTxn(eVela.approve(complexRewardPerSec2.address,  amount), "Approve eVELA"); // VELA approve
    // await sendTxn(eVela.approve(complexRewardPerSec3.address,  amount), "Approve eVELA"); // eVELA approve
    // await sendTxn(complexRewardPerSec1.addRewardInfo(
    //     pId1,
    //     endTimestamp1,
    //     rewardPerSec1
    // ), "add RewardInfo 1");
    // await sendTxn(complexRewardPerSec2.addRewardInfo(
    //     pId2,
    //     endTimestamp2,
    //     rewardPerSec2
    // ), "add RewardInfo 2");
    // await sendTxn(complexRewardPerSec3.addRewardInfo(
    //     pId3,
    //     endTimestamp3,
    //     rewardPerSec3
    // ), "add RewardInfo 3");
    // await sendTxn(tokenFarm.add(
    //     vlp.address,
    //     [complexRewardPerSec1.address],
    //     true
    // ), "add Reward 1");
    // await sendTxn(tokenFarm.add(
    //     vela.address,
    //     [complexRewardPerSec2.address],
    //     true
    // ), "add Reward 2");
    // await sendTxn(tokenFarm.add(
    //     eVela.address,
    //     [complexRewardPerSec3.address],
    //     false
    // ), "add Reward 3");    
    const levels = [
      expandDecimals('500', 18),
      expandDecimals('2500', 18),
      expandDecimals('5000', 18),
      expandDecimals('10000', 18),
      expandDecimals('25000', 18),
      expandDecimals('50000', 18),
      expandDecimals('100000', 18),
      expandDecimals('250000', 18),
      expandDecimals('500000', 18)
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
  