// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVaultUtils.sol";
import {Constants} from "../access/Constants.sol";
import {Position, Order, ConfirmInfo, OrderStatus} from "./structs.sol";

contract VaultUtils is IVaultUtils, Constants {
    IPositionVault private immutable positionVault;
    IPriceManager private priceManager;
    ISettingsManager private settingsManager;

    event ClosePosition(uint256 posId, int256 realisedPnl, uint256 markPrice, uint256 feeUsd);
    event DecreasePosition(
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        int256 realisedPnl,
        uint256[5] posData
    );
    event IncreasePosition(
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        uint256[5] posData
    );
    event LiquidatePosition(uint256 posId, int256 realisedPnl, uint256 markPrice, uint256 feeUsd);
    event SetDepositFee(address indexed token, uint256 indexed fee);

    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault");
        _;
    }

    constructor(address _positionVault, address _priceManager, address _settingsManager) {
        require(Address.isContract(_positionVault), "vault invalid");
        positionVault = IPositionVault(_positionVault);
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManager(_settingsManager);
    }

    function emitClosePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault {
        uint256 price = priceManager.getLastPrice(_indexToken);
        (Position memory position, , ) = positionVault.getPosition(_posId);
        uint256 migrateFeeUsd = settingsManager.collectMarginFees(_account, _indexToken, _isLong, position.size);
        emit ClosePosition(_posId, position.realisedPnl, price, migrateFeeUsd);
    }

    function emitDecreasePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _sizeDelta,
        uint256 _fee
    ) external override onlyVault {
        uint256 price = priceManager.getLastPrice(_indexToken);
        (Position memory position, , ) = positionVault.getPosition(_posId);
        uint256 _collateralDelta = (position.collateral * _sizeDelta) / position.size;
        emit DecreasePosition(
            _account,
            _indexToken,
            _isLong,
            _posId,
            position.realisedPnl,
            [_collateralDelta, _sizeDelta, position.averagePrice, price, _fee]
        );
    }

    function emitIncreasePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _fee
    ) external override onlyVault {
        uint256 price = priceManager.getLastPrice(_indexToken);
        (Position memory position, , ) = positionVault.getPosition(_posId);
        emit IncreasePosition(
            _account,
            _indexToken,
            _isLong,
            _posId,
            [_collateralDelta, _sizeDelta, position.averagePrice, price, _fee]
        );
    }

    function emitLiquidatePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _delta
    ) external override onlyVault {
        uint256 price = priceManager.getLastPrice(_indexToken);
        (Position memory position, , ) = positionVault.getPosition(_posId);
        uint256 migrateFeeUsd = settingsManager.collectMarginFees(_account, _indexToken, _isLong, position.size);
        emit LiquidatePosition(_posId, (-1) * int256(_delta), price, migrateFeeUsd);
    }

    function validateConfirmDelay(uint256 _posId, bool _raise) external view override returns (bool) {
        (, , ConfirmInfo memory confirm) = positionVault.getPosition(_posId);
        bool validateFlag;
        if (confirm.confirmDelayStatus) {
            if (
                block.timestamp >= (confirm.delayStartTime + settingsManager.delayDeltaTime()) &&
                confirm.pendingDelayCollateral > 0
            ) validateFlag = true;
            else validateFlag = false;
        } else validateFlag = false;
        if (_raise) {
            require(validateFlag, "order is still in delay pending");
        }
        return validateFlag;
    }

    function validateDecreasePosition(
        uint256 _posId,
        uint256 _price,
        bool _raise
    ) external view override returns (bool) {
        (Position memory position, , ) = positionVault.getPosition(_posId);
        bool validateFlag;
        (bool hasProfit, ) = settingsManager.getPnl(
            position.indexToken,
            position.size,
            position.averagePrice,
            _price,
            position.fundingIndex,
            position.isLong
        );
        if (hasProfit) {
            if (
                position.lastIncreasedTime > 0 &&
                position.lastIncreasedTime < block.timestamp - settingsManager.closeDeltaTime()
            ) {
                validateFlag = true;
            } else {
                if (
                    (position.isLong &&
                        _price * BASIS_POINTS_DIVISOR >=
                        (BASIS_POINTS_DIVISOR + settingsManager.priceMovementPercent()) * position.lastPrice) ||
                    (!position.isLong &&
                        _price * BASIS_POINTS_DIVISOR <=
                        (BASIS_POINTS_DIVISOR - settingsManager.priceMovementPercent()) * position.lastPrice)
                ) {
                    validateFlag = true;
                }
            }
        } else {
            validateFlag = true;
        }
        if (_raise) {
            require(validateFlag, "not allowed to close the position");
        }
        return validateFlag;
    }

    function validateLiquidation(uint256 _posId, bool _raise) external view override returns (uint256, uint256) {
        (Position memory position, , ) = positionVault.getPosition(_posId);
        uint256 price = priceManager.getLastPrice(position.indexToken);
        if (position.averagePrice > 0) {
            (bool hasProfit, uint256 delta) = settingsManager.getPnl(
                position.indexToken,
                position.size,
                position.averagePrice,
                price,
                position.fundingIndex,
                position.isLong
            );
            uint256 migrateFeeUsd = settingsManager.collectMarginFees(
                position.owner,
                position.indexToken,
                position.isLong,
                position.size
            );
            if (!hasProfit && position.collateral < delta) {
                if (_raise) {
                    revert("Vault: losses exceed collateral");
                }
                return (LIQUIDATE_FEE_EXCEED, position.collateral);
            }

            uint256 remainingCollateral = position.collateral;
            if (!hasProfit) {
                remainingCollateral = position.collateral - delta;
            } else {
                remainingCollateral = position.collateral + delta;
            }

            return _checkMaxThreshold(remainingCollateral, position.size, migrateFeeUsd, position.indexToken, _raise);
        } else {
            return (LIQUIDATE_NONE_EXCEED, 0);
        }
    }

    function validateMinLeverage(uint256 _size, uint256 _collateral) external pure override {
        require(_size >= _collateral, "leverage cannot be less than 1");
    }

    function validateMaxLeverage(address _indexToken, uint256 _size, uint256 _collateral) external view override {
        require(
            _size * 10 ** 4 <= _collateral * (priceManager.maxLeverage(_indexToken) + LEVERAGE_SLIPPAGE),
            "maxLeverage exceeded"
        );
    }

    function validateTrailingStopInputData(
        uint256 _posId,
        uint256[] memory _params
    ) external view override returns (bool) {
        (Position memory position, , ) = positionVault.getPosition(_posId);
        uint256 price = priceManager.getLastPrice(position.indexToken);
        require(_params[1] > 0 && _params[1] <= position.size, "trailing size should be smaller than position size");
        if (position.isLong) {
            require(_params[4] > 0 && _params[3] > 0 && _params[3] <= price, "invalid trailing data");
        } else {
            require(_params[4] > 0 && _params[3] > 0 && _params[3] >= price, "invalid trailing data");
        }
        if (_params[2] == TRAILING_STOP_TYPE_PERCENT) {
            require(_params[4] < BASIS_POINTS_DIVISOR, "percent cant exceed 100%");
        } else {
            if (position.isLong) {
                require(_params[4] < price, "step amount cant exceed price");
            }
        }
        return true;
    }

    function validateTrailingStopPrice(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view override returns (bool) {
        (, Order memory order, ) = positionVault.getPosition(_posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        uint256 stopPrice;
        if (_isLong) {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice + order.stepAmount;
            } else {
                stopPrice = (order.stpPrice * BASIS_POINTS_DIVISOR) / (BASIS_POINTS_DIVISOR - order.stepAmount);
            }
        } else {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice - order.stepAmount;
            } else {
                stopPrice = (order.stpPrice * BASIS_POINTS_DIVISOR) / (BASIS_POINTS_DIVISOR + order.stepAmount);
            }
        }
        bool flag;
        if (
            _isLong &&
            order.status == OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice <= price
        ) {
            flag = true;
        } else if (
            !_isLong &&
            order.status == OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice >= price
        ) {
            flag = true;
        }
        if (_raise) {
            require(flag, "price incorrect");
        }
        return flag;
    }

    function validateTrigger(address _indexToken, bool _isLong, uint256 _posId) external view override returns (uint8) {
        (, Order memory order, ) = positionVault.getPosition(_posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        uint8 statusFlag;
        if (order.status == OrderStatus.PENDING) {
            if (order.positionType == POSITION_LIMIT) {
                if (_isLong && order.lmtPrice >= price) statusFlag = ORDER_FILLED;
                else if (!_isLong && order.lmtPrice <= price) statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_STOP_MARKET) {
                if (_isLong && order.stpPrice <= price) statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice >= price) statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                if (_isLong && order.stpPrice <= price) statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice >= price) statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                if (_isLong && order.stpPrice >= price) statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice <= price) statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            }
        } else {
            statusFlag = ORDER_NOT_FILLED;
        }
        return statusFlag;
    }

    function _checkMaxThreshold(
        uint256 _collateral,
        uint256 _size,
        uint256 _marginFees,
        address _indexToken,
        bool _raise
    ) internal view returns (uint256, uint256) {
        if (_collateral < _marginFees) {
            if (_raise) {
                revert("Vault: fees exceed collateral");
            }
            // cap the fees to the remainingCollateral
            return (LIQUIDATE_FEE_EXCEED, _collateral);
        }

        if (_collateral < _marginFees + settingsManager.liquidationFeeUsd()) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (LIQUIDATE_FEE_EXCEED, _marginFees);
        }

        if (
            _collateral - (_marginFees + settingsManager.liquidationFeeUsd()) <
            (_size * (LIQUIDATE_THRESHOLD_DIVISOR - settingsManager.liquidateThreshold(_indexToken))) /
                LIQUIDATE_THRESHOLD_DIVISOR
        ) {
            if (_raise) {
                revert("Vault: maxThreshold exceeded");
            }
            return (LIQUIDATE_THRESHOLD_EXCEED, _marginFees + settingsManager.liquidationFeeUsd());
        }
        return (LIQUIDATE_NONE_EXCEED, _marginFees);
    }
}
