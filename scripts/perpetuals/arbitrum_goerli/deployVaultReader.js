const { deployContract, contractAt } = require("../../shared/helpers");
const { ethers } = require("ethers");
const hre = require("hardhat");

async function main() {
  const vaultReader = await deployContract("VaultReader", []);
  // Deploying VaultReader 0x107f32C434DBc33536DD94D9C251ffe517214e7c
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
