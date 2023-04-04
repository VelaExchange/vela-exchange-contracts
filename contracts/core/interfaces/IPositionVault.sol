// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {Position, Order, OrderType, ConfirmInfo} from "../structs.sol";

interface IPositionVault {
    function addOrRemoveCollateral(address _account, uint256 _posId, bool isPlus, uint256 _amount) external;

    function addPosition(
        address _account,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptedPrice
    ) external;

    function addTrailingStop(address _account, uint256 _posId, uint256[] memory _params) external;

    function cancelPendingOrder(address _account, uint256 _posId) external;

    function decreasePosition(address _account, uint256 _sizeDelta, uint256 _posId) external;

    function newPositionOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external;

    function getPosition(uint256 _posId) external view returns (Position memory, Order memory, ConfirmInfo memory);

    function getVaultUSDBalance() external view returns (uint256);
}
