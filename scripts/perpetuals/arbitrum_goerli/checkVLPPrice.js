const {
    deployContract,
    contractAt,
    sendTxn,
  } = require("../../shared/helpers");
  const {
    expandDecimals,
    getBlockTime
  } = require("../../shared/utilities");
  const { ethers } = require("ethers");
  
  function toUsd(value) {
    const normalizedValue = parseInt(value * Math.pow(10, 10));
    return ethers.BigNumber.from(normalizedValue).mul(
      ethers.BigNumber.from(10).pow(20)
    );
  }
  
  async function main() {
    // const usdcAddress = "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b"
    // const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
    // const amount = expandDecimals("100", 6)
    // const vault = await contractAt('Vault', '0x7Cc082cc3552cf9B23a0f68B63Eb1d4e5054aCE3')
    // // await sendTxn(vault.withdraw(usdcAddress, account, amount), "withdraw USDC")
    // const vlpLastPrice = await vault.getVLPPrice();
    // console.log(
    //   "VLP lastPrice: ",
    //   ethers.utils.formatUnits(vlpLastPrice, 5)
    // );
    // const usdc = await contractAt("BaseToken", usdcAddress)
    // await sendTxn(usdc.approve(vault.address, amount), "approve USDC")
    // await sendTxn(vault.stake(account, usdcAddress, amount), "USDC Stake for Vault");
    // const vlpLastPriceAfterStake = await vault.getVLPPrice();
    // console.log(
    //   "VLP lastPrice After Stake: ",
    //   ethers.utils.formatUnits(vlpLastPriceAfterStake, 5)
    // );

    const usdcAddress = "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b"
    const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
    const amount = expandDecimals("20900", 30)
    const vault = await contractAt('Vault', '0x350B4A1BEBf50A52137af8db2D857aACf802b3c8')
    await sendTxn(vault.withdraw(usdcAddress, account, amount), "withdraw USDC")
    const vlpLastPrice = await vault.getVLPPrice();
    console.log(
      "VLP lastPrice: ",
      ethers.utils.formatUnits(vlpLastPrice, 5)
    );
    const usdc = await contractAt("BaseToken", usdcAddress)
    const totalVLP = await vault.totalVLP()
    console.log("totalVLP : ", ethers.utils.formatUnits(totalVLP, 18))
    const totalUSDC = await vault.totalUSDC()
    console.log("totalUSDC : ", ethers.utils.formatUnits(totalUSDC, 30))

}
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  