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
  const name = "Vested USDC";
  const symbol = "VUSDC";
  const initialSupply = 0;
  const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
  const vaultAddress = "0xE465BEe14Cd580F118C5D0E63bCf3cD1388DF78e";
  const vaultUtilsAddress = "0xcEa1D0c176eEB0F443142Bcc7e1CAcAf9957790B";
  // const vUSDC = await deployContract('vUSDC', [name, symbol, initialSupply])
  // Deploying vUSDC 0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79 "Vested USDC" "VUSDC" "0"
  const vUSDC = await contractAt(
    "vUSDC",
    "0x8d41FA7f0aC4444c6D4BaE9e9a02C4e4aa60cb79"
  );
  // await sendTxn(vUSDC.addAdmin(account), "addAdmin")
  // await sendTxn(vUSDC.mint(account, expandDecimals("10000000", 30)), "vUSD mint")
  const usdc = await contractAt(
    "Token",
    "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b"
  );
  const usdt = await contractAt(
    "Token",
    "0x1d51eEcc9b82b63cb5630adB44a195200e25c123"
  );
  const vusd_balanceOf = await vUSDC.balanceOf(account);
  const usdt_balanceOf = await usdt.balanceOf(account);
  const usdc_balanceOf = await usdc.balanceOf(account);
  console.log(
    "vusd balanceOf : ",
    ethers.utils.formatUnits(vusd_balanceOf.toString(), 30)
  );
  console.log(
    "usdt balanceOf : ",
    ethers.utils.formatUnits(usdt_balanceOf.toString(), 6)
  );
  console.log(
    "usdc balanceOf : ",
    ethers.utils.formatUnits(usdc_balanceOf.toString(), 6)
  );
  const user1 = "0x8426793B4ebfce022997Eb4D6303822ca64037f6";
  const user2 = "0xd54e8e0E50F90278079C6BaDA3d4F84ab812089b";
  const user3 = "0x4EDC01b119A224DbC0fa1297A6acA3f02af5a58d";
  const balanceOf = await vUSDC.balanceOf(user1);
  const balanceOf2 = await vUSDC.balanceOf(user2);
  const balanceOf3 = await vUSDC.balanceOf(user3);
  console.log("Balance : ", ethers.utils.formatUnits(balanceOf, 30));
  console.log("Balance2 : ", ethers.utils.formatUnits(balanceOf2, 30));
  console.log("balanceOf3 : ", ethers.utils.formatUnits(balanceOf3, 30));
  // const burnAmount = '9999999999063.921178363618632773136560153431';
  // await sendTxn(vUSDC.burn(user2, ethers.utils.parseUnits(burnAmount, 30)), "burn fake token")
  const vault = await contractAt("Vault", vaultAddress);
  await sendTxn(vUSDC.addAdmin(vaultAddress), "addAdmin vault");
  await sendTxn(vUSDC.addAdmin(vaultUtilsAddress), "addAdmin vaultUtils");
  // const poolAmounts = await vault.poolAmounts()
  // console.log("pool amounts : ", ethers.utils.formatUnits(poolAmounts, 30))
  // await sendTxn(usdt.mint(account, expandDecimals("1000000", 6)), "usdt mint");
  // await sendTxn(usdc.mint(account, expandDecimals("1000000", 6)), "usdc mint");
  await sendTxn(
    vUSDC.mint(vaultAddress, expandDecimals("1000000", 30)),
    "usdc mint"
  );
  await sendTxn(
    usdt.approve(vaultAddress, expandDecimals("1000000", 6)),
    "approve USDT"
  );
  await sendTxn(
    usdc.approve(vaultAddress, expandDecimals("1000000", 6)),
    "approve USDC"
  );
  await sendTxn(
    vault.deposit(account, usdt.address, expandDecimals("1000000", 6)),
    "deposit USDT"
  );
  await sendTxn(
    vault.deposit(account, usdc.address, expandDecimals("1000000", 6)),
    "deposit USDC"
  );
  // const poolAmounts2 = await vault.poolAmounts()
  // console.log("pool amounts : ", ethers.utils.formatUnits(poolAmounts2, 30))
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
