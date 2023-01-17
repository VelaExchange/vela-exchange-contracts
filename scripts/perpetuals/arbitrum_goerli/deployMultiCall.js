const { deployContract, contractAt } = require("../../shared/helpers");
const { ethers } = require("ethers");
const hre = require("hardhat");

function toUsd(value) {
  const normalizedValue = parseInt(value * Math.pow(10, 10));
  return ethers.BigNumber.from(normalizedValue).mul(
    ethers.BigNumber.from(10).pow(20)
  );
}

async function main() {
  const vlp = await deployContract("Multicall", []);
  // Deploying VLP 0x997f4A098e3010a2CCf9F299F1A7Dc86D8F99674
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
