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
  //================== Deploy Process =========================
  const vlp = await deployContract("VLP", []);
  // ++++++++++++++++++++++++++ 2022.09.28 10.27AM ++++++++++++++++++++++++++++
  // Deploying VLP 0x277b5Efcc1F7eba9A4f1e8Fdd110A720733B9F7F
  // ++++++++++++++++++++++++++ 2022.11.21 10.27AM ++++++++++++++++++++++++++++
  // Deploying VLP 0x020F88c59222241378B23325fdCFEc4ea3fF5199

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
