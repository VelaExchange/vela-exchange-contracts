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
  // const btc_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const eth_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const gbp_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const euro_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const jpy_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const ape_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const doge_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const usdjpy_fastPriceFeed = await deployContract('FastPriceFeed', [])
     const vlp_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const usdc_marketcap_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const usdt_marketcap_fastPriceFeed = await deployContract('FastPriceFeed', [])
  // const usdc_marketcap_fastPriceFeed = await contractAt(
  //   "FastPriceFeed",
  //   "0x4aD41D7DdE9fefA425a686823c1Df5Caf7077794"
  // );
  // const usdt_marketcap_fastPriceFeed = await contractAt(
  //   "FastPriceFeed",
  //   "0x5aE8407F06d26d7aD864dd0A35682326161035D3"
  // );
  // Deploying BTC/USD FastPriceFeed 0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f
  // Deploying ETH/USD FastPriceFeed 0xa142374C993c434C424A63390118451e5b396b57
  // Deploying GBP/USD FastPriceFeed 0x1675E6462580F6cCBfaB781958554D5990A9bbfe
  // Deploying EUR/USD FastPriceFeed 0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c
  // Deploying JPY/USD FastPriceFeed 0xEA1AE30DCfC984e5d78D43EECE27f31083163eb6
  // Deploying APE/USD FastPriceFeed 0xA9cFD4E4E758e79EBD440081bA1971f32387Fc4B
  // Deploying DOGE/USD FastPriceFeed 0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14
  // Deploying USD/JPY FastPriceFeed 0x91B2B5925Aeb2250e1176C068fD23d08041eF73e
  // Deploying VLP/USD FastPriceFeed 0x8045E2C156A35a110DAc2D220a63fe749cD5CFDd
  // await sendTxn(btc_fastPriceFeed.setDescription("BTC/USD"), "set BTC PriceFeed Description")
  // await sendTxn(eth_fastPriceFeed.setDescription("ETH/USD"), "set ETH PriceFeed Description")
  // await sendTxn(gbp_fastPriceFeed.setDescription("GBP/USD"), "set GBP PriceFeed Description")
  // await sendTxn(euro_fastPriceFeed.setDescription("EUR/USD"), "set EUR PriceFeed Description")
  // await sendTxn(jpy_fastPriceFeed.setDescription("JPY/USD"), "set JPY PriceFeed Description")
  // await sendTxn(ape_fastPriceFeed.setDescription("APE/USD"), "set APE PriceFeed Description")
  // await sendTxn(doge_fastPriceFeed.setDescription("DOGE/USD"), "set DOGE PriceFeed Description")
  // await sendTxn(usdjpy_fastPriceFeed.setDescription("USD/JPY"), "set USD/JPY PriceFeed Description")
  await sendTxn(vlp_fastPriceFeed.setDescription("VLP/USD"), "set VLP/USD PriceFeed Description")
  // await sendTxn(usdc_marketcap_fastPriceFeed.setDescription("USDC MarketCap"), "USDC MarketCap")
  // await sendTxn(usdt_marketcap_fastPriceFeed.setDescription("USDC MarketCap"), "USDT MarketCap")
  // Deploying FastPriceFeed 0x4aD41D7DdE9fefA425a686823c1Df5Caf7077794 USDC MarketCap
  // Deploying FastPriceFeed 0x5aE8407F06d26d7aD864dd0A35682326161035D3 USDT MarketCap
  // const doge_fastPriceFeed = await contractAt('FastPriceFeed', '0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14')
  // const btcPriceFeed = await contractAt('FastPriceFeed', '0x6550bc2301936011c1334555e62A87705A81C12C')
  // const aggregator = await btcPriceFeed.aggregator()
  // console.log("aggregator : ", aggregator)
  // const description = await usdjpy_fastPriceFeed.description()
  // console.log("description : ", description)
  // const btcAggPriceFeed = await contractAt('FastPriceFeed', aggregator)
  // const latestAnswer = await btcAggPriceFeed.latestAnswer()
  // console.log("latestAnswer : ", latestAnswer.toString())
  // const usdc_marketcap = 43857846922;
  // const usdt_marketcap = 68473503493;
  // const doge_price = 8275900
  // const btc_price = 1622100000000
  // const eth_price = 113400000000
  const vlp_price = 240000000
  // await sendTxn(
  //   btc_fastPriceFeed.setLatestAnswer(btc_price),
  //   "BTC SetLatestAnswer"
  // );
  // await sendTxn(
  //   eth_fastPriceFeed.setLatestAnswer(eth_price),
  //   "ETH SetLatestAnswer"
  // );  
  // await sendTxn(
  //   doge_fastPriceFeed.setLatestAnswer(doge_price),
  //   "DOGE SetLatestAnswer"
  // ); 
  // await sendTxn(
  //   usdc_marketcap_fastPriceFeed.setLatestAnswer(usdc_marketcap),
  //   "USDC SetLatestAnswer"
  // );
  // await sendTxn(
  //   usdt_marketcap_fastPriceFeed.setLatestAnswer(usdt_marketcap),
  //   "USDC SetLatestAnswer"
  // );
    await sendTxn(
      vlp_fastPriceFeed.setLatestAnswer(vlp_price),
      "VLP SetLatestAnswer"
    );  
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
