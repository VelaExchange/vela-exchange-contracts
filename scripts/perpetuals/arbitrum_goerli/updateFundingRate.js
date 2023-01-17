const { contractAt, sendTxn } = require("../../shared/helpers");
const { ethers } = require("ethers");
const hre = require("hardhat");

async function main() {
  const fundingInterval = 8 * 60 * 60;
  const fundingRateFactor = 100;
  const stableFundingRateFactor = 100;
  const vault = await contractAt(
    "Vault",
    "0x1dbA200926F133e0b8f5a5b84fc52ED652a8B821"
  );
  await sendTxn(
    vault.setFundingRate(
      fundingInterval,
      fundingRateFactor,
      stableFundingRateFactor
    ),
    "setFundingRate"
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
