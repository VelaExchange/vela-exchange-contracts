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
    // const doge_fastPriceFeed = await deployContract('FastPriceFeed', [])
    const btc_fastPriceFeed = await contractAt('FastPriceFeed', '0x6ED562a792214AC325F2682302bD690237c6c08E')
    const eth_fastPriceFeed = await contractAt('FastPriceFeed', '0xE5ad377d9EBfFaA3dc1424AC2C8452F161377215')
    const gbp_fastPriceFeed = await contractAt('FastPriceFeed', '0x8E6C73422032FcCAEb6ce2a4083EE389C40C08bE')
    const euro_fastPriceFeed = await contractAt('FastPriceFeed', '0xb4f7Fde31cE1e03F233d0b4c18D4000138C1Bf33')
    const jpy_fastPriceFeed = await contractAt('FastPriceFeed', '0x707B8FE57cECCcCCd129f182285144C0D7437cD2')
    const doge_fastPriceFeed = await contractAt('FastPriceFeed', '0xb0311A44E541F6d0b491989a494C279BE8ece2EE')
    const usdc_fastPriceFeed = await contractAt('FastPriceFeed', '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3')
    const usdt_fastPriceFeed = await contractAt('FastPriceFeed', '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7')
    // Deploying BTC/USD FastPriceFeed 0x6ED562a792214AC325F2682302bD690237c6c08E
    // Deploying ETH/USD FastPriceFeed 0xE5ad377d9EBfFaA3dc1424AC2C8452F161377215
    // Deploying GBP/USD FastPriceFeed 0x8E6C73422032FcCAEb6ce2a4083EE389C40C08bE
    // Deploying EUR/USD FastPriceFeed 0xb4f7Fde31cE1e03F233d0b4c18D4000138C1Bf33
    // Deploying JPY/USD FastPriceFeed 0x707B8FE57cECCcCCd129f182285144C0D7437cD2
    // Deploying DOGE/USD FastPriceFeed 0xb0311A44E541F6d0b491989a494C279BE8ece2EE
    const btc_description = await btc_fastPriceFeed.description()
    const eth_description = await eth_fastPriceFeed.description()
    const gbp_description = await gbp_fastPriceFeed.description()
    const euro_description = await euro_fastPriceFeed.description()
    const jpy_description = await jpy_fastPriceFeed.description()
    const doge_description = await doge_fastPriceFeed.description()
    console.log("BTC Description : ", btc_description)
    console.log("ETH Description : ", eth_description)
    console.log("GBP Description : ", gbp_description)
    console.log("EURO Description : ", euro_description)
    console.log("JPY Description : ", jpy_description)
    console.log("DOGE Description : ", doge_description)
    // await sendTxn(btc_fastPriceFeed.setDescription("BTC/USD"), "set BTC PriceFeed Description")
    // await sendTxn(eth_fastPriceFeed.setDescription("ETH/USD"), "set ETH PriceFeed Description")
    // await sendTxn(gbp_fastPriceFeed.setDescription("GBP/USD"), "set GBP PriceFeed Description")
    // await sendTxn(euro_fastPriceFeed.setDescription("EUR/USD"), "set EUR PriceFeed Description")
    // await sendTxn(jpy_fastPriceFeed.setDescription("JPY/USD"), "set JPY PriceFeed Description")
    // await sendTxn(doge_fastPriceFeed.setDescription("DOGE/USD"), "set DOGE PriceFeed Description")
    // await sendTxn(usdjpy_fastPriceFeed.setDescription("USD/JPY"), "set USD/JPY PriceFeed Description")
    const btc_price = 1673321800000
    const eth_price = 121748000000
    const gbp_price = 119988860
    const eur_price = 105681000
    const jpy_price = 765200
    const doge_price = 7164000
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
    await sendTxn(
      btc_fastPriceFeed.setLatestAnswer(btc_price),
      "BTC SetLatestAnswer"
    );
    await sendTxn(
      eth_fastPriceFeed.setLatestAnswer(eth_price),
      "ETH SetLatestAnswer"
    );  
    await sendTxn(
      gbp_fastPriceFeed.setLatestAnswer(gbp_price),
      "GBP SetLatestAnswer"
    );
    await sendTxn(
      euro_fastPriceFeed.setLatestAnswer(eur_price),
      "EUR SetLatestAnswer"
    );  
    await sendTxn(
      jpy_fastPriceFeed.setLatestAnswer(jpy_price),
      "JPY SetLatestAnswer"
    ); 
    await sendTxn(
      doge_fastPriceFeed.setLatestAnswer(doge_price),
      "DOGE SetLatestAnswer"
    ); 
    // await sendTxn(
    //   usdc_marketcap_fastPriceFeed.setLatestAnswer(usdc_marketcap),
    //   "USDC SetLatestAnswer"
    // );
    // await sendTxn(
    //   usdt_marketcap_fastPriceFeed.setLatestAnswer(usdt_marketcap),
    //   "USDC SetLatestAnswer"
    // );
      // await sendTxn(
      //   vlp_fastPriceFeed.setLatestAnswer(vlp_price),
      //   "VLP SetLatestAnswer"
      // );  
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  