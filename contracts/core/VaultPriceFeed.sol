// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";

pragma solidity 0.8.9;

contract VaultPriceFeed is IVaultPriceFeed {
    address priceManager;
    mapping(address => bool) private isInitialized;
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;

    constructor() {
        priceManager = msg.sender;
    }

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

    function setPrice(address _token, uint256 _answer) public override {
        require(msg.sender == priceManager, "not manager");
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        // TODO: verify the price against pyth oracle before setting it, do not set if deviation > a certain percentage

        IPriceFeed(priceFeedAddress).setLatestAnswer(_answer);
    }

    function setPrices(address[] calldata _tokens, uint256[] calldata _answers) external override {
        require(_tokens.length == _answers.length, "VaultPriceFeed: length mismatch");

        for (uint256 i = 0; i < _tokens.length; ++i) {
            setPrice(_tokens[i], _answers[i]);
        }
    }
}
