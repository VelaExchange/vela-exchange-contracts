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
  // +++++++++++++++++ 2022-08-25 16:04 ++++++++++++++++++++++
  // Deploying VLP 0x7bf2d1Cb75F0559B8d3966ddAE16aE406D8d774f
  // Deploying Vault 0x61f2887a449Da23668345B6da8Ead282fAC749C6 "0x277b5Efcc1F7eba9A4f1e8Fdd110A720733B9F7F" "0x6fA2af82bA9090654DBf4bBA7EF8E5aB69100649" "0x13Dc284FeAB37d4D7CAf2e1e09dbc9Ce4eE3C1f4" "0x4c5571727079351182Da2E30F89888401549B79D"
  // Deploying VaultUtils 0x63aFD12d47220C136eb6c9aCE74dE8795C423219 "0x8D003309880Da2B857da9787DBbA30c3dC6bE390" "0x6fA2af82bA9090654DBf4bBA7EF8E5aB69100649"
  const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
  const vlp = await contractAt(
    "VLP",
    "0x277b5Efcc1F7eba9A4f1e8Fdd110A720733B9F7F"
  );
  // await sendTxn(vlp.mint(account, expandDecimals('10000', 18)), "vlp minting")
  const vault = await contractAt(
    "Vault",
    "0x342806157C5c0d6cda2B2A043d35082aB9d1C7C2"
  );
  const vaultUtils = await contractAt(
    "VaultUtils",
    "0xE03Fd8a6412CB62eDeF32f09338b492c8962F829"
  )
  const indexToken = "0xc28fe92245adc11bb63a0054d425f9b5c1680f17";
  const posId = 1;
  const isLong = true;
  const orderType = 0;
  const lmtPrice = expandDecimals("0", 30);
  const stpPrice = expandDecimals("0", 30);
  const pendingCollateral = expandDecimals("10", 30);
  const pendingSize = expandDecimals("50", 30);
  const tpAmountPercent = expandDecimals("0", 5);
  const slAmountPercent = expandDecimals("0", 5);
  const tpPrice = expandDecimals("0", 30);
  const slPrice = expandDecimals("0", 30);
  const triggerPrices = [
    lmtPrice,
    stpPrice,
    pendingCollateral,
    pendingSize,
    tpAmountPercent,
    slAmountPercent,
    tpPrice,
    slPrice,
  ];
  const referAddress = ethers.constants.AddressZero;
  // const delayDeltaTime = await vaultUtils.delayDeltaTime()
  // const validateConfirmDelay = await vaultUtils.validateConfirmDelay(account, indexToken, isLong, posId, false);
  // await sendTxn(vault.confirmDelayTransaction(account, indexToken, isLong, posId), "confirmDelayTransaction");
  // await sendTxn(vault.newPositionOrder(
  //   indexToken,
  //   isLong,
  //   orderType,
  //   triggerPrices,
  //   referAddress
  // ), "Open New Market Order");
  // await sendTxn(vault.decreasePosition(
  //   indexToken,
  //   pendingSize,
  //   isLong,
  //   posId
  // ), "Close Position");
  const positionData = await vault.getPosition(
    account,
    indexToken,
    isLong,
    posId
  );
  console.log("positionData: ", 
    parseFloat(ethers.utils.formatUnits(positionData[0].pendingDelayCollateral, 30)),
    parseFloat(ethers.utils.formatUnits(positionData[0].pendingDelaySize, 30))
    )
  // const index = 0;
  // const delta = await vault.getDelta(indexToken, positionData[index], positionData[index + 3][1], isLong, positionData[index + 3][0])
  // console.log("next hasProfit : ", delta[0])
  // console.log("realisedPnl : ", ethers.utils.formatUnits(delta[1], 30))
  // const position_size = ethers.utils.formatUnits(positionData[index], 30);
  // const position_collateral = ethers.utils.formatUnits(
  //   positionData[index + 1],
  //   30
  // );
  // const position_hasRealisedProfit = positionData[index + 2].toString();
  // const position_lastIncreasedTime = positionData[index + 3][0].toString();
  // const position_averagePrice = ethers.utils.formatUnits(
  //   positionData[index + 3][1],
  //   30
  // );
  // const position_tpPrice = ethers.utils.formatUnits(positionData[index + 3][2], 30);
  // const position_slPrice = ethers.utils.formatUnits(positionData[index + 3][3], 30);
  // const position_lmtPrice = ethers.utils.formatUnits(
  //   positionData[index + 3][4],
  //   30
  // );
  // const position_stpPrice = ethers.utils.formatUnits(
  //   positionData[index + 3][5],
  //   30
  // );
  // const position_tpAmount = ethers.utils.formatUnits(
  //   positionData[index + 3][6],
  //   3
  // );
  // const position_slAmount = ethers.utils.formatUnits(
  //   positionData[index + 3][7],
  //   3
  // );
  // const position_pendingCollateral = ethers.utils.formatUnits(
  //   positionData[index + 3][8],
  //   30
  // );
  // const position_pendingSize = ethers.utils.formatUnits(
  //   positionData[index + 3][9],
  //   30
  // );
  // const position_entryFundingRate = positionData[index + 3][10].toString();
  // const position_reserveAmount = ethers.utils.formatUnits(
  //   positionData[index + 3][11],
  //   30
  // );
  // const position_stepAmount = ethers.utils.formatUnits(
  //   positionData[index + 3][12],
  //   30
  // );
  // const position_positionType = positionData[index + 3][13].toString();
  // const position_stepType = positionData[index + 3][14].toString();
  // const position_status = positionData[index + 3][15].toString();
  // const position_realisedPnl = positionData[index + 3][16].toString();
  // const position_confirmDelayStatus = positionData[index + 3][17].toNumber();
  // const position_delayStartTime = positionData[index + 3][18].toString();
  // console.log("positions size : ", position_size);
  // console.log("positions collateral : ", position_collateral);
  // console.log("positions hasRealisedPnl : ", position_hasRealisedProfit);
  // console.log("positions lastIncreasedTime : ", position_lastIncreasedTime);
  // console.log("positions averagePrice : ", position_averagePrice);
  // console.log("positions TP Price : ", position_tpPrice);
  // console.log("positions SL Price : ", position_slPrice);
  // console.log("positions Limit Price : ", position_lmtPrice);
  // console.log("positions Stop Price : ", position_stpPrice);
  // console.log("positions TP Amount Percent : ", position_tpAmount);
  // console.log("positions SL Amount Percent: ", position_slAmount);
  // console.log("positions pendingCollateral : ", position_pendingCollateral);
  // console.log("positions pendingSize : ", position_pendingSize);
  // console.log("positions entryFundingRate : ", position_entryFundingRate);
  // console.log("positions reserveAmount : ", position_reserveAmount);
  // console.log("positions position Type : ", position_positionType);
  // console.log("positions step Amount : ", position_stepAmount);
  // console.log("positions step Type : ", position_stepType);
  // console.log("positions status : ", position_status);
  // console.log("positions realisedPnl : ", position_realisedPnl);
  // console.log("positions confirmDelayStatus : ", position_confirmDelayStatus);
  // console.log("positions delayStartTime : ", position_delayStartTime);
  // console.log("positions delayDeltaTime : ", delayDeltaTime.toString());
  // console.log("validateConfirmDelay : ", validateConfirmDelay)
  // await sendTxn(vault.triggerPosition(account, token, true), "triggerPosition")
  // await sendTxn(vlp.setMinter(account, true), "set Minter");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
