// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IPriceManager.sol";
import "../staking/interfaces/ITokenFarm.sol";
import "../access/Governable.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IVUSDC.sol";

contract VaultUtils is IVaultUtils, Governable, Constants {
    address public immutable vUSDC;
    IPriceManager public priceManager;
    ISettingsManager settingsManager;
    ITokenFarm public immutable tokenFarm;
    IVault public immutable vault;

    event ClosePosition(
        bytes32 key,
        int256 realisedPnl,
        uint256 markPrice,
        uint256 feeUsd
    );
    event DecreasePosition(
        bytes32 key,
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        int256 realisedPnl,
        uint256[7] posData
    );
    event IncreasePosition(
        bytes32 key,
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        uint256[7] posData
    );
    event LiquidatePosition(
        bytes32 key,
        int256 realisedPnl,
        uint256 markPrice,
        uint256 feeUsd
    );
    event SetDepositFee(uint256 indexed fee);
    event TakeVUSDIn(
        address indexed account,
        address indexed refer,
        uint256 amount,
        uint256 fee
    );
    event TakeVUSDOut(
        address indexed account,
        address indexed refer,
        uint256 amount,
        uint256 fee
    );
    event TransferBounty(address indexed account, uint256 amount);
    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault has access");
        _;
    }

    constructor(
        address _vault,
        address _vUSDC,
        address _tokenFarm,
        address _priceManager,
        address _settingsManager
    ) {
        require(Address.isContract(_vault), "vault address is invalid");
        require(Address.isContract(_vUSDC), "vUSD address is invalid");
        require(Address.isContract(_tokenFarm), "tokenFarm address is invalid");
        tokenFarm = ITokenFarm(_tokenFarm);
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManager(_settingsManager);
        vault = IVault(_vault);
        vUSDC = _vUSDC;
    }

    function distributeFee(
        address _account,
        address _refer,
        uint256 _fee
    ) external override onlyVault {
        _mintOrBurnVUSDForVault(true, _fee, _fee, _refer);
        emit TakeVUSDIn(_account, _refer, 0, _fee);
    }

    function emitClosePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 feeUsd = settingsManager.getPositionFee(
            _indexToken,
            _isLong,
            position.size
        );
        feeUsd += settingsManager.getFundingFee(
            _indexToken,
            _isLong,
            position.size,
            position.entryFundingRate
        );
        uint256 migrateFeeUsd = (feeUsd *
            tokenFarm.getTier(STAKING_PID_FOR_CHARGE_FEE, _account)) /
            BASIS_POINTS_DIVISOR;
        emit ClosePosition(key, position.realisedPnl, price, migrateFeeUsd);
    }

    function emitDecreasePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _sizeDelta,
        uint256 _fee
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 _collateralDelta = (position.collateral * _sizeDelta) /
            position.size;
        emit DecreasePosition(
            key,
            _account,
            _indexToken,
            _isLong,
            _posId,
            position.realisedPnl,
            [
                _collateralDelta,
                _sizeDelta,
                position.reserveAmount,
                position.entryFundingRate,
                position.averagePrice,
                price,
                _fee
            ]
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
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        emit IncreasePosition(
            key,
            _account,
            _indexToken,
            _isLong,
            _posId,
            [
                _collateralDelta,
                _sizeDelta,
                position.reserveAmount,
                position.entryFundingRate,
                position.averagePrice,
                price,
                _fee
            ]
        );
    }

    function emitLiquidatePositionEvent(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        uint256 price = priceManager.getLastPrice(_indexToken);
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 feeUsd = settingsManager.getPositionFee(
            _indexToken,
            _isLong,
            position.size
        );
        feeUsd += settingsManager.getFundingFee(
            _indexToken,
            _isLong,
            position.size,
            position.entryFundingRate
        );
        uint256 migrateFeeUsd = (feeUsd *
            tokenFarm.getTier(STAKING_PID_FOR_CHARGE_FEE, _account)) /
            BASIS_POINTS_DIVISOR;
        emit LiquidatePosition(key, position.realisedPnl, price, migrateFeeUsd);
    }

    function takeVUSDIn(
        address _account,
        address _refer,
        uint256 _amount,
        uint256 _fee
    ) external override onlyVault {
        IVUSDC(vUSDC).burn(_account, _amount);
        _mintOrBurnVUSDForVault(true, _amount, _fee, _refer);
        emit TakeVUSDIn(_account, _refer, _amount, _fee);
    }

    function takeVUSDOut(
        address _account,
        address _refer,
        uint256 _fee,
        uint256 _usdOut
    ) external override onlyVault {
        uint256 _usdOutAfterFee = _usdOut - _fee;
        IVUSDC(vUSDC).mint(_account, _usdOutAfterFee);
        _mintOrBurnVUSDForVault(false, _usdOutAfterFee, _fee, _refer);
        emit TakeVUSDOut(_account, _refer, _usdOut, _fee);
    }

    function transferBounty(
        address _account,
        uint256 _amount
    ) external override onlyVault {
        IVUSDC(vUSDC).burn(address(vault), _amount);
        IVUSDC(vUSDC).mint(_account, _amount);
        emit TransferBounty(_account, _amount);
    }

    function validateConfirmDelay(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view override returns (bool) {
        (, , IVault.ConfirmInfo memory confirm) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        bool validateFlag;
        if (confirm.confirmDelayStatus) {
            if (
                block.timestamp >=
                (confirm.delayStartTime + settingsManager.delayDeltaTime()) &&
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
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view override returns (bool) {
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        bool validateFlag;
        (bool hasProfit, ) = priceManager.getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong
        );
        if (hasProfit) {
            if (
                position.lastIncreasedTime > 0 &&
                position.lastIncreasedTime <
                block.timestamp - settingsManager.closeDeltaTime()
            ) {
                validateFlag = true;
            } else {
                uint256 price = priceManager.getLastPrice(_indexToken);
                if (
                    (_isLong &&
                        price * BASIS_POINTS_DIVISOR >=
                        (BASIS_POINTS_DIVISOR +
                            settingsManager.priceMovementPercent()) *
                            position.lastPrice) ||
                    (!_isLong &&
                        price * BASIS_POINTS_DIVISOR <=
                        (BASIS_POINTS_DIVISOR -
                            settingsManager.priceMovementPercent()) *
                            position.lastPrice)
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

    function validateLiquidation(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) external view override returns (uint256, uint256) {
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        if (position.averagePrice > 0) {
            (bool hasProfit, uint256 delta) = priceManager.getDelta(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong
            );
            uint256 marginFees = settingsManager.getPositionFee(
                _indexToken,
                _isLong,
                position.size
            );
            marginFees += settingsManager.getFundingFee(
                _indexToken,
                _isLong,
                position.size,
                position.entryFundingRate
            );
            uint256 migrateFeeUsd = (marginFees *
                tokenFarm.getTier(STAKING_PID_FOR_CHARGE_FEE, _account)) /
                BASIS_POINTS_DIVISOR;
            if (!hasProfit && position.collateral < delta) {
                if (_raise) {
                    revert("Vault: losses exceed collateral");
                }
                return (LIQUIDATE_FEE_EXCEED, migrateFeeUsd);
            }

            uint256 remainingCollateral = position.collateral;
            if (!hasProfit) {
                remainingCollateral = position.collateral - delta;
            }

            if (
                position.collateral * priceManager.maxLeverage(_indexToken) <
                position.size * MIN_LEVERAGE
            ) {
                if (_raise) {
                    revert("Vault: maxLeverage exceeded");
                }
            }
            return
                _checkMaxThreshold(
                    remainingCollateral,
                    position.size,
                    migrateFeeUsd,
                    _indexToken,
                    _raise
                );
        } else {
            return (LIQUIDATE_NONE_EXCEED, 0);
        }
    }

    function validatePosData(
        bool _isLong,
        address _indexToken,
        OrderType _orderType,
        uint256[] memory _triggerPrices,
        bool _raise
    ) external view override returns (bool) {
        bool orderTypeFlag;
        if (_triggerPrices[3] > 0) {
            if (_isLong) {
                if (_orderType == OrderType.LIMIT && _triggerPrices[0] > 0) {
                    orderTypeFlag = true;
                } else if (
                    _orderType == OrderType.STOP && _triggerPrices[1] > 0
                ) {
                    orderTypeFlag = true;
                } else if (
                    _orderType == OrderType.STOP_LIMIT &&
                    _triggerPrices[0] > 0 &&
                    _triggerPrices[1] > 0
                ) {
                    orderTypeFlag = true;
                } else if (_orderType == OrderType.MARKET) {
                    checkSlippage(
                        _isLong,
                        _triggerPrices[0],
                        _triggerPrices[1],
                        priceManager.getLastPrice(_indexToken)
                    );
                    orderTypeFlag = true;
                }
            } else {
                if (_orderType == OrderType.LIMIT && _triggerPrices[0] > 0) {
                    orderTypeFlag = true;
                } else if (
                    _orderType == OrderType.STOP && _triggerPrices[1] > 0
                ) {
                    orderTypeFlag = true;
                } else if (
                    _orderType == OrderType.STOP_LIMIT &&
                    _triggerPrices[0] > 0 &&
                    _triggerPrices[1] > 0
                ) {
                    orderTypeFlag = true;
                } else if (_orderType == OrderType.MARKET) {
                    checkSlippage(
                        _isLong,
                        _triggerPrices[0],
                        _triggerPrices[1],
                        priceManager.getLastPrice(_indexToken)
                    );
                    orderTypeFlag = true;
                }
            }
        } else orderTypeFlag = true;
        if (_raise) {
            require(orderTypeFlag, "invalid position data");
        }
        return orderTypeFlag;
    }

    function validateTrailingStopInputData(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _triggerPrices
    ) external view override returns (bool) {
        (IVault.Position memory position, , ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 price = priceManager.getLastPrice(_indexToken);
        require(
            _triggerPrices[1] > 0 && _triggerPrices[1] <= position.size,
            "trailing size should be smaller than position size"
        );
        if (_isLong) {
            require(
                _triggerPrices[4] > 0 &&
                    _triggerPrices[3] > 0 &&
                    _triggerPrices[3] <= price,
                "invalid trailing data"
            );
        } else {
            require(
                _triggerPrices[4] > 0 &&
                    _triggerPrices[3] > 0 &&
                    _triggerPrices[3] >= price,
                "invalid trailing data"
            );
        }
        if (_triggerPrices[2] == TRAILING_STOP_TYPE_PERCENT) {
            require(
                _triggerPrices[4] < BASIS_POINTS_DIVISOR,
                "percent cant exceed 100%"
            );
        } else {
            if (_isLong) {
                require(
                    _triggerPrices[4] < price,
                    "step amount cant exceed price"
                );
            }
        }
        return true;
    }

    function validateTrailingStopPrice(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view override returns (bool) {
        (, IVault.OrderInfo memory order, ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 price = priceManager.getLastPrice(_indexToken);
        uint256 stopPrice;
        if (_isLong) {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice + order.stepAmount;
            } else {
                stopPrice =
                    (order.stpPrice * BASIS_POINTS_DIVISOR) /
                    (BASIS_POINTS_DIVISOR - order.stepAmount);
            }
        } else {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice - order.stepAmount;
            } else {
                stopPrice =
                    (order.stpPrice * BASIS_POINTS_DIVISOR) /
                    (BASIS_POINTS_DIVISOR + order.stepAmount);
            }
        }
        bool flag;
        if (
            _isLong &&
            order.status == IVault.OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice <= price
        ) {
            flag = true;
        } else if (
            !_isLong &&
            order.status == IVault.OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice >= price
        ) {
            flag = true;
        }
        require(flag, "price incorrect");
        return flag;
    }

    function validateTrigger(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view override returns (uint8) {
        (, IVault.OrderInfo memory order, ) = vault.getPosition(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        uint256 price = priceManager.getLastPrice(_indexToken);
        uint8 statusFlag;
        if (order.status == IVault.OrderStatus.PENDING) {
            if (order.positionType == POSITION_LIMIT) {
                if (_isLong && order.lmtPrice >= price)
                    statusFlag = ORDER_FILLED;
                else if (!_isLong && order.lmtPrice <= price)
                    statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_STOP_MARKET) {
                if (_isLong && order.stpPrice <= price)
                    statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice >= price)
                    statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                if (_isLong && order.stpPrice <= price)
                    statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice >= price)
                    statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                if (_isLong && order.stpPrice >= price)
                    statusFlag = ORDER_FILLED;
                else if (!_isLong && order.stpPrice <= price)
                    statusFlag = ORDER_FILLED;
                else statusFlag = ORDER_NOT_FILLED;
            }
        } else {
            statusFlag = ORDER_NOT_FILLED;
        }
        return statusFlag;
    }

    function validateSizeCollateralAmount(
        uint256 _size,
        uint256 _collateral
    ) external pure override {
        require(
            _size >= _collateral,
            "position size should be greater than collateral"
        );
    }

    function _mintOrBurnVUSDForVault(
        bool _mint,
        uint256 _amount,
        uint256 _fee,
        address _refer
    ) internal {
        address _feeManager = settingsManager.feeManager();
        if (_fee != 0 && _feeManager != ZERO_ADDRESS) {
            uint256 feeReward = (_fee *
                settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            uint256 feeMinusFeeReward = _fee - feeReward;
            IVUSDC(vUSDC).mint(_feeManager, feeMinusFeeReward);
            if (_mint) {
                _amount -= feeMinusFeeReward;
            } else {
                _amount += feeMinusFeeReward;
            }
            _fee = feeReward;
        }
        if (_refer != ZERO_ADDRESS && settingsManager.referEnabled()) {
            uint256 referFee = (_fee * settingsManager.referFee()) /
                BASIS_POINTS_DIVISOR;
            IVUSDC(vUSDC).mint(_refer, referFee);
            if (_mint) {
                _amount -= referFee;
            } else {
                _amount += referFee;
            }
        }
        if (_mint) {
            IVUSDC(vUSDC).mint(address(vault), _amount);
        } else {
            IVUSDC(vUSDC).burn(address(vault), _amount);
        }
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
            (_size *
                (BASIS_POINTS_DIVISOR -
                    settingsManager.liquidateThreshold(_indexToken))) /
                BASIS_POINTS_DIVISOR
        ) {
            if (_raise) {
                revert("Vault: maxThreshold exceeded");
            }
            return (
                LIQUIDATE_THRESHOLD_EXCEED,
                _marginFees + settingsManager.liquidationFeeUsd()
            );
        }
        return (LIQUIDATE_NONE_EXCEED, _marginFees);
    }
}
