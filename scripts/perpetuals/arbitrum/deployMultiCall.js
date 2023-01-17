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
  // Deploying Multicall 0x02E34aeb59c60744d5C365d58C158636908C716F
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
