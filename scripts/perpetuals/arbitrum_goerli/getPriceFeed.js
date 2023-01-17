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
  //================== Deploy Process =========================
  const priceFeed = await contractAt(
    "PriceFeed",
    "0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08"
  );
  const aggreator = await priceFeed.aggregator();
  console.log("aggreator : ", aggreator);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
