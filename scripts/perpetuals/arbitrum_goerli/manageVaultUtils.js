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

async function main() {
  const vaultUtils = await contractAt(
    "VaultUtils",
    "0xcEa1D0c176eEB0F443142Bcc7e1CAcAf9957790B"
  );
  const delayDelatTime = 20;
  await sendTxn(vaultUtils.setDelayDeltaTime(delayDelatTime), "setDelayDeltaTime")
  const account = "0x0a52c4cd73157bcfdd4a7c570106016db2749b05";
  const indexToken = "0xa36f5ea837a1925252eb5dc5a3605c9c3ba840ec";
  const indexToken2 = "0x02311940c23D524Be839b958464B18084E127523";
  const posId = 2;
  const isLong = true;
  // const validateTrigger = await vaultUtils.validateTrigger(account, indexToken, isLong, posId)
  // console.log("validateTrigger : ", validateTrigger)
  // const validateLiquidation = await vaultUtils.validateLiquidation(
  //   account,
  //   indexToken,
  //   isLong,
  //   posId,
  //   false
  // );
  // console.log(
  //   "validateLiquidation : ",
  //   validateLiquidation[0].toNumber(),
  //   ethers.utils.formatUnits(validateLiquidation[1], 30)
  // );
  // const vault = await contractAt(
  //   "Vault",
  //   "0x8D003309880Da2B857da9787DBbA30c3dC6bE390"
  // );
  // await sendTxn(
  //   vault.liquidatePosition(account, indexToken, isLong, posId),
  //   ""
  // );
  const btcAddress = "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec"
  const ethAddress = "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17"
  const gbpAddress = "0x02311940c23D524Be839b958464B18084E127523"
  const eurAddress = "0x3a25e25A0059cd08C974a8672250E22012Fb1260"
  const jpyAddress = "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04"
  const apeAddress = "0x0E5DFdC9a2C96DFb234eB7b55629A789aa9dedf8"
  const dogeAddress = "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD"
  const BTCLiquidateThreshold = 99000;
  const BTCMaxBorrowAmount = expandDecimals('10000000000', 30)
  const ETHLiquidateThreshold = 99000;
  const ETHMaxBorrowAmount = expandDecimals('10000000000', 30)
  const GBPLiquidateThreshold = 99700;
  const GBPMaxBorrowAmount = expandDecimals('10000000000', 30)
  const EURLiquidateThreshold = 99700;
  const EURMaxBorrowAmount = expandDecimals('10000000000', 30)
  const JPYLiquidateThreshold = 99700;
  const JPYMaxBorrowAmount = expandDecimals('10000000000', 30)
  // const APELiquidateThreshold = 99000;
  // const APEMaxBorrowAmount = expandDecimals('10000000000', 30)
  const DOGELiquidateThreshold = 99000;
  const DOGEMaxBorrowAmount = expandDecimals('10000000000', 30)
  const LONGMaxBorrowAmount = expandDecimals('1000000000000', 30)
  const SHORTMaxBorrowAmount = expandDecimals('1000000000000', 30)
  const USERMaxBorrowAmount = expandDecimals('10000000000', 30)
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(BTCLiquidateThreshold, btcAddress),
  //   "setLiquidateThreshold for BTC"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(btcAddress, BTCMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for BTC"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(ETHLiquidateThreshold, ethAddress),
  //   "setLiquidateThreshold for ETH"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(ethAddress, ETHMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for ETH"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(GBPLiquidateThreshold, gbpAddress),
  //   "setLiquidateThreshold for GBP"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(gbpAddress, GBPMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for GBP"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(EURLiquidateThreshold, eurAddress),
  //   "setLiquidateThreshold for EUR"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(eurAddress, EURMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for EUR"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(JPYLiquidateThreshold, jpyAddress),
  //   "setLiquidateThreshold for JPY"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(jpyAddress, JPYMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for JPY"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(APELiquidateThreshold, apeAddress),
  //   "setLiquidateThreshold for APE"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(apeAddress, APEMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for APE"
  // );
  // await sendTxn(
  //   vaultUtils.setLiquidateThreshold(DOGELiquidateThreshold, dogeAddress),
  //   "setLiquidateThreshold for DOGE"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerAsset(dogeAddress, DOGEMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for DOGE"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerSide(true, LONGMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for LONG"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerSide(false, SHORTMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for SHORT"
  // );
  // await sendTxn(
  //   vaultUtils.setMaxBorrowAmountPerUser(USERMaxBorrowAmount),
  //   "setMaxBorrowUSDAmount for USER"
  // );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
