const {
  deployContract,
  contractAt,
  sendTxn,
  writeTmpAddresses,
  readTmpAddresses,
} = require("../../shared/helpers");
const {
  expandDecimals,
  parseBytes32FromString,
} = require("../../shared/utilities");
const { ethers } = require("ethers");
const hre = require("hardhat");

function toUsd(value) {
  const normalizedValue = parseInt(value * Math.pow(10, 10));
  return ethers.BigNumber.from(normalizedValue).mul(
    ethers.BigNumber.from(10).pow(20)
  );
}

async function main() {
  //================== Deploy Process =========================
  const wethAddress = "0x007354C7DD2EB9f636204192092d7221c9d988F2";
  const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
  const vUSDCAddress = "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79";
  const vlpAddress = "0x020F88c59222241378B23325fdCFEc4ea3fF5199";
  const vlp = await contractAt("VLP", vlpAddress);
  const tokenFarmAddress = "0x43e1D1A1CAaE3801cf68D9EB7da94408A976F4E8";
  const vaultPriceFeed = await contractAt(
    "VaultPriceFeed",
    "0xb665E8E6F2031b143458866a940ec0E8BF58c34A"
  );
  const vault = await deployContract("Vault", [
    vlpAddress,
    vUSDCAddress,
    tokenFarmAddress,
    vaultPriceFeed.address
  ]);
  const vaultUtils = await deployContract("VaultUtils", [
    vault.address,
    vUSDCAddress,
  ]);
  // Deploying Vault 0xE465BEe14Cd580F118C5D0E63bCf3cD1388DF78e "0x020F88c59222241378B23325fdCFEc4ea3fF5199" "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79" "0x43e1D1A1CAaE3801cf68D9EB7da94408A976F4E8" "0xb665E8E6F2031b143458866a940ec0E8BF58c34A"
  // Deploying VaultUtils 0xcEa1D0c176eEB0F443142Bcc7e1CAcAf9957790B "0xE465BEe14Cd580F118C5D0E63bCf3cD1388DF78e" "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79"
  // const vault = await contractAt(
  //   "Vault",
  //   "0xE465BEe14Cd580F118C5D0E63bCf3cD1388DF78e"
  // );
  // const vaultUtils = await contractAt(
  //   "VaultUtils",
  //   "0xcEa1D0c176eEB0F443142Bcc7e1CAcAf9957790B"
  // );
  const positions = await vault.lastPosId(account);
  console.log(positions.toString());

  const btc = await contractAt(
    "BaseToken",
    "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec"
  );
  const eth = await contractAt(
    "BaseToken",
    "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17"
  );
  const dai = await contractAt(
    "BaseToken",
    "0x302321b51FEa7eeca55625b4B78D836623A43CFA"
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
  const ape = await contractAt(
    "BaseToken",
    "0x0E5DFdC9a2C96DFb234eB7b55629A789aa9dedf8"
  );

  const doge = await contractAt(
    "BaseToken",
    "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD"
  )
  // const btc_balanceOf = await btc.balanceOf(account);
  // const eth_balanceOf = await eth.balanceOf(account);
  // const dai_balanceOf = await dai.balanceOf(account);
  // const usdt_balanceOf = await usdt.balanceOf(account);
  // const usdc_balanceOf = await usdc.balanceOf(account);
  // const gbp_balanceOf = await gbp.balanceOf(account);
  // const eur_balanceOf = await eur.balanceOf(account);
  // const jpy_balanceOf = await jpy.balanceOf(account);
  // const ape_balanceOf = await ape.balanceOf(account);
  // console.log(
  //   "bitcoin balanceOf : ",
  //   ethers.utils.formatUnits(btc_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "eth balanceOf : ",
  //   ethers.utils.formatUnits(eth_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "dai balanceOf : ",
  //   ethers.utils.formatUnits(dai_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "usdt balanceOf : ",
  //   ethers.utils.formatUnits(usdt_balanceOf.toString(), 6)
  // );
  // console.log(
  //   "usdc balanceOf : ",
  //   ethers.utils.formatUnits(usdc_balanceOf.toString(), 6)
  // );
  // console.log(
  //   "gbp balanceOf : ",
  //   ethers.utils.formatUnits(gbp_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "eur balanceOf : ",
  //   ethers.utils.formatUnits(eur_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "jpy balanceOf : ",
  //   ethers.utils.formatUnits(jpy_balanceOf.toString(), 18)
  // );
  // console.log(
  //   "ape balanceOf : ",
  //   ethers.utils.formatUnits(ape_balanceOf.toString(), 18)
  // );

  const tokens = [
    {
      name: "btc",
      address: "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec",
      decimals: 18,
      priceFeed: "0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 80 / 100000
      isStrictStable: false,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: true,
      maxLeverage: 30 * 10000
    },
    {
      name: "eth",
      address: "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17",
      decimals: 18,
      priceFeed: "0xa142374C993c434C424A63390118451e5b396b57",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 80 / 100000
      isStrictStable: false,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: true,
      maxLeverage: 30 * 10000
    },
    {
      name: "gbp",
      address: "0x02311940c23D524Be839b958464B18084E127523",
      decimals: 18,
      priceFeed: "0x1675E6462580F6cCBfaB781958554D5990A9bbfe",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 8, // 0.008% 8 / 100000
      isStrictStable: true,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: false,
      maxLeverage: 100 * 10000
    },
    {
      name: "eur",
      address: "0x3a25e25A0059cd08C974a8672250E22012Fb1260",
      decimals: 18,
      priceFeed: "0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 8, // 0.008% 8 / 100000
      isStrictStable: true,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: false,
      maxLeverage: 100 * 10000
    },
    {
      name: "jpy",
      address: "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04",
      decimals: 18,
      priceFeed: "0xEA1AE30DCfC984e5d78D43EECE27f31083163eb6",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 8, // 0.008% 8 / 100000
      isStrictStable: true,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: false,
      maxLeverage: 100 * 10000
    },
    // {
    //   name: "ape",
    //   address: "0x0E5DFdC9a2C96DFb234eB7b55629A789aa9dedf8",
    //   decimals: 18,
    //   priceFeed: "0xA9cFD4E4E758e79EBD440081bA1971f32387Fc4B",
    //   priceDecimals: 8,
    //   minProfitBps: 0,
    //   marginFeeBasisPoints: 80, // 0.08% 8 / 100000
    //   isStrictStable: true,
    //   isStable: false,
    //   isDeposit: false,
    //   isStaking: false,
    //   isShortable: false,
    //   maxLeverage: 100 * 10000
    // },
    {
      name: "doge",
      address: "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD",
      decimals: 18,
      priceFeed: "0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 8 / 100000
      isStrictStable: true,
      isStable: false,
      isDeposit: false,
      isStaking: false,
      isShortable: false,
      maxLeverage: 30 * 10000
    },
    {
      name: "dai",
      address: "0x302321b51FEa7eeca55625b4B78D836623A43CFA",
      decimals: 18,
      priceFeed: "0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 80 / 100000
      isStrictStable: true,
      isStable: true,
      isDeposit: false,
      isStaking: false,
      isShortable: false,
      maxLeverage: 100 * 10000
    },
    {
      name: "usdc",
      address: "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b",
      decimals: 6,
      priceFeed: "0x1692Bdd32F31b831caAc1b0c9fAF68613682813b",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 80 / 100000
      isStrictStable: true,
      isStable: true,
      isDeposit: true,
      isStaking: true,
      isShortable: false,
      maxLeverage: 100 * 10000
    },
    {
      name: "usdt",
      address: "0x1d51eEcc9b82b63cb5630adB44a195200e25c123",
      decimals: 6,
      priceFeed: "0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E",
      priceDecimals: 8,
      minProfitBps: 0,
      marginFeeBasisPoints: 80, // 0.08% 80 / 100000
      isStrictStable: true,
      isStable: true,
      isDeposit: true,
      isStaking: true,
      isShortable: false,
      maxLeverage: 100 * 10000
    }
  ];
  for (const token of tokens) {
    await sendTxn(
      vault.setTokenConfig(
        token.address,
        token.isDeposit,
        token.isStaking,
        token.decimals,
        token.minProfitBps,
        token.maxLeverage,
        token.marginFeeBasisPoints
      ),
      `vaultPriceFeed.setTokenConfig(${token.name}) ${token.address}, ${token.decimals}`
    );
  }
  const updatedVlpRate = expandDecimals("1", 18);
  await sendTxn(vault.setVaultSettings(
    updatedVlpRate,
    86400,    // setCooldownDuration
    toUsd(0), // _liquidationFeeUsd
    1 * 60 * 60, // fundingInterval = 8 hours
    100, //  fundingRateFactor
    70000, // FeeRewardBasisPoints 70%
    24 * 60 * 60, // _minProfitTime
    vaultUtils.address // set vaultUtils address"
  ), "setVaultSettings")

  await sendTxn(vlp.setMinter(vault.address, true), "vlp SetMinter");
  await sendTxn(vault.setManager(account, true), "setPositionManager");
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

  const apeLastPrice = await vault.getLastPrice(ape.address);
  console.log(
    "APE lastPrice: ",
    ethers.utils.formatUnits(apeLastPrice, 30)
  );

  const dogeLastPrice = await vault.getLastPrice(doge.address);
  console.log(
    "DOGE lastPrice: ",
    ethers.utils.formatUnits(dogeLastPrice, 30)
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
