// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {Order, OrderType} from "../structs.sol";

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

    function emitLiquidatePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _delta
    ) external;

    function validateDecreasePosition(uint256 _posId, uint256 _price, bool _raise) external view returns (bool);

    function validateLiquidation(uint256 _posId, bool _raise) external view returns (uint256, uint256);

    function validateMaxLeverage(address _indexToken, uint256 _size, uint256 _collateral) external view;

    function validateMinLeverage(uint256 _size, uint256 _collateral) external view;

    function validateTrailingStopInputData(uint256 _posId, uint256[] memory _params) external view returns (bool);

    function validateTrailingStopPrice(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view returns (bool);

    function validateTrigger(address _indexToken, bool _isLong, uint256 _posId) external view returns (uint8);
}
