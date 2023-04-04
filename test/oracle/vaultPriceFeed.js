/**
 * The test runner for Dexpools Perpetual contract
 */

const { expect, use } = require('chai')
const { solidity } = require('ethereum-waffle')
const { ethers, upgrades } = require('hardhat')

const { deployContract } = require('../../scripts/shared/helpers.js')
const { zeroAddress } = require('../../scripts/shared/utilities.js')
const { toChainlinkPrice } = require('../../scripts/shared/chainlink.js')

use(solidity)

describe('VaultPriceFeed', function () {
  const provider = waffle.provider
  const [wallet, user0, user1, user2, user3] = provider.getWallets()
  let btc
  let jpy
  let btcPriceFeed
  let jpyPriceFeed
  let vaultPriceFeed

  before(async function () {
    btc = await deployContract('MintableBaseToken', ['Bitcoin', 'BTC', 0])
    btcPriceFeed = await deployContract('FastPriceFeed', [])
    jpy = await deployContract('MintableBaseToken', ['Japanese Yan', 'JPY', 0])
    jpyPriceFeed = await deployContract('FastPriceFeed', [])
    vaultPriceFeed = await deployContract('VaultPriceFeed', [])
    //================= PriceFeed Prices Initialization ==================
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    const btcLastPrice = await btcPriceFeed.latestAnswer()
    expect(parseFloat(ethers.utils.formatUnits(btcLastPrice, 8))).eq(60000)
    await expect(vaultPriceFeed.setTokenConfig(zeroAddress, btcPriceFeed.address, 8)).to.be.revertedWith(
      'Address is wrong'
    )
    await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8)
    await expect(vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8)).to.be.revertedWith(
      'already initialized'
    )
  })

  it('getLastPrice', async () => {
    await expect(vaultPriceFeed.getLastPrice(zeroAddress)).to.be.revertedWith('VaultPriceFeed: invalid price feed')
    const lastPrice = await vaultPriceFeed.getLastPrice(btc.address)

    await vaultPriceFeed.setTokenConfig(jpy.address, jpyPriceFeed.address, 8)
    await expect(vaultPriceFeed.getLastPrice(jpy.address)).to.be.revertedWith('VaultPriceFeed: could not fetch price')
  })
})
