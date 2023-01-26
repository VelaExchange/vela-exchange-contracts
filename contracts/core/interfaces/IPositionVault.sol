// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {Position, OrderInfo, OrderType, ConfirmInfo} from "../structs.sol";

interface IPositionVault {
    function addOrRemoveCollateral(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external;

    function addPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external;

    function addTrailingStop(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external;

    function cancelPendingOrder(address _account, address _indexToken, bool _isLong, uint256 _posId) external;

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external;

    function newPositionOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external;

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (Position memory, OrderInfo memory, ConfirmInfo memory);

    function poolAmounts(address _token, bool _isLong) external view returns (uint256);

    function reservedAmounts(address _token, bool _isLong) external view returns (uint256);
}
