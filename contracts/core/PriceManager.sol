// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/IOperators.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import {Constants} from "../access/Constants.sol";

contract PriceManager is IPriceManager, Ownable, Constants {
    IOperators public immutable operators;

    mapping(address => uint256) public override maxLeverage; //  50 * 10000 50x
    mapping(address => uint256) public override tokenDecimals;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;

    constructor(address _operators) {
        require(Address.isContract(_operators), "operators invalid");
        operators = IOperators(_operators);
    }

    function setTokenConfig(address _token, uint256 _tokenDecimals, uint256 _maxLeverage, address _priceFeed, uint256 _priceDecimals) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(Address.isContract(_token), "Address is wrong");
        tokenDecimals[_token] = _tokenDecimals;
        require(_maxLeverage > MIN_LEVERAGE, "Max Leverage should be greater than Min Leverage");
        maxLeverage[_token] = _maxLeverage;
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        getLastPrice(_token);
    }

    function setMaxLeverage(address _token, uint256 _maxLeverage) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_maxLeverage > MIN_LEVERAGE, "Max Leverage should be greater than Min Leverage");
        maxLeverage[_token] = _maxLeverage;
    }

    function tokenToUsd(address _token, uint256 _tokenAmount) external view override returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getLastPrice(_token);
        uint256 decimals = tokenDecimals[_token];
        return (_tokenAmount * price) / (10 ** decimals);
    }

    function usdToToken(address _token, uint256 _usdAmount) external view override returns (uint256) {
        uint256 _price = getLastPrice(_token);
        if (_usdAmount == 0) {
            return 0;
        }
        uint256 decimals = tokenDecimals[_token];
        return (_usdAmount * (10 ** decimals)) / _price;
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

    function setPrice(address _token, uint256 _answer) public {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        // TODO: verify the price against pyth oracle before setting it, do not set if deviation > a certain percentage

        IPriceFeed(priceFeedAddress).setLatestAnswer(_answer);
    }

    function setLatestPrices(address[] calldata _tokens, uint256[] calldata _answers) external override {
        require(_tokens.length == _answers.length, "VaultPriceFeed: length mismatch");

        for (uint256 i = 0; i < _tokens.length; ++i) {
            setPrice(_tokens[i], _answers[i]);
        }
    }
}
