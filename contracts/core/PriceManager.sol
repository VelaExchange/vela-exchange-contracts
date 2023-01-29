// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/IVaultPriceFeed.sol";
import {Constants} from "../access/Constants.sol";

contract PriceManager is IPriceManager, Ownable, Constants {
    address public immutable priceFeed;
    mapping(address => bool) public isInitialized;

    mapping(address => bool) public override isForex;
    mapping(address => uint256) public override maxLeverage; //  50 * 10000 50x
    mapping(address => uint256) public override tokenDecimals;

    constructor(address _priceFeed) {
        priceFeed = _priceFeed;
    }

    function setTokenConfig(address _token, uint256 _tokenDecimals, uint256 _maxLeverage, bool _isForex) external onlyOwner {
        require(Address.isContract(_token), "Address is wrong");
        require(!isInitialized[_token], "already initialized");
        tokenDecimals[_token] = _tokenDecimals;
        require(_maxLeverage > MIN_LEVERAGE, "Max Leverage should be greater than Min Leverage");
        maxLeverage[_token] = _maxLeverage;
        isForex[_token] = _isForex;
        getLastPrice(_token);
        isInitialized[_token] = true;
    }

    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta
    ) external view override returns (uint256) {
        (bool hasProfit, uint256 delta) = getDelta(_indexToken, _size, _averagePrice, _isLong);
        uint256 nextSize = _size + _sizeDelta;
        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? nextSize + delta : nextSize - delta;
        } else {
            divisor = hasProfit ? nextSize - delta : nextSize + delta;
        }
        return (_nextPrice * nextSize) / divisor;
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

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong
    ) public view override returns (bool, uint256) {
        require(_averagePrice > 0, "average price should be greater than zero");
        uint256 price = getLastPrice(_indexToken);
        uint256 priceDelta = _averagePrice >= price ? _averagePrice - price : price - _averagePrice;
        uint256 delta = (_size * priceDelta) / _averagePrice;

        bool hasProfit;

        if (_isLong) {
            hasProfit = price >= _averagePrice;
        } else {
            hasProfit = _averagePrice >= price;
        }
        return (hasProfit, delta);
    }

    function getLastPrice(address _token) public view override returns (uint256) {
        return IVaultPriceFeed(priceFeed).getLastPrice(_token);
    }
}
