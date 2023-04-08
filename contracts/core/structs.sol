// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

enum OrderType {
    MARKET,
    LIMIT,
    STOP,
    STOP_LIMIT,
    TRAILING_STOP
}

enum OrderStatus {
    NONE,
    PENDING,
    FILLED,
    CANCELED
}

enum PositionStatus {
    NONE,
    PENDING,
    FILLED,
    CANCELED
}

enum TriggerStatus {
    NONE,
    OPEN,
    TRIGGERED,
    CANCELLED
}

struct Order {
    OrderStatus status;
    uint256 lmtPrice;
    uint256 size;
    uint256 collateral;
    uint256 positionType;
    uint256 stepAmount;
    uint256 stepType;
    uint256 stpPrice;
    uint256 timestamp;
}

struct AddPositionOrder {
    uint256 collateral;
    uint256 size;
    uint256 acceptedPrice;
    uint256 timestamp;
}

struct DecreasePositionOrder {
    uint256 size;
    uint256 acceptedPrice;
    uint256 timestamp;
}

struct Position {
    address owner;
    address refer;
    address indexToken;
    bool isLong;
    int256 realisedPnl;
    uint256 averagePrice;
    uint256 collateral;
    int256 fundingIndex;
    uint256 lastIncreasedTime;
    uint256 lastPrice;
    uint256 size;
    uint256 accruedBorrowFee;
}

struct TriggerInfo {
    bool isTP;
    uint256 amountPercent;
    uint256 createdAt;
    uint256 price;
    uint256 triggeredAmount;
    uint256 triggeredAt;
    TriggerStatus status;
}

struct PositionTrigger {
    TriggerInfo[] triggers;
    uint256 triggerCount;
    TriggerStatus status;
}
