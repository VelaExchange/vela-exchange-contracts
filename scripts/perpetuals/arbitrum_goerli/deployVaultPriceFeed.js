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
  // const vaultPriceFeed = await deployContract("VaultPriceFeed", []);
  const vaultPriceFeed = await contractAt(
    "VaultPriceFeed",
    "0xb665E8E6F2031b143458866a940ec0E8BF58c34A"
  );
  const tokens = [
    // {
    //   name: "btc",
    //   address: "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec",
    //   decimals: 18,
    //   priceFeed: "0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "eth",
    //   address: "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17",
    //   decimals: 18,
    //   priceFeed: "0xa142374C993c434C424A63390118451e5b396b57",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "dai",
    //   address: "0x302321b51FEa7eeca55625b4B78D836623A43CFA",
    //   decimals: 18,
    //   priceFeed: "0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1",
    //   priceDecimals: 8,
    //   isStrictStable: true,
    // },
    // {
    //   name: "usdc",
    //   address: "0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b",
    //   decimals: 6,
    //   priceFeed: "0x1692Bdd32F31b831caAc1b0c9fAF68613682813b",
    //   priceDecimals: 8,
    //   isStrictStable: true,
    // },
    // {
    //   name: "usdt",
    //   address: "0x1d51eEcc9b82b63cb5630adB44a195200e25c123",
    //   decimals: 6,
    //   priceFeed: "0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E",
    //   priceDecimals: 8,
    //   isStrictStable: true,
    // },
    // {
    //   name: "gbp",
    //   address: "0x02311940c23D524Be839b958464B18084E127523",
    //   decimals: 18,
    //   priceFeed: "0x1675E6462580F6cCBfaB781958554D5990A9bbfe",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "eur",
    //   address: "0x3a25e25A0059cd08C974a8672250E22012Fb1260",
    //   decimals: 18,
    //   priceFeed: "0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "jpy",
    //   address: "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04",
    //   decimals: 18,
    //   priceFeed: "0xEA1AE30DCfC984e5d78D43EECE27f31083163eb6",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "ape",
    //   address: "0x0E5DFdC9a2C96DFb234eB7b55629A789aa9dedf8",
    //   decimals: 18,
    //   priceFeed: "0xA9cFD4E4E758e79EBD440081bA1971f32387Fc4B",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    // {
    //   name: "doge",
    //   address: "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD",
    //   decimals: 18,
    //   priceFeed: "0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14",
    //   priceDecimals: 8,
    //   isStrictStable: false,
    // },
    {
      name: "vlp",
      address: "0x020F88c59222241378B23325fdCFEc4ea3fF5199",
      decimals: 18,
      priceFeed: "0x8045E2C156A35a110DAc2D220a63fe749cD5CFDd",
      priceDecimals: 8,
      isStrictStable: false,
    },
  ];
  for (const token of tokens) {
    await sendTxn(
      vaultPriceFeed.setTokenConfig(
        token.address,
        token.priceFeed,
        token.priceDecimals
      ),
      `vaultPriceFeed.setTokenConfig(${token.name}) ${token.address}, ${token.priceFeed}`
    );
  }
  // Deploying VaultPriceFeed 0xb665E8E6F2031b143458866a940ec0E8BF58c34A
  // Sending vaultPriceFeed.setTokenConfig(btc) 0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec, 0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f...
  // Sending vaultPriceFeed.setTokenConfig(eth) 0xC28FE92245aDC11bB63A0054D425f9B5C1680F17, 0xa142374C993c434C424A63390118451e5b396b57...
  // Sending vaultPriceFeed.setTokenConfig(dai) 0x302321b51FEa7eeca55625b4B78D836623A43CFA, 0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1...
  // Sending vaultPriceFeed.setTokenConfig(usdc) 0x93F2394ceA60fa9E2E9AC215cd8ba04c30ed103b, 0x1692Bdd32F31b831caAc1b0c9fAF68613682813b...
  // Sending vaultPriceFeed.setTokenConfig(usdt) 0x1d51eEcc9b82b63cb5630adB44a195200e25c123, 0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E...
  // Sending vaultPriceFeed.setTokenConfig(gbp) 0x02311940c23D524Be839b958464B18084E127523, 0x1675E6462580F6cCBfaB781958554D5990A9bbfe...
  // Sending vaultPriceFeed.setTokenConfig(eur) 0x3a25e25A0059cd08C974a8672250E22012Fb1260, 0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c...
  // Sending vaultPriceFeed.setTokenConfig(jpy) 0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04, 0xEA1AE30DCfC984e5d78D43EECE27f31083163eb6...
  // Sending vaultPriceFeed.setTokenConfig(ape) 0x0E5DFdC9a2C96DFb234eB7b55629A789aa9dedf8, 0xA9cFD4E4E758e79EBD440081bA1971f32387Fc4B...
  // Sending vaultPriceFeed.setTokenConfig(doge) 0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD, 0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14...
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
