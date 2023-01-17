const { deployContract, contractAt, sendTxn, writeTmpAddresses, readTmpAddresses } = require("../../shared/helpers")
const { expandDecimals } = require('../../shared/utilities');
const {ethers} = require("ethers");
const hre = require("hardhat");

async function main() {
    const owner = "0x0a52C4Cd73157bcfDD4a7c570106016db2749B05"
    const trustedFarwarder = "0xdc39780a90EDFc0bB3Bb2437486356e5625944B1"
    const vela = await deployContract('Vela', [trustedFarwarder])
    // Deploying Vela 0xa94b111F6957A6fa0ca4E06D295AD173030e7713 "0xdc39780a90EDFc0bB3Bb2437486356e5625944B1"
    // const vela = await contractAt('Vela', '0xfe1172d80071ca5A281e46A17a73F9b73C347410')
    await sendTxn(vela.mint(owner, expandDecimals('10000000', 18)), "mint Token")
    const balanceOf = await vela.balanceOf(owner)
    console.log("balanceOf : ", ethers.utils.formatUnits(balanceOf, 18))
    // Deploying Vela 0x22B1E7E25ce22251DAf656B7c85b0fcc16d8aF8D "0xdc39780a90EDFc0bB3Bb2437486356e5625944B1"
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
