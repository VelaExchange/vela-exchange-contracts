// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IPriceManager {
    function getLastPrice(address _token) external view returns (uint256);

    function maxLeverage(address _token) external view returns (uint256);

    function usdToToken(address _token, uint256 _usdAmount) external view returns (uint256);

    function tokenDecimals(address _token) external view returns (uint256);

    function tokenToUsd(address _token, uint256 _tokenAmount) external view returns (uint256);

    function setLatestPrices(address[] calldata _tokens, uint256[] calldata _answers) external;
}
