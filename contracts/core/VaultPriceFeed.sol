// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";

pragma solidity 0.8.9;

contract VaultPriceFeed is IVaultPriceFeed {
    mapping(address => bool) private isInitialized;
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;

    constructor() {}

    function setTokenConfig(address _token, address _priceFeed, uint256 _priceDecimals) external override {
        require(Address.isContract(_token), "Address is wrong");
        require(!isInitialized[_token], "already initialized");
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        isInitialized[_token] = true;
    }

    function getLastPrice(address _token) public view override returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = priceFeed.latestAnswer();
        require(price > 0, "VaultPriceFeed: could not fetch price");
        uint256 _priceDecimals = priceDecimals[_token];
        return (price * PRICE_PRECISION) / (10 ** _priceDecimals);
    }
}
