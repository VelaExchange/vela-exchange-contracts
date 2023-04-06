// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {Order, OrderType, OrderStatus } from "../structs.sol";

interface IOrderVault {
    function addTrailingStop(address _account, uint256 _posId, uint256[] memory _params) external;
    function cancelPendingOrder(address _account, uint256 _posId) external;
    function updateOrder(uint256 _posId, uint256 _positionType, uint256 _collateral, uint256 _size, OrderStatus _status) external;
    function cancelMarketOrder(uint256 _posId) external;
    function createNewOrder(uint256 _posId, uint256 _positionType, uint256[] memory _params, OrderStatus _status) external;
    function removeOrder(uint256 _posId) external;
    function getOrder(uint256 _posId) external view returns (Order memory);
}
