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
  const vUSDCAddress = "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79";
  const claimAmount = expandDecimals("10000", 30);
  const currentTime = 1669042902;
  const expirationTime = currentTime + 22 * 24 * 60 * 60;
  const betaTrading = await deployContract("BetaTrading", [vUSDCAddress, expirationTime, claimAmount]);
  const vUSDC = await contractAt("vUSDC", vUSDCAddress);
  // const betaTrading = await contractAt(
  //   "BetaTrading",
  //   "0xd56A014bd6E9f642b6fA4fFA8fbe7C1E8a574fEe"
  // );
  await sendTxn(vUSDC.addAdmin(betaTrading.address), "addAdmin for betaTrading")
  // await sendTxn(betaTrading.claim(), "Claim")
  await sendTxn(
    betaTrading.updateExpirationTime(expirationTime),
    "updateExpirationTime"
  );
  const allHolders = await betaTrading.getVUSDHolders();
  console.log("allHolders : ", allHolders);
  // Deploying BetaTrading 0x5F55e02602967B374CbA38eAC2C68aF28C209D00 "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79" "1670943702" "10000000000000000000000000000000000"
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
