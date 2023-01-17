For deploying perpetual smart contracts, Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat run --network network_name scripts/perpetuals_chainlink/deploy.js
npx hardhat run --network network_name scripts/perpetuals_chainlink/deployVaultPriceFeed.js
npx hardhat run --network network_name scripts/perpetuals_chainlink/deployVaultReader.js
npx hardhat help
```

# VELA-PERPETUAL

## Deployed Contracts

| Name        | Address                                    | Explorer                                                                       |
| ----------- | ------------------------------------------ | ------------------------------------------------------------------------------ |
| Vault       | 0xf7d42Cc4759fbF5aB6494A9DB9698941FD73A384 | https://testnet.arbiscan.io/address/0xf7d42Cc4759fbF5aB6494A9DB9698941FD73A384 |
| Router      | 0x493E0F9b08be730461E3c52eEA74BD221AAB96d9 | https://testnet.arbiscan.io/address/0x493E0F9b08be730461E3c52eEA74BD221AAB96d9 |
| VaultReader | 0xf07870Eab480f35ff21F3A261654b2915e676408 | https://testnet.arbiscan.io/address/0xf07870Eab480f35ff21F3A261654b2915e676408 |

### Initialize

OnlyOwner
Function

```
vault.initialize(address _router, address _priceFeed, uint256 _liquidationFeeUsd, uint256 _fundingRateFactor, uint256 _stableFundingRateFactor)
```

Example Input

```
('0x493E0F9b08be730461E3c52eEA74BD221AAB96d9', '0xC46800fF33c9104F61D389Fa18D82a5cC10a9002', toUsd(2), 100, 100)
```

Example Output

```

```

### setFees

OnlyOwner
Function

```
vault.setFees(uint256 _taxBabsisPoints, uint256 _stableTaxBasisPoints, uint256 _mintBurnFeeBasisPoints, uint256 _swapFeeBasisPoints, uint256 _stableSwapFeeBasisPoints, uint256 _marginFeeBasisPoints, uint256 _liquidationFeeUsd, uint256 _liquidationFeeUsd, bool _hasDynamicFees)
```

Example Input

```
(10, 5, 20, 20, 1, 10, toUsd(2), 24 * 60 * 60, true)
```

Example Output

```

```

### setTokenConfig

Function

```
vault.setTokenConfig(address _token, uint256 _tokenDecimals, uint256 _minProfitBps, bool _isStable, bool _isShortable)
```

Example Input

```
('0x0d0fDd6a1BF333796a19B3df1433333044Da14Dd', 18, 0, false, true) // ETH
('0x6Fb0674Bd389110230d6c01edAe1cD76165Be0a6', 6, 0, true, false) // USDT
```

Example Output

```

```

### setVaultUtils

Function

```
vault.setVaultUtils(IVaultUtils _vaultUtils)
```

Example Input

```
'0xC4374B3c23e4E2f411fD8a9586D0594fad46924f'
```

Example Output

```

```

### setMiner

Function

```
dlp.setMiner(address _minter, bool _isActive)
```

Example Input

```
(vault.address, true)
```

Example Output

```

```

### increasePosition

Function

```
router.increasePosition(address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _sizeDelta, bool _isLong)
```

Example Input

```
([usdt.address, eth.address], eth.address, expandDecimals(200, 6), toUsd(1200), true)
```

Example Output

```

```

### decreasePosition

Function

```
router.decreasePosition(address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong, address _receiver)
```

Example Input

```
([usdt.address, eth.address], eth.address, expandDecimals(200, 6), toUsd(1200), true)
```

Example Output

```

```
