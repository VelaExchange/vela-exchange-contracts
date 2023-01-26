// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IPriceFeed {
    function aggregator() external view returns (address);

    function description() external view returns (string memory);

    function getRoundData(uint80 roundId) external view returns (uint80, uint256, uint256, uint256, uint80);

    function latestAnswer() external view returns (uint256);

    function latestRound() external view returns (uint80);
}
