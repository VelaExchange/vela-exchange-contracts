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
    mapping(uint256 => Position) public positions;
    mapping(uint256 => ConfirmInfo) public confirms;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => address) public liquidateRegistrant;
    mapping(uint256 => uint256) public liquidateRegisterTime;

    event AddOrRemoveCollateral(
        uint256 posId,
        bool isPlus,
        uint256 amount,
        uint256 reserveAmount,
        uint256 collateral,
        uint256 size
    );
    event AddPosition(uint256 posId, bool confirmDelayStatus, uint256 collateral, uint256 size);
    event AddTrailingStop(uint256 posId, uint256[] data);
    event ConfirmDelayTransaction(
        uint256 posId,
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
        address indexed account,
        address indexToken,
        bool isLong,
        uint256 posId,
        uint256 positionType,
        OrderStatus orderStatus,
        uint256[] triggerData
    );
    event UpdateOrder(uint256 posId, uint256 positionType, OrderStatus orderStatus);
    event UpdatePoolAmount(address indexed token, bool isLong, uint256 amount);
    event UpdateReservedAmount(address indexed token, bool isLong, uint256 amount);
    event UpdateTrailingStop(uint256 posId, uint256 stpPrice);
    event RegisterLiquidation(address account, address token, bool isLong, uint256 posId, address caller, uint256 marginFees);
    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault has access");
        _;
    }

    constructor() {}

    function addOrRemoveCollateral(
        address _account,
        address _indexToken,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external override onlyVault {
        Position storage position = positions[_posId];
        if (isPlus) {
            position.collateral += _amount;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            position.reserveAmount += _amount;
            vault.takeVUSDIn(_account, position.refer, _amount, 0);
            _increasePoolAmount(_indexToken, position.isLong, _amount);
        } else {
            position.collateral -= _amount;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            vaultUtils.validateMaxLeverage(_indexToken, position.size, position.collateral);
            position.reserveAmount -= _amount;
            position.lastIncreasedTime = block.timestamp;
            vault.takeVUSDOut(_account, position.refer, 0, _amount);
            _decreasePoolAmount(_indexToken, position.isLong, _amount);
        }
        emit AddOrRemoveCollateral(_posId, isPlus, _amount, position.reserveAmount, position.collateral, position.size);
    }

    function addPosition(
        address _account,
        address _indexToken,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external override onlyVault {
        ConfirmInfo storage confirm = confirms[_posId];
        Position storage position = positions[_posId];
        require(position.size > 0, "Position not Open");
        require(_account == position.owner && _indexToken == position.indexToken, "you are not allowed to add position");
        confirm.delayStartTime = block.timestamp;
        confirm.confirmDelayStatus = true;
        confirm.pendingDelayCollateral = _collateralDelta;
        confirm.pendingDelaySize = _sizeDelta;
        emit AddPosition(_posId, confirm.confirmDelayStatus, _collateralDelta, _sizeDelta);
    }

    function addTrailingStop(
        address _account,
        address _indexToken,
        uint256 _posId,
        uint256[] memory _params
    ) external override onlyVault {
        Order storage order = orders[_posId];
        Position storage position = positions[_posId];
        require(_account == position.owner && _indexToken == position.indexToken, "you are not allowed to add trailing stop");
        vaultUtils.validateTrailingStopInputData(_indexToken, position.isLong, _posId, _params);
        order.collateral = _params[0];
        order.size = _params[1];
        order.status = OrderStatus.PENDING;
        order.positionType = POSITION_TRAILING_STOP;
        order.stepType = _params[2];
        order.stpPrice = _params[3];
        order.stepAmount = _params[4];
        emit AddTrailingStop(_posId, _params);
    }

    function cancelPendingOrder(
        address _account,
        uint256 _posId
    ) external override onlyVault {
        Order storage order = orders[_posId];
        Position storage position = positions[_posId];
        require(_account == position.owner, "You are not allowed to cancel");
        require(order.status == OrderStatus.PENDING, "Not in Pending");
        if (order.positionType == POSITION_TRAILING_STOP) {
            order.status = OrderStatus.FILLED;
            order.positionType = POSITION_MARKET;
        } else {
            order.status = OrderStatus.CANCELED;
        }
        order.collateral = 0;
        order.size = 0;
        order.lmtPrice = 0;
        order.stpPrice = 0;
        emit UpdateOrder(_posId, order.positionType, order.status);
    }

    function confirmDelayTransaction(
        address _account,
        uint256 _posId
    ) external nonReentrant {
        Position storage position = positions[_posId];
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "not allowed");
        ConfirmInfo storage confirm = confirms[_posId];
        vaultUtils.validateConfirmDelay(_posId, true);
        uint256 price = priceManager.getLastPrice(position.indexToken);
        uint256 fee = settingsManager.collectMarginFees(
            _account,
            position.indexToken,
            position.isLong,
            confirm.pendingDelaySize,
            position.size,
            position.entryFundingRate
        );
        _increasePosition(
            _account,
            position.indexToken,
            confirm.pendingDelayCollateral + fee,
            confirm.pendingDelaySize,
            _posId,
            price,
            position.isLong
        );
        emit ConfirmDelayTransaction(
            _posId,
            confirm.confirmDelayStatus,
            confirm.pendingDelayCollateral,
            confirm.pendingDelaySize,
            fee
        );
        confirm.confirmDelayStatus = false;
        confirm.pendingDelayCollateral = 0;
        confirm.pendingDelaySize = 0;
    }

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _posId
    ) external override onlyVault {
        Position memory position = positions[_posId];
        uint256 price = priceManager.getLastPrice(_indexToken);
        require(_account == position.owner && _indexToken == position.indexToken, 'you are not allowed to decrease position');
        _decreasePosition(_account, _indexToken, _sizeDelta, price, position.isLong, _posId);
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

    function registerLiquidatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        require(liquidateRegistrant[_posId] == address(0), "not the firstCaller");
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(
            _account,
            _indexToken,
            _isLong,
            _posId,
            false
        );
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");
        liquidateRegistrant[_posId] = msg.sender;
        liquidateRegisterTime[_posId] = block.timestamp;
        emit RegisterLiquidation(_account, _indexToken, _isLong, _posId, msg.sender, marginFees);
    }

    function liquidatePosition(
        address _account,
        uint256 _posId
    ) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateCumulativeFundingRate(position.indexToken, position.isLong);
        require(
            settingsManager.isManager(msg.sender) ||
                ( msg.sender == liquidateRegistrant[_posId] &&
                liquidateRegisterTime[_posId] + settingsManager.liquidationPendingTime() <= block.timestamp ),
            "not manager or not allowed before pendingTime"
        );
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(
            _account,
            position.indexToken,
            position.isLong,
            _posId,
            false
        );
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");

        (uint32 teamPercent, uint32 firstCallerPercent, uint32 resolverPercent) = settingsManager.bountyPercent();
        uint256 bountyTeam = (marginFees * teamPercent) / BASIS_POINTS_DIVISOR;
        //uint256 bounty = bountyTeam; //this can be used in log, leave to future
        vault.transferBounty(settingsManager.feeManager(), bountyTeam);
        if ( msg.sender == liquidateRegistrant[_posId] || liquidateRegistrant[_posId] == address(0)){ 
            // same address to receive firstCaller bounty and resolver bounty
            uint256 bountyCaller = (marginFees * (firstCallerPercent+resolverPercent)) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(msg.sender, bountyCaller);
            //bounty += bountyCaller;
        }else{
            uint256 bountyCaller = (marginFees * firstCallerPercent) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(liquidateRegistrant[_posId], bountyCaller);
            //bounty += bountyCaller;
            uint256 bountyResolver = (marginFees * resolverPercent) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(msg.sender, bountyResolver);
            //bounty += bountyResolver;
        }

        if (liquidationState == LIQUIDATE_THRESHOLD_EXCEED) {
            uint256 price = priceManager.getLastPrice(position.indexToken);
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(_account, position.indexToken, position.size, price, position.isLong, _posId);
            return;
        }
        vault.accountDeltaAndFeeIntoTotalUSDC(true, 0, marginFees);
        settingsManager.decreaseOpenInterest(position.indexToken, _account, position.isLong, position.size);
        _decreaseReservedAmount(position.indexToken, position.isLong, position.size);
        _decreasePoolAmount(position.indexToken, position.isLong, marginFees);
        vaultUtils.emitLiquidatePositionEvent(_account, position.indexToken, position.isLong, _posId);
        delete positions[_posId];
        delete orders[_posId];
        delete confirms[_posId];
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
        Order storage order = orders[lastPosId];
        Position storage position = positions[lastPosId];
        vaultUtils.validatePosData(_isLong, _indexToken, _orderType, _params, true);
        order.collateral = _params[2];
        order.size = _params[3];
        position.owner = _account;
        position.refer = _refer;
        position.indexToken = _indexToken;
        position.isLong = _isLong;
        if (_orderType == OrderType.MARKET) {
            require(settingsManager.marketOrderEnabled(), "market order was disabled");
            order.positionType = POSITION_MARKET;
            uint256 fee = settingsManager.collectMarginFees(
                _account,
                _indexToken,
                _isLong,
                order.size,
                position.size,
                position.entryFundingRate
            );
            uint256 price = priceManager.getLastPrice(_indexToken);
            _increasePosition(_account, _indexToken, order.collateral + fee, order.size, lastPosId, price, _isLong);
            order.collateral = 0;
            order.size = 0;
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
        emit NewOrder(_account, _indexToken, _isLong, lastPosId - 1, order.positionType, order.status, _params);
    }

    function triggerForOpenOrders(
        address _account,
        uint256 _posId
    ) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateCumulativeFundingRate(position.indexToken, position.isLong);
        Order storage order = orders[_posId];
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "You are not allowed to trigger");
        uint8 statusFlag = vaultUtils.validateTrigger(position.indexToken, position.isLong, _posId);
        require(statusFlag == ORDER_FILLED, "trigger not ready");
        if (statusFlag == ORDER_FILLED) {
            if (order.positionType == POSITION_LIMIT) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    position.indexToken,
                    position.isLong,
                    order.size,
                    position.size,
                    position.entryFundingRate
                );
                _increasePosition(
                    _account,
                    position.indexToken,
                    order.collateral + fee,
                    order.size,
                    _posId,
                    order.lmtPrice,
                    position.isLong
                );
                order.collateral = 0;
                order.size = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_MARKET) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    position.indexToken,
                    position.isLong,
                    order.size,
                    position.size,
                    position.entryFundingRate
                );
                _increasePosition(
                    _account,
                    position.indexToken,
                    order.collateral + fee,
                    order.size,
                    _posId,
                    order.stpPrice,
                    position.isLong
                );
                order.collateral = 0;
                order.size = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                order.positionType = POSITION_LIMIT;
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                _decreasePosition(_account, position.indexToken, order.size, order.stpPrice, position.isLong, _posId);
                order.positionType = POSITION_MARKET;
                order.collateral = 0;
                order.size = 0;
                order.status = OrderStatus.FILLED;
            }
        }
        emit UpdateOrder(_posId, order.positionType, order.status);
    }


    function triggerForTPSL(
        address _account,
        uint256 _posId
    ) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateCumulativeFundingRate(position.indexToken, position.isLong);
        Order storage order = orders[_posId];
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "You are not allowed to trigger");
        (bool hitTrigger, uint256 triggerAmountPercent, uint256 triggerPrice) = triggerOrderManager.executeTriggerOrders(
            position.indexToken,
            position.isLong,
            _posId
        );
        require(hitTrigger, "trigger not ready");
        if (hitTrigger) {
            _decreasePosition(
                _account,
                position.indexToken,
                (position.size * (triggerAmountPercent)) / BASIS_POINTS_DIVISOR,
                triggerPrice,
                position.isLong,
                _posId
            );
        }
        emit UpdateOrder(_posId, order.positionType, order.status);
    }

    function updateTrailingStop(
        uint256 _posId
    ) external nonReentrant {
        Position storage position = positions[_posId];
        Order storage order = orders[_posId];
        uint256 price = priceManager.getLastPrice(position.indexToken);
        require(position.owner == msg.sender || settingsManager.isManager(msg.sender), "updateTStop not allowed");
        vaultUtils.validateTrailingStopPrice(position.indexToken, position.isLong, _posId, true);
        if (position.isLong) {
            order.stpPrice = order.stepType == 0
                ? price - order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR - order.stepAmount)) / BASIS_POINTS_DIVISOR;
        } else {
            order.stpPrice = order.stepType == 0
                ? price + order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR + order.stepAmount)) / BASIS_POINTS_DIVISOR;
        }
        emit UpdateTrailingStop(_posId, order.stpPrice);
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
        uint256 _price,
        bool _isLong,
        uint256 _posId
    ) internal {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        Position storage position = positions[_posId];
        require(position.size > 0, "position size is zero");
        settingsManager.decreaseOpenInterest(
            _indexToken,
            _account,
            _isLong,
            _sizeDelta
        );
        _decreaseReservedAmount(_indexToken, _isLong, _sizeDelta);
        position.reserveAmount -= (position.reserveAmount * _sizeDelta) / position.size;
        (uint256 usdOut, uint256 usdOutFee) = _reduceCollateral(_account, _indexToken, _sizeDelta, _price, _isLong, _posId);
        if (position.size != _sizeDelta) {
            position.entryFundingRate = settingsManager.cumulativeFundingRates(_indexToken, _isLong);
            position.size -= _sizeDelta;
            vaultUtils.validateSizeCollateralAmount(position.size, position.collateral);
            vaultUtils.validateMaxLeverage(_indexToken, position.size, position.collateral);
            vaultUtils.emitDecreasePositionEvent(_account, _indexToken, _isLong, _posId, _sizeDelta, usdOutFee);
        } else {
            vaultUtils.emitClosePositionEvent(_account, _indexToken, _isLong, _posId);
            delete positions[_posId];
            delete orders[_posId];
            delete confirms[_posId];
        }
        if (usdOutFee <= usdOut) {
            if (usdOutFee != usdOut) {
                _decreasePoolAmount(_indexToken, _isLong, usdOut - usdOutFee);
            }
            vault.takeVUSDOut(_account, position.refer, usdOutFee, usdOut);
        } else if (usdOutFee != 0) {
            vault.distributeFee(_account, position.refer, usdOutFee);
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
        uint256 _price,
        bool _isLong
    ) internal {
        settingsManager.updateCumulativeFundingRate(_indexToken, _isLong);
        Position storage position = positions[_posId];
        if (position.size == 0) {
            position.averagePrice = _price;
        }

        if (position.size > 0 && _sizeDelta > 0) {
            position.averagePrice = priceManager.getNextAveragePrice(
                position.size,
                position.averagePrice,
                _isLong,
                _price,
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
        position.lastPrice = _price;
        vault.accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        vault.takeVUSDIn(_account, position.refer, _amountIn, fee);
        settingsManager.validatePosition(_account, _indexToken, _isLong, position.size, position.collateral);
        vaultUtils.validateMaxLeverage(_indexToken, position.size, position.collateral);
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
        uint256 _price,
        bool _isLong,
        uint256 _posId
    ) internal returns (uint256, uint256) {
        Position storage position = positions[_posId];
        bool hasProfit;
        uint256 adjustedDelta;
        // scope variables to avoid stack too deep errors
        {
            (bool _hasProfit, uint256 delta) = priceManager.getDelta(
                position.size,
                position.averagePrice,
                _price,
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
        vaultUtils.validateDecreasePosition(_isLong, _posId, _price, true);
        return (usdOut, fee);
    }

    function getPosition(
        uint256 _posId
    ) external view override returns (Position memory, Order memory, ConfirmInfo memory) {
        Position memory position = positions[_posId];
        Order memory order = orders[_posId];
        ConfirmInfo memory confirm = confirms[_posId];
        return (position, order, confirm);
    }
}
