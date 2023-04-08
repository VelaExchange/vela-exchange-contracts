// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {Order, OrderType, OrderStatus, AddPositionOrder, DecreasePositionOrder} from "../structs.sol";

interface IOrderVault {
    function addTrailingStop(address _account, uint256 _posId, uint256[] memory _params) external;

    function cancelPendingOrder(address _account, uint256 _posId) external;

    function updateOrder(
        uint256 _posId,
        uint256 _positionType,
        uint256 _collateral,
        uint256 _size,
        OrderStatus _status
    ) external;

    function cancelMarketOrder(uint256 _posId) external;

    function createNewOrder(
        uint256 _posId,
        uint256 _positionType,
        uint256[] memory _params,
        OrderStatus _status
    ) external;

    function createAddPositionOrder(
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptedPrice
    ) external;

    function createDecreasePositionOrder(uint256 _posId, uint256 _sizeDelta, uint256 _acceptedPrice) external;

    function deleteAddPositionOrder(uint256 _posId) external;

    function deleteDecreasePositionOrder(uint256 _posId) external;

    function removeOrder(uint256 _posId) external;

    function getOrder(uint256 _posId) external view returns (Order memory);

    function getAddPositionOrder(uint256 _posId) external view returns (AddPositionOrder memory);

    function getDecreasePositionOrder(uint256 _posId) external view returns (DecreasePositionOrder memory);

    function executeTriggerOrders(
        address _token,
        bool _isLong,
        uint256 _posId
    ) external returns (bool, uint256, uint256);

    function validateTPSLTriggers(address _token, bool _isLong, uint256 _posId) external view returns (bool);
}
