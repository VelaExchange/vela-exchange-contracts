// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITriggerOrderManager {
    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external returns (bool, uint256);

    function updateTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpAmountPercents,
        uint256[] memory _slAmountPercents,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external payable;

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view returns (bool);
}
