// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {OrderInfo, OrderType} from "../structs.sol";

interface IVaultUtils {
    function emitClosePositionEvent(address _account, address _indexToken, bool _isLong, uint256 _posId) external;

    function emitDecreasePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _sizeDelta,
        uint256 _fee
    ) external;

    function emitIncreasePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _fee
    ) external;

    function emitLiquidatePositionEvent(address _account, address _indexToken, bool _isLong, uint256 _posId) external;

    function validateConfirmDelay(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view returns (bool);

    function validateDecreasePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view returns (bool);

    function validateLiquidation(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view returns (uint256, uint256);

    function validatePosData(
        bool _isLong,
        address _indexToken,
        OrderType _orderType,
        uint256[] memory _params,
        bool _raise
    ) external view returns (bool);

    function validateSizeCollateralAmount(uint256 _size, uint256 _collateral) external view;

    function validateTrailingStopInputData(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external view returns (bool);

    function validateTrailingStopPrice(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view returns (bool);

    function validateTrigger(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (uint8);
}
