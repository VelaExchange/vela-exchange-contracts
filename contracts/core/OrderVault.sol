// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IOrderVault.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus, TriggerInfo, TriggerStatus, PositionTrigger} from "./structs.sol";

contract OrderVault is Constants, ReentrancyGuard, IOrderVault {
    uint256 public lastPosId;
    IPriceManager private priceManager;
    IPositionVault private positionVault;
    ISettingsManager private settingsManager;
    IVault private vault;
    IVaultUtils private vaultUtils;

    bool private isInitialized;
    mapping(uint256 => Order) public orders;
    event AddTrailingStop(uint256 posId, uint256[] data);
    event AddTriggerOrders(uint256 posId, bool isTP, uint256 price, uint256 amountPercent, TriggerStatus status);
    event ExecuteAddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 feeUsd);
    event ExecuteTriggerOrders(uint256 posId, uint256 amount, uint256 orderId, uint256 price, TriggerStatus status);
    event NewOrder(
        uint256 posId,
        uint256 positionType,
        OrderStatus orderStatus,
        uint256[] triggerData
    );
    event UpdateOrder(uint256 posId, uint256 positionType, OrderStatus orderStatus);
    event UpdateTrailingStop(uint256 posId, uint256 stpPrice);
    event UpdateTriggerOrderStatus(uint256 posId, uint256 orderId, TriggerStatus status);
    event UpdatePositionTriggerStatus(uint256 posId, TriggerStatus status);
    mapping(uint256 => PositionTrigger) public triggerOrders;

    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault");
        _;
    }

    modifier onlyPositionVault() {
        require(msg.sender == address(positionVault), "Only position vault");
        _;
    }

    constructor() {}

    function addTrailingStop(address _account, uint256 _posId, uint256[] memory _params) external override onlyVault {
        Order storage order = orders[_posId];
        Position memory position = positionVault.getPosition(_posId);
        require(_account == position.owner, "you are not allowed to add trailing stop");
        vaultUtils.validateTrailingStopInputData(_posId, _params);
        order.collateral = _params[0];
        order.size = _params[1];
        order.status = OrderStatus.PENDING;
        order.positionType = POSITION_TRAILING_STOP;
        order.stepType = _params[2];
        order.stpPrice = _params[3];
        order.stepAmount = _params[4];
        emit AddTrailingStop(_posId, _params);
    }

    function addTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool[] memory _isTPs,
        uint256[] memory _prices,
        uint256[] memory _amountPercents
    ) external payable nonReentrant {
        Position memory position = positionVault.getPosition(_posId);
        require(position.size > 0, "position size should be greater than zero");
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{ value: msg.value }("");
        require(success, "failed to send fee");
        bool validateTriggerData = validateTriggerOrdersData(
            _indexToken,
            _isLong,
            _isTPs,
            _prices,
            _amountPercents
        );
        require(validateTriggerData, "triggerOrder data are incorrect");
        PositionTrigger storage triggerOrder = triggerOrders[_posId];
        if (triggerOrder.triggerCount == 0) {
            triggerOrder.status = TriggerStatus.OPEN;
        }
        for (uint256 i = 0; i < _prices.length; i++) {
            triggerOrder.triggers.push(
                TriggerInfo({
                    isTP: _isTPs[i],
                    amountPercent: _amountPercents[i],
                    createdAt: block.timestamp,
                    price: _prices[i],
                    triggeredAmount: 0,
                    triggeredAt: 0,
                    status: TriggerStatus.OPEN
                })
            );
            triggerOrder.triggerCount += 1;
            emit AddTriggerOrders(_posId, _isTPs[i], _prices[i], _amountPercents[i], TriggerStatus.OPEN);
        }
    }

    function cancelMarketOrder(uint256 _posId) public override onlyPositionVault {
        Order storage order = orders[_posId];
        order.status = OrderStatus.CANCELED;
        emit UpdateOrder(_posId, order.positionType, order.status);
    }

    function cancelPendingOrder(address _account, uint256 _posId) external override onlyVault {
        Order storage order = orders[_posId];
        Position memory position = positionVault.getPosition(_posId);
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

    function cancelPositionTrigger(
        uint256 _posId) external {
        PositionTrigger storage order = triggerOrders[_posId];
        require(order.status == TriggerStatus.OPEN, "PositionTrigger was cancelled");
        order.status = TriggerStatus.CANCELLED;
        emit UpdatePositionTriggerStatus(_posId, order.status);
    }   

    function cancelTriggerOrder(
        uint256 _posId,
        uint256 _orderId) external {
        PositionTrigger storage order = triggerOrders[_posId];
        require(order.status == TriggerStatus.OPEN && order.triggers.length > _orderId, "TriggerOrder was cancelled");
        order.triggers[_orderId].status = TriggerStatus.CANCELLED;
        emit UpdateTriggerOrderStatus(_posId, _orderId, order.triggers[_orderId].status);
    }

    function createNewOrder(uint256 _posId, uint256 _positionType, uint256[] memory _params, OrderStatus _status) external override onlyPositionVault {
        Order storage order = orders[_posId];
        order.status = _status;
        order.positionType = _positionType;
        order.collateral = _params[2];
        order.size = _params[3];
        order.lmtPrice = _params[0];
        order.stpPrice = _params[1];
        emit NewOrder(_posId, order.positionType, order.status, _params);
    }

    function executeTriggerOrders(
        address _token,
        bool _isLong,
        uint256 _posId
    ) external override onlyPositionVault returns (bool, uint256, uint256) {
        PositionTrigger storage order = triggerOrders[_posId];
        Position memory position = positionVault.getPosition(_posId);
        require(order.status == TriggerStatus.OPEN, "Trigger Not Open");
        uint256 price = priceManager.getLastPrice(_token);
        for (uint256 i = 0; i < order.triggers.length; i++) {
            bool pricesAreUpperBounds = order.triggers[i].isTP ? _isLong : !_isLong;
            if (
                order.triggers[i].status == TriggerStatus.OPEN &&
                order.triggers[i].triggeredAmount == 0 &&
                (pricesAreUpperBounds ? order.triggers[i].price <= price : price <= order.triggers[i].price)
            ) {
                order.triggers[i].triggeredAmount =
                    (position.size * order.triggers[i].amountPercent) /
                    BASIS_POINTS_DIVISOR;
                order.triggers[i].triggeredAt = block.timestamp;
                order.triggers[i].status = TriggerStatus.TRIGGERED;
                if (order.triggers[i].amountPercent == BASIS_POINTS_DIVISOR) {
                    order.status = TriggerStatus.TRIGGERED;
                }
                emit ExecuteTriggerOrders(_posId, order.triggers[i].triggeredAmount, i, price, order.status);
                return (true, order.triggers[i].amountPercent, order.triggers[i].price);
            }
        }
        return (false, 0, 0);
    }

    function initialize(
        IPriceManager _priceManager,
        IPositionVault _positionVault,
        ISettingsManager _settingsManager,
        IVault _vault,
        IVaultUtils _vaultUtils
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "priceManager invalid");
        require(Address.isContract(address(_positionVault)), "positionVault invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager invalid");
        require(Address.isContract(address(_vault)), "vault invalid");
        require(Address.isContract(address(_vaultUtils)), "vaultUtils address is invalid");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        positionVault = _positionVault;
        vault = _vault;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    }

    function removeOrder(uint256 _posId) external override onlyPositionVault {
        delete orders[_posId];
    }

    function updateOrder(uint256 _posId, uint256 _positionType, uint256 _collateral, uint256 _size, OrderStatus _status) public override onlyPositionVault {
        Order storage order = orders[_posId];
        order.positionType = _positionType;
        order.collateral = _collateral;
        order.size = _size;
        order.status = _status;
        emit UpdateOrder(_posId, order.positionType, order.status);
    }


    function updateTrailingStop(uint256 _posId) external nonReentrant {
        Position memory position = positionVault.getPosition(_posId);
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

    function getOrder(uint256 _posId) external view override returns (Order memory) {
        Order memory order = orders[_posId];
        return order;
    }

    function getTriggerOrderInfo(uint256 _posId) external view returns (PositionTrigger memory) {
        return triggerOrders[_posId];
    }

    function validateTPSLTriggers(address _token, bool _isLong, uint256 _posId) external view override returns (bool) {
        PositionTrigger storage order = triggerOrders[_posId];
        if (order.status != TriggerStatus.OPEN) {
            return false;
        }
        uint256 price = priceManager.getLastPrice(_token);
        for (uint256 i = 0; i < order.triggers.length; i++) {
            bool pricesAreUpperBounds = order.triggers[i].isTP ? _isLong : !_isLong;
            if (
                order.triggers[i].status == TriggerStatus.OPEN &&
                order.triggers[i].triggeredAmount == 0 &&
                (pricesAreUpperBounds ? order.triggers[i].price <= price : price <= order.triggers[i].price)
            ) {
                return true;
            }
        }
        return false;
    }

    function validateTriggerOrdersData(
        address _indexToken,
        bool _isLong,
        bool[] memory _isTPs,
        uint256[] memory _prices,
        uint256[] memory _amountPercents
    ) internal view returns (bool) {
        uint256 price = priceManager.getLastPrice(_indexToken);
        for (uint256 i = 0; i < _prices.length; ++i) {
            bool pricesAreUpperBounds = _isTPs[i] ? _isLong : !_isLong;
            if (_amountPercents[i] > 0 && (price < _prices[i]) != pricesAreUpperBounds) {
                return false;
            }
        }
        return true;
    }
}
