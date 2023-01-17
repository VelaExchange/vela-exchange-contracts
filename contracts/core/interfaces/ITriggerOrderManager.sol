// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITriggerOrderManager {
    enum TriggerStatus {
        OPEN,
        TRIGGERED,
        CANCELLED
    }
    struct TriggerOrder {
        bytes32 key;
        uint256[] slPrices;
        uint256[] slAmountPercents;
        uint256[] slTriggeredAmounts;
        uint256[] tpPrices;
        uint256[] tpAmountPercents;
        uint256[] tpTriggeredAmounts;
        TriggerStatus status;
    }

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
    ) external;

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view returns (bool);
}
