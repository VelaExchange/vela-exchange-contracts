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
    const cryptoWallet = "0xffD8EDB88aDf79E275fc2399e84f40b4A4631533"
    const forexWallet = "0x76ba4883fed3Ef355554E8a8f495074eb1bed2B0"
    const tokens = [
        // {
        //   name: "btc",
        //   address: "0xa36F5ea837A1925252eB5dc5A3605C9C3ba840ec",
        //   admin: "0xffD8EDB88aDf79E275fc2399e84f40b4A4631533",
        //   decimals: 18,
        //   priceFeed: "0xE72ccE78A240d169521c01Ab8b9af80f785BBa6f",
        //   priceDecimals: 8,
        //   minProfitBps: 0,
        //   marginFeeBasisPoints: 80, // 0.08% 80 / 100000
        //   isStrictStable: false,
        //   isStable: false,
        //   isDeposit: false,
        //   isStaking: false,
        //   isShortable: true,
        //   maxLeverage: 30 * 10000
        // },
        {
          name: "eth",
          address: "0xC28FE92245aDC11bB63A0054D425f9B5C1680F17",
          admin: "0x2982e69Ff012778263D1352C26bE10D2bBd8d37f",
          decimals: 18,
          priceFeed: "0xa142374C993c434C424A63390118451e5b396b57",
          priceDecimals: 8,
          minProfitBps: 0,
          marginFeeBasisPoints: 80, // 0.08% 80 / 100000
          isStrictStable: false,
          isStable: false,
          isDeposit: false,
          isStaking: false,
          isShortable: true,
          maxLeverage: 30 * 10000
        },
        // {
        //   name: "gbp",
        //   address: "0x02311940c23D524Be839b958464B18084E127523",
        //   admin: "0x76ba4883fed3Ef355554E8a8f495074eb1bed2B0",
        //   decimals: 18,
        //   priceFeed: "0x1675E6462580F6cCBfaB781958554D5990A9bbfe",
        //   priceDecimals: 8,
        //   minProfitBps: 0,
        //   marginFeeBasisPoints: 8, // 0.008% 8 / 100000
        //   isStrictStable: true,
        //   isStable: false,
        //   isDeposit: false,
        //   isStaking: false,
        //   isShortable: false,
        //   maxLeverage: 100 * 10000
        // },
        {
          name: "eur",
          address: "0x3a25e25A0059cd08C974a8672250E22012Fb1260",
          admin: "0xB0203F6F66e3bEAA2087768c87147139C6510351",
          decimals: 18,
          priceFeed: "0xD8bdDd5dE2ad2333Fc813cf4CE10135cc863bb8c",
          priceDecimals: 8,
          minProfitBps: 0,
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          isStrictStable: true,
          isStable: false,
          isDeposit: false,
          isStaking: false,
          isShortable: false,
          maxLeverage: 100 * 10000
        },
        {
          name: "jpy",
          address: "0xBC35F65f3B511c06f123908d94B7d0bf97CbBE04",
          admin: "0xc55FEBfF08bc4ad0F656505Da9355A723A893bb8",
          decimals: 18,
          priceFeed: "0xEA1AE30DCfC984e5d78D43EECE27f31083163eb6",
          priceDecimals: 8,
          minProfitBps: 0,
          marginFeeBasisPoints: 8, // 0.008% 8 / 100000
          isStrictStable: true,
          isStable: false,
          isDeposit: false,
          isStaking: false,
          isShortable: false,
          maxLeverage: 100 * 10000
        },
        {
          name: "doge",
          address: "0x0D998BFfadF77E4C52701E65FA81A3dEF12B24DD",
          admin: "0xaAeA0735e12A940323f287f280D20EDA995742Fe",
          decimals: 18,
          priceFeed: "0xe0FB944d3f724A79A4A3F7f3aAbfcD2c85057C14",
          priceDecimals: 8,
          minProfitBps: 0,
          marginFeeBasisPoints: 80, // 0.08% 8 / 100000
          isStrictStable: true,
          isStable: false,
          isDeposit: false,
          isStaking: false,
          isShortable: false,
          maxLeverage: 30 * 10000
        },
    ];
    for (const token of tokens) {
        try {
            const priceFeed = await contractAt(
                "FastPriceFeed",
                token.priceFeed
              );
            const govAddress = await priceFeed.gov()
            console.log("govAddress: ", govAddress)
            await sendTxn(priceFeed.setAdmin(token.admin, true), `setAdmin`);
        } catch (e) {
            console.log("e : ", e)
        }
    }
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  