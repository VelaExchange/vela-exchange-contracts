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

async function main() {
  //================== Deploy Process =========================
  const vaultPriceFeed = await deployContract("VaultPriceFeed", []);
  // Deploying VaultPriceFeed 0xF82D30B70405a3af72d10849d0D6E4554F2103F8
  const tokens = [
    {
      name: "btc",
      address: "0x61159e7Cb1F06476A217DaBDb5e03527aB69217A",
      decimals: 18,
      priceFeed: "0x6ED562a792214AC325F2682302bD690237c6c08E",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "eth",
      address: "0xA6E249FFB81cF6f28aB021C3Bd97620283C7335f",
      decimals: 18,
      priceFeed: "0xE5ad377d9EBfFaA3dc1424AC2C8452F161377215",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "gbp",
      address: "0xf34BF1185c190dab28ccF0Bb0BD22D312273D28b",
      decimals: 18,
      priceFeed: "0x8E6C73422032FcCAEb6ce2a4083EE389C40C08bE",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "eur",
      address: "0xb04ed6FFE5f6A7a19B47d5a78f43C694901E449b",
      decimals: 18,
      priceFeed: "0xb4f7Fde31cE1e03F233d0b4c18D4000138C1Bf33",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "jpy",
      address: "0x194a51Dce44a2f9Faea3480459365F53bD7702F7",
      decimals: 18,
      priceFeed: "0x707B8FE57cECCcCCd129f182285144C0D7437cD2",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "doge",
      address: "0xD1C8Cb78887E1254df137f3Ebb9FADa152679eE4",
      decimals: 18,
      priceFeed: "0xb0311A44E541F6d0b491989a494C279BE8ece2EE",
      priceDecimals: 8,
      isStrictStable: false,
    },
    {
      name: "usdc",
      address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
      decimals: 6,
      priceFeed: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
      priceDecimals: 8,
      isStrictStable: true,
    },
    {
      name: "usdt",
      address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
      decimals: 6,
      priceFeed: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
      priceDecimals: 8,
      isStrictStable: true,
    },
  ];
  for (const token of tokens) {
    await sendTxn(
      vaultPriceFeed.setTokenConfig(
        token.address,
        token.priceFeed,
        token.priceDecimals,
      ),
      `vaultPriceFeed.setTokenConfig(${token.name}) ${token.address}, ${token.priceFeed}`
    );
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
