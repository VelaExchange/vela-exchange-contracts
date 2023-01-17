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
    const vault = await contractAt(
      "Vault",
      "0xcAFF3B221993910a5073C22740Edd68577177a35"
    );
    const vaultUtils = await contractAt(
      "VaultUtils",
      "0xb39903ab48fE69418A538F2A4b45c17BE5368F40"
    )
    const triggerOrderManager = await contractAt(
        "TriggerOrderManager",
        "0xAFc9Bea13e43BD52E395bcAC38AFF427bfEEfC01"
    )
    const indexToken = "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17";
    const posId = 0;
    const isLong = true;
    const tpPrices = [
      expandDecimals('1250', 30),
      expandDecimals('1300', 30),
      expandDecimals('1350', 30)
    ]
    const tpAmountPercents = [
      50000,
      30000,
      20000
    ]
    const slPrices = [
      expandDecimals('1120', 30)
    ]
    const slAmountPercents = [
      100000
    ]
    await sendTxn(triggerOrderManager.updateTriggerOrders(
        indexToken, 
        isLong, 
        posId, 
        tpPrices, 
        slPrices, 
        tpAmountPercents, 
        slAmountPercents
      ), "UpdateTriggerOrders")
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  