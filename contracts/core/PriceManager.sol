// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "./interfaces/IOperators.sol";
import {Constants} from "../access/Constants.sol";

contract PriceManager is IPriceManager, Ownable, Constants {
    address public immutable priceFeed;
    IOperators public immutable operators;

    mapping(address => bool) public isInitialized;

    mapping(address => uint256) public override maxLeverage; //  50 * 10000 50x
    mapping(address => uint256) public override tokenDecimals;

    constructor(address _priceFeed, address _operators) {
        require(Address.isContract(_operators), "operators invalid");
        operators = IOperators(_operators);
        priceFeed = _priceFeed;
    }

    function setTokenConfig(address _token, uint256 _tokenDecimals, uint256 _maxLeverage) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(Address.isContract(_token), "Address is wrong");
        require(!isInitialized[_token], "already initialized");
        tokenDecimals[_token] = _tokenDecimals;
        require(_maxLeverage > MIN_LEVERAGE, "Max Leverage should be greater than Min Leverage");
        maxLeverage[_token] = _maxLeverage;
        getLastPrice(_token);
        isInitialized[_token] = true;
    }

    function setMaxLeverage(address _token, uint256 _maxLeverage) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(isInitialized[_token] == true, "can only modify maxLeverage for existing tokens");
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
        return IVaultPriceFeed(priceFeed).getLastPrice(_token);
    }

    function setLatestPrices(address[] calldata _tokens, uint256[] calldata _answers) external override {
        return IVaultPriceFeed(priceFeed).setPrices(_tokens, _answers);
    }
}
