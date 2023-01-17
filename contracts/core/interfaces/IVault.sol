// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IVault {
    enum OrderStatus {
        NONE,
        PENDING,
        FILLED,
        CANCELED
    }
    struct OrderInfo {
        OrderStatus status;
        uint256 lmtPrice;
        uint256 pendingSize;
        uint256 pendingCollateral;
        uint256 positionType;
        uint256 stepAmount;
        uint256 stepType;
        uint256 stpPrice;
    }

    struct ConfirmInfo {
        bool confirmDelayStatus;
        uint256 pendingDelayCollateral;
        uint256 pendingDelaySize;
        uint256 delayStartTime;
    }

    struct Position {
        address owner;
        address refer;
        int256 realisedPnl;
        uint256 averagePrice;
        uint256 collateral;
        uint256 entryFundingRate;
        uint256 lastIncreasedTime;
        uint256 lastPrice;
        uint256 reserveAmount;
        uint256 size;
    }

    function decreasePosition(
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external;

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    )
        external
        view
        returns (Position memory, OrderInfo memory, ConfirmInfo memory);

    function poolAmounts(
        address _token,
        bool _isLong
    ) external view returns (uint256);

    function reservedAmounts(
        address _token,
        bool _isLong
    ) external view returns (uint256);
}
