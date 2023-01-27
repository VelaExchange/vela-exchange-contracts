// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSDC.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/ITriggerOrderManager.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus} from "./structs.sol";

contract PositionVault is Constants, ReentrancyGuard, IPositionVault {
    uint256 public lastPosId;
    IPriceManager private priceManager;
    ISettingsManager private settingsManager;
    ITriggerOrderManager private triggerOrderManager;
    IVault private vault;
    IVaultUtils private vaultUtils;

    bool private isInitialized;
    mapping(address => mapping(bool => uint256)) public override poolAmounts;
    mapping(address => mapping(bool => uint256)) public override reservedAmounts;
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => ConfirmInfo) public confirms;
    mapping(bytes32 => OrderInfo) public orders;
    event AddOrRemoveCollateral(
        bytes32 indexed key,
        bool isPlus,
        uint256 amount,
        uint256 reserveAmount,
        uint256 collateral,
        uint256 size
    );
    event AddPosition(bytes32 indexed key, bool confirmDelayStatus, uint256 collateral, uint256 size);
    event AddTrailingStop(bytes32 key, uint256[] data);
    event ConfirmDelayTransaction(
        bytes32 indexed key,
        bool confirmDelayStatus,
        uint256 collateral,
        uint256 size,
        uint256 feeUsd
    );
    event DecreasePoolAmount(address indexed token, bool isLong, uint256 amount);
    event DecreaseReservedAmount(address indexed token, bool isLong, uint256 amount);
    event IncreasePoolAmount(address indexed token, bool isLong, uint256 amount);
    event IncreaseReservedAmount(address indexed token, bool isLong, uint256 amount);
    event NewOrder(
        bytes32 key,
        address indexed account,
        address indexToken,
        bool isLong,
        uint256 posId,
        uint256 positionType,
        OrderStatus orderStatus,
        uint256[] triggerData
    );
    event UpdateOrder(bytes32 key, uint256 positionType, OrderStatus orderStatus);
    event UpdatePoolAmount(address indexed token, bool isLong, uint256 amount);
    event UpdateReservedAmount(address indexed token, bool isLong, uint256 amount);
    event UpdateTrailingStop(bytes32 key, uint256 stpPrice);
    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault has access");
        _;
    }

    constructor() {}

    function addOrRemoveCollateral(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        if (isPlus) {
            position.collateral += _amount;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            position.reserveAmount += _amount;
            vault.takeVUSDIn(_account, position.refer, _amount, 0);
            _increasePoolAmount(_indexToken, _isLong, _amount);
        } else {
            position.collateral -= _amount;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            vaultUtils.validateLiquidation(_account, _indexToken, _isLong, _posId, true);
            position.reserveAmount -= _amount;
            position.lastIncreasedTime = block.timestamp;
            vault.takeVUSDOut(_account, position.refer, 0, _amount);
            _decreasePoolAmount(_indexToken, _isLong, _amount);
        }
        emit AddOrRemoveCollateral(key, isPlus, _amount, position.reserveAmount, position.collateral, position.size);
    }

    function addPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        ConfirmInfo storage confirm = confirms[key];
        confirm.delayStartTime = block.timestamp;
        confirm.confirmDelayStatus = true;
        confirm.pendingDelayCollateral = _collateralDelta;
        confirm.pendingDelaySize = _sizeDelta;
        emit AddPosition(key, confirm.confirmDelayStatus, _collateralDelta, _sizeDelta);
    }

    function addTrailingStop(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        OrderInfo storage order = orders[key];
        vaultUtils.validateTrailingStopInputData(_account, _indexToken, _isLong, _posId, _params);
        order.pendingCollateral = _params[0];
        order.pendingSize = _params[1];
        order.status = OrderStatus.PENDING;
        order.positionType = POSITION_TRAILING_STOP;
        order.stepType = _params[2];
        order.stpPrice = _params[3];
        order.stepAmount = _params[4];
        emit AddTrailingStop(key, _params);
    }

    function cancelPendingOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        OrderInfo storage order = orders[key];
        require(order.status == OrderStatus.PENDING, "Not in Pending");
        if (order.positionType == POSITION_TRAILING_STOP) {
            order.status = OrderStatus.FILLED;
            order.positionType = POSITION_MARKET;
        } else {
            order.status = OrderStatus.CANCELED;
        }
        order.pendingCollateral = 0;
        order.pendingSize = 0;
        order.lmtPrice = 0;
        order.stpPrice = 0;
        emit UpdateOrder(key, order.positionType, order.status);
    }

    function confirmDelayTransaction(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "not allowed");
        ConfirmInfo storage confirm = confirms[key];
        vaultUtils.validateConfirmDelay(_account, _indexToken, _isLong, _posId, true);
        uint256 fee = settingsManager.collectMarginFees(
            _account,
            _indexToken,
            _isLong,
            confirm.pendingDelaySize,
            position.size,
            position.entryFundingRate
        );
        _increasePosition(
            _account,
            _indexToken,
            confirm.pendingDelayCollateral + fee,
            confirm.pendingDelaySize,
            _posId,
            _isLong,
            position.refer
        );
        confirm.confirmDelayStatus = false;
        confirm.pendingDelayCollateral = 0;
        confirm.pendingDelaySize = 0;
        emit ConfirmDelayTransaction(
            key,
            confirm.confirmDelayStatus,
            confirm.pendingDelayCollateral,
            confirm.pendingDelaySize,
            fee
        );
    }

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault {
        _decreasePosition(_account, _indexToken, _sizeDelta, _isLong, _posId);
    }

    function initialize(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager,
        ITriggerOrderManager _triggerOrderManager,
        IVault _vault,
        IVaultUtils _vaultUtils
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "priceManager address is invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager address is invalid");
        require(Address.isContract(address(_triggerOrderManager)), "triggerOrderManager address is invalid");
        require(Address.isContract(address(_vault)), "vault address is invalid");
        require(Address.isContract(address(_vaultUtils)), "vaultUtils address is invalid");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        triggerOrderManager = _triggerOrderManager;
        vault = _vault;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    }

    function liquidatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position memory position = positions[key];
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(
            _account,
            _indexToken,
            _isLong,
            _posId,
            false
        );
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");
        if (liquidationState == LIQUIDATE_THRESHOLD_EXCEED) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(_account, _indexToken, position.size, _isLong, _posId);
            return;
        }
        vault.accountDeltaAndFeeIntoTotalUSDC(true, 0, marginFees);
        uint256 bounty = (marginFees * settingsManager.bountyPercent()) / BASIS_POINTS_DIVISOR;
        vault.transferBounty(msg.sender, bounty);
        settingsManager.decreaseOpenInterest(_indexToken, _account, _isLong, position.size);
        _decreasePoolAmount(_indexToken, _isLong, marginFees);
        vaultUtils.emitLiquidatePositionEvent(_account, _indexToken, _isLong, _posId);
        delete positions[key];
        // pay the fee receive using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
    }

    function newPositionOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external nonReentrant onlyVault {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, lastPosId);
        OrderInfo storage order = orders[key];
        Position storage position = positions[key];
        vaultUtils.validatePosData(_isLong, _indexToken, _orderType, _params, true);
        order.pendingCollateral = _params[2];
        order.pendingSize = _params[3];
        position.owner = _account;
        position.refer = _refer;
        if (_orderType == OrderType.MARKET) {
            require(settingsManager.marketOrderEnabled(), "market order was disabled");
            order.positionType = POSITION_MARKET;
            uint256 fee = settingsManager.collectMarginFees(
                _account,
                _indexToken,
                _isLong,
                order.pendingSize,
                position.size,
                position.entryFundingRate
            );
            _increasePosition(_account, _indexToken, _params[2] + fee, order.pendingSize, lastPosId, _isLong, _refer);
            order.pendingCollateral = 0;
            order.pendingSize = 0;
            order.status = OrderStatus.FILLED;
        } else if (_orderType == OrderType.LIMIT) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_LIMIT;
            order.lmtPrice = _params[0];
        } else if (_orderType == OrderType.STOP) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_MARKET;
            order.stpPrice = _params[1];
        } else if (_orderType == OrderType.STOP_LIMIT) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_LIMIT;
            order.lmtPrice = _params[0];
            order.stpPrice = _params[1];
        }
        lastPosId += 1;
        emit NewOrder(key, _account, _indexToken, _isLong, lastPosId - 1, order.positionType, order.status, _params);
    }

    function triggerPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position memory position = positions[key];
        OrderInfo storage order = orders[key];
        uint8 statusFlag = vaultUtils.validateTrigger(_account, _indexToken, _isLong, _posId);
        (bool hitTrigger, uint256 triggerAmountPercent) = triggerOrderManager.executeTriggerOrders(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        require(
            (statusFlag == ORDER_FILLED || hitTrigger) &&
                (position.owner == msg.sender || settingsManager.isManager(msg.sender)),
            "trigger not ready"
        );
        if (hitTrigger) {
            _decreasePosition(
                _account,
                _indexToken,
                (position.size * (triggerAmountPercent)) / BASIS_POINTS_DIVISOR,
                _isLong,
                _posId
            );
        }
        if (statusFlag == ORDER_FILLED) {
            if (order.positionType == POSITION_LIMIT) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    _indexToken,
                    _isLong,
                    order.pendingSize,
                    position.size,
                    position.entryFundingRate
                );
                _increasePosition(
                    _account,
                    _indexToken,
                    order.pendingCollateral + fee,
                    order.pendingSize,
                    _posId,
                    _isLong,
                    position.refer
                );
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_MARKET) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    _indexToken,
                    _isLong,
                    order.pendingSize,
                    position.size,
                    position.entryFundingRate
                );
                _increasePosition(
                    _account,
                    _indexToken,
                    order.pendingCollateral + fee,
                    order.pendingSize,
                    _posId,
                    _isLong,
                    position.refer
                );
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                order.positionType = POSITION_LIMIT;
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                _decreasePosition(_account, _indexToken, order.pendingSize, _isLong, _posId);
                order.positionType = POSITION_MARKET;
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            }
        }
        emit UpdateOrder(key, order.positionType, order.status);
    }

    function updateTrailingStop(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        OrderInfo storage order = orders[key];
        uint256 price = priceManager.getLastPrice(_indexToken);
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "updateTStop not allowed");
        vaultUtils.validateTrailingStopPrice(_account, _indexToken, _isLong, _posId, true);
        if (_isLong) {
            order.stpPrice = order.stepType == 0
                ? price - order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR - order.stepAmount)) / BASIS_POINTS_DIVISOR;
        } else {
            order.stpPrice = order.stepType == 0
                ? price + order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR + order.stepAmount)) / BASIS_POINTS_DIVISOR;
        }
        emit UpdateTrailingStop(key, order.stpPrice);
    }

    function _decreasePoolAmount(address _indexToken, bool _isLong, uint256 _amount) internal {
        require(poolAmounts[_indexToken][_isLong] >= _amount, "Vault: poolAmount exceeded");
        poolAmounts[_indexToken][_isLong] -= _amount;
        emit DecreasePoolAmount(_indexToken, _isLong, poolAmounts[_indexToken][_isLong]);
    }

    function _decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) internal {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        address _refer = position.refer;
        require(position.size > 0, "position size is zero");
        settingsManager.decreaseOpenInterest(
            _indexToken,
            _account,
            _isLong,
            _sizeDelta
        );
        _decreaseReservedAmount(_indexToken, _isLong, _sizeDelta);
        position.reserveAmount -= (position.reserveAmount * _sizeDelta) / position.size;
        (uint256 usdOut, uint256 usdOutFee) = _reduceCollateral(_account, _indexToken, _sizeDelta, _isLong, _posId);
        if (position.size != _sizeDelta) {
            position.entryFundingRate = settingsManager.cumulativeFundingRates(_indexToken, _isLong);
            position.size -= _sizeDelta;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            vaultUtils.validateLiquidation(_account, _indexToken, _isLong, _posId, true);
            vaultUtils.emitDecreasePositionEvent(_account, _indexToken, _isLong, _posId, _sizeDelta, usdOutFee);
        } else {
            vaultUtils.emitClosePositionEvent(_account, _indexToken, _isLong, _posId);
            delete positions[key];
        }
        if (usdOutFee <= usdOut) {
            if (usdOutFee != usdOut) {
                _decreasePoolAmount(_indexToken, _isLong, usdOut - usdOutFee);
            }
            vault.takeVUSDOut(_account, _refer, usdOutFee, usdOut);
        } else if (usdOutFee != 0) {
            vault.distributeFee(_account, _refer, usdOutFee);
        }
    }

    function _decreaseReservedAmount(address _token, bool _isLong, uint256 _amount) internal {
        require(reservedAmounts[_token][_isLong] >= _amount, "Vault: reservedAmounts exceeded");
        reservedAmounts[_token][_isLong] -= _amount;
        emit DecreaseReservedAmount(_token, _isLong, reservedAmounts[_token][_isLong]);
    }

    function _increasePoolAmount(address _indexToken, bool _isLong, uint256 _amount) internal {
        poolAmounts[_indexToken][_isLong] += _amount;
        emit IncreasePoolAmount(_indexToken, _isLong, poolAmounts[_indexToken][_isLong]);
    }

    function _increasePosition(
        address _account,
        address _indexToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        uint256 _posId,
        bool _isLong,
        address _refer
    ) internal {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        uint256 price = priceManager.getLastPrice(_indexToken);
        if (position.size == 0) {
            position.averagePrice = price;
        }

        if (position.size > 0 && _sizeDelta > 0) {
            position.averagePrice = priceManager.getNextAveragePrice(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                price,
                _sizeDelta
            );
        }
        uint256 fee = settingsManager.collectMarginFees(
            _account,
            _indexToken,
            _isLong,
            _sizeDelta,
            position.size,
            position.entryFundingRate
        );
        uint256 _amountInAfterFee = _amountIn - fee;
        position.collateral += _amountInAfterFee;
        position.reserveAmount += _amountIn;
        position.entryFundingRate = settingsManager.cumulativeFundingRates(_indexToken, _isLong);
        position.size += _sizeDelta;
        position.lastIncreasedTime = block.timestamp;
        position.lastPrice = price;
        vault.accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        vault.takeVUSDIn(_account, _refer, _amountIn, fee);
        settingsManager.validatePosition(_account, _indexToken, _isLong, position.size, position.collateral);
        vaultUtils.validateLiquidation(_account, _indexToken, _isLong, _posId, true);
        settingsManager.increaseOpenInterest(_indexToken, _account, _isLong, _sizeDelta);
        _increaseReservedAmount(_indexToken, _isLong, _sizeDelta);
        _increasePoolAmount(_indexToken, _isLong, _amountInAfterFee);
        vaultUtils.emitIncreasePositionEvent(_account, _indexToken, _isLong, _posId, _amountIn, _sizeDelta, fee);
    }

    function _increaseReservedAmount(address _token, bool _isLong, uint256 _amount) internal {
        reservedAmounts[_token][_isLong] += _amount;
        emit IncreaseReservedAmount(_token, _isLong, reservedAmounts[_token][_isLong]);
    }

    function _reduceCollateral(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) internal returns (uint256, uint256) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        bool hasProfit;
        uint256 adjustedDelta;
        // scope variables to avoid stack too deep errors
        {
            (bool _hasProfit, uint256 delta) = priceManager.getDelta(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong
            );
            hasProfit = _hasProfit;
            // get the proportional change in pnl
            adjustedDelta = (_sizeDelta * delta) / position.size;
        }

        uint256 usdOut;
        // transfer profits
        uint256 fee = settingsManager.collectMarginFees(
            _account,
            _indexToken,
            _isLong,
            _sizeDelta,
            position.size,
            position.entryFundingRate
        );
        if (adjustedDelta > 0) {
            if (hasProfit) {
                usdOut = adjustedDelta;
                position.realisedPnl += int256(adjustedDelta);
            } else {
                position.collateral -= adjustedDelta;
                position.realisedPnl -= int256(adjustedDelta);
            }
        }

        // if the position will be closed, then transfer the remaining collateral out
        if (position.size == _sizeDelta) {
            usdOut += position.collateral;
            position.collateral = 0;
        } else {
            // reduce the position's collateral by _collateralDelta
            // transfer _collateralDelta out
            uint256 _collateralDelta = (position.collateral * _sizeDelta) / position.size;
            usdOut += _collateralDelta;
            position.collateral -= _collateralDelta;
        }
        vault.accountDeltaAndFeeIntoTotalUSDC(hasProfit, adjustedDelta, fee);
        // if the usdOut is more or equal than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        if (usdOut < fee) {
            position.collateral -= fee;
        }
        vaultUtils.validateDecreasePosition(_account, _indexToken, _isLong, _posId, true);
        return (usdOut, fee);
    }

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view override returns (Position memory, OrderInfo memory, ConfirmInfo memory) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position memory position = positions[key];
        OrderInfo memory order = orders[key];
        ConfirmInfo memory confirm = confirms[key];
        return (position, order, confirm);
    }
}
