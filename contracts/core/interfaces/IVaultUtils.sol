// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

enum OrderType {
    MARKET,
    LIMIT,
    STOP,
    STOP_LIMIT,
    TRAILING_STOP
}

interface IVaultUtils {
    function emitClosePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external;

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
        uint256 _posId
    ) external;

    function distributeFee(
        address _account,
        address _refer,
        uint256 _fee
    ) external;

    function takeVUSDIn(
        address _account,
        address _refer,
        uint256 _amount,
        uint256 _fee
    ) external;

    function takeVUSDOut(
        address _account,
        address _refer,
        uint256 _fee,
        uint256 _usdOut
    ) external;

    function transferBounty(address _account, uint256 _amount) external;

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
        uint256[] memory _triggerPrices,
        bool _raise
    ) external view returns (bool);

    function validateSizeCollateralAmount(
        uint256 _size,
        uint256 _collateral
    ) external view;

    function validateTrailingStopInputData(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _triggerPrices
    ) external view returns (bool);

    function validateTrailingStopPrice(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (bool);

    function validateTrigger(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (uint8);
}
