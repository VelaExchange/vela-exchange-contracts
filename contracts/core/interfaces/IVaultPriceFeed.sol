// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IVaultPriceFeed {
    function setTokenConfig(address _token, address _priceFeed, uint256 _priceDecimals) external;

    function getLastPrice(address _token) external view returns (uint256);

    function setPrice(address _token, uint256 _answer) external;

    function setPrices(address[] calldata _tokens, uint256[] calldata _answers) external;
}
