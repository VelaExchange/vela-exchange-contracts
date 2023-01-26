// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITriggerOrderManager {
    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external returns (bool, uint256);

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view returns (bool);
}
