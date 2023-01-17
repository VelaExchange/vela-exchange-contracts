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
    //================== Deploy Process =========================
    const account = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05";
    const vlp = await contractAt('VLP', '0x020F88c59222241378B23325fdCFEc4ea3fF5199')
    const eVela = await contractAt('eVELA', '0x1fd018999420dAb0f98032e8831C0A735f55EDd0')
    const vela = await contractAt('MintableBaseToken', '0x22B1E7E25ce22251DAf656B7c85b0fcc16d8aF8D')
    const tokenFarm = await contractAt("TokenFarm", "0x0029B3851b2872e809fb92e62682F6CDd91B7538")
    const poolLength = await tokenFarm.poolLength()
    console.log("poolLength : ", poolLength.toNumber())
    // const isNative = false
    // const pId1 = 0
    // const pId2 = 1
    // const pId3 = 2
    // const currentTimestamp = 1672150161 //await getBlockTime(provider);
    // const endTimestamp1 = currentTimestamp + 14 * 60 * 60 * 24 //1659716363  => delta 2,592,000
    // const endTimestamp2 = currentTimestamp + 30 * 60 * 60 * 24
    // const endTimestamp3 = currentTimestamp + 30 * 60 * 60 * 24 
    // const rewardPerSec1 = expandDecimals(8267, 12)
    // const rewardPerSec2 = expandDecimals(3858, 12)
    // const rewardPerSec3 = expandDecimals(3858, 12)
    // await sendTxn(eVela.setMinter(account, true), "set Minter");
    // await sendTxn(eVela.mint(account, expandDecimals(10000000, 18)), "mint eVELA"); // mint eVELA
    // const complexRewardPerSec1 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    // // const complexRewardPerSec1 = await contractAt('ComplexRewarderPerSec', '0x40befA12fACecF7C2287173CE0C46f9A14ad2572')
    // const complexRewardPerSec2 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    // // const complexRewardPerSec2 = await contractAt('ComplexRewarderPerSec', '0x6d1dC1807D40049cA787768Bd9833968df42F3D8')
    // const complexRewardPerSec3 = await deployContract("ComplexRewarderPerSec", [
    //     eVela.address,
    //     tokenFarm.address,
    //     isNative
    // ])
    // // const complexRewardPerSec3 = await contractAt('ComplexRewarderPerSec', '0x31888975C1516AF891e9Fc2Dc1b739d764Bce0e0')
    // const amount = String(ethers.constants.MaxUint256)
    // await eVela.setMinter(tokenFarm.address, true);
    // await sendTxn(eVela.approve(complexRewardPerSec1.address,  amount), "Approve eVELA"); // VLP approve
    // await sendTxn(eVela.approve(complexRewardPerSec2.address,  amount), "Approve eVELA"); // VELA approve
    // await sendTxn(eVela.approve(complexRewardPerSec3.address,  amount), "Approve eVELA"); // eVELA approve
    // await sendTxn(complexRewardPerSec1.add(pId1, currentTimestamp), "add pID1");
    // await sendTxn(complexRewardPerSec2.add(pId2, currentTimestamp), "add pID2");
    // await sendTxn(complexRewardPerSec3.add(pId3, currentTimestamp), "add pID3");
    // await sendTxn(complexRewardPerSec1.addRewardInfo(
    //     pId1,
    //     endTimestamp1,
    //     rewardPerSec1
    // ), "add RewardInfo 1");
    // await sendTxn(complexRewardPerSec2.addRewardInfo(
    //     pId2,
    //     endTimestamp2,
    //     rewardPerSec2
    // ), "add RewardInfo 2");
    // await sendTxn(complexRewardPerSec3.addRewardInfo(
    //     pId3,
    //     endTimestamp3,
    //     rewardPerSec3
    // ), "add RewardInfo 3");
    // await sendTxn(tokenFarm.add(
    //     vlp.address,
    //     [complexRewardPerSec1.address],
    //     true
    // ), "add Reward 1");
    // await sendTxn(tokenFarm.add(
    //     vela.address,
    //     [complexRewardPerSec2.address],
    //     true
    // ), "add Reward 2");
    // await sendTxn(tokenFarm.add(
    //     eVela.address,
    //     [complexRewardPerSec3.address],
    //     false
    // ), "add Reward 3");    
    // const levels = [
    //   expandDecimals('1000', 18),
    //   expandDecimals('5000', 18),
    //   expandDecimals('10000', 18),
    //   expandDecimals('25000', 18),
    //   expandDecimals('50000', 18),
    //   expandDecimals('100000', 18),
    //   expandDecimals('250000', 18),
    //   expandDecimals('500000', 18),
    //   expandDecimals('1000000', 18)
    // ]
    // const percents = [
    //   (100 - 2) * 100,
    //   (100 - 3) * 100,
    //   (100 - 5) * 100,
    //   (100 - 10) * 100,
    //   (100 - 15) * 100,
    //   (100 - 20) * 100,
    //   (100 - 30) * 100,
    //   (100 - 40) * 100,
    //   (100 - 50) * 100
    // ]
    // await sendTxn(tokenFarm.updateRewardTierInfo(levels, percents), "updateRewardTierInfo");
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  