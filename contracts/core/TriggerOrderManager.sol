// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/ITriggerOrderManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Constants} from "../access/Constants.sol";
import {Position, TriggerInfo, TriggerStatus, PositionTrigger } from "./structs.sol";
contract TriggerOrderManager is ITriggerOrderManager, ReentrancyGuard, Constants {
    IPositionVault public immutable positionVault;
    ISettingsManager public immutable settingsManager;
    IPriceManager public priceManager;

    mapping(bytes32 => PositionTrigger) public triggerOrders;

    event ExecuteTriggerOrders(
        bytes32 key,
        uint256 amount,
        uint256 orderId,
        uint256 price,
        TriggerStatus status
    );
    event AddTriggerOrders(
        bytes32 key,
        bool isTP,
        uint256 price,
        uint256 amountPercent,
        TriggerStatus status
    );
    event UpdateTriggerOrderStatus(bytes32 key, uint256 orderId, TriggerStatus status);
    event UpdatePositionTriggerStatus(bytes32 key, TriggerStatus status);
    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault has access");
        _;
    }

    constructor(address _positionVault, address _priceManager, address _settingsManager) {
        require(Address.isContract(_positionVault), "positionVault address is invalid");
        require(Address.isContract(_priceManager), "priceManager address is invalid");
        require(Address.isContract(_settingsManager), "settingsManager address is invalid");
        positionVault = IPositionVault(_positionVault);
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManager(_settingsManager);
    }

    function cancelTriggerOrder(        
        address _token,
        bool _isLong,
        uint256 _posId, 
        uint256 _orderId) external {
        bytes32 key = _getPositionKey(msg.sender, _token, _isLong, _posId);
        PositionTrigger storage order = triggerOrders[key];
        require(order.status == TriggerStatus.OPEN && order.triggers.length > _orderId, "TriggerOrder was cancelled");
        order.triggers[_orderId].status = TriggerStatus.CANCELLED;
        emit UpdateTriggerOrderStatus(key, _orderId, order.triggers[_orderId].status);
    }

    function cancelPositionTrigger(        
        address _token,
        bool _isLong,
        uint256 _posId) external {
        bytes32 key = _getPositionKey(msg.sender, _token, _isLong, _posId);
        PositionTrigger storage order = triggerOrders[key];
        require(order.status == TriggerStatus.OPEN , "PositionTrigger was cancelled");
        order.status = TriggerStatus.CANCELLED;
        emit UpdatePositionTriggerStatus(key, order.status);
    }

    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault returns (bool, uint256) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        PositionTrigger storage order = triggerOrders[key];
        (Position memory position, , ) = positionVault.getPosition(_account, _token, _isLong, _posId);
        if (order.status != TriggerStatus.OPEN) {
            return (false, 0);
        }
        uint256 price = priceManager.getLastPrice(_token);
        for (uint256 i = 0; i < order.triggers.length; i++) {
            bool pricesAreUpperBounds = order.triggers[i].isTP ? _isLong : !_isLong;
            if (order.triggers[i].status == TriggerStatus.OPEN && order.triggers[i].triggeredAmount == 0 && (pricesAreUpperBounds ? order.triggers[i].price <= price : price <= order.triggers[i].price)) {
                order.triggers[i].triggeredAmount = (position.size * order.triggers[i].amountPercent) / BASIS_POINTS_DIVISOR;
                order.triggers[i].triggeredAt = block.timestamp;
                order.triggers[i].triggeredPrice = price;
                order.triggers[i].status = TriggerStatus.TRIGGERED; 
                if (order.triggers[i].amountPercent == BASIS_POINTS_DIVISOR) {
                    order.status = TriggerStatus.TRIGGERED;                        
                }
                emit ExecuteTriggerOrders(
                    key,
                    order.triggers[i].triggeredAmount,
                    i,
                    price,
                    order.status
                );
                return (true, order.triggers[i].amountPercent);
            }
        }
        return (false, 0);
    }

    function addTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool[] memory _isTPs,
        uint256[] memory _prices,
        uint256[] memory _amountPercents
    ) external payable nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        (Position memory position, , ) = positionVault.getPosition(msg.sender, _indexToken, _isLong, _posId);
        require(position.size > 0, "position size should be greater than zero");
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        payable(settingsManager.feeManager()).transfer(msg.value);
        bool validateTriggerData = validateTriggerOrdersData(
            _indexToken,
            _isLong,
            _isTPs,
            _prices,
            _amountPercents
        );
        require(validateTriggerData, "triggerOrder data are incorrect");
        PositionTrigger storage triggerOrder = triggerOrders[key];
        if (triggerOrder.triggerCount > 0) {
            for (uint256 i = 0; i < _prices.length; i++) {
                triggerOrder.triggers.push(TriggerInfo({
                    isTP: _isTPs[i],
                    amountPercent: _amountPercents[i],
                    createdAt: block.timestamp,
                    price: _prices[i],
                    triggeredAmount: 0,
                    triggeredAt: 0,
                    triggeredPrice: 0,
                    status: TriggerStatus.OPEN
                }));
                triggerOrder.triggerCount += 1;
                emit AddTriggerOrders(
                    key,
                    _isTPs[i],
                    _prices[i],
                    _amountPercents[i],
                    TriggerStatus.OPEN
                );
            }
        } else {
            triggerOrder.status = TriggerStatus.OPEN;
            for (uint256 i = 0; i < _prices.length; i++) {
                triggerOrder.triggers.push(TriggerInfo({
                    isTP: _isTPs[i],
                    amountPercent: _amountPercents[i],
                    createdAt: block.timestamp,
                    price: _prices[i],
                    triggeredAmount: 0,
                    triggeredAt: 0,
                    triggeredPrice: 0,
                    status: TriggerStatus.OPEN
                }));
                triggerOrder.triggerCount += 1;
                emit AddTriggerOrders(
                    key,
                    _isTPs[i],
                    _prices[i],
                    _amountPercents[i],
                    TriggerStatus.OPEN
                );
            }
        }
    }

    function getTriggerOrderInfo(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (PositionTrigger memory) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        return triggerOrders[key];
    }

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view override returns (bool) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        PositionTrigger storage order = triggerOrders[key];
        if (order.status != TriggerStatus.OPEN) {
            return false;
        }
        uint256 price = priceManager.getLastPrice(_token);
        for (uint256 i = 0; i < order.triggers.length; i++) {
            bool pricesAreUpperBounds = order.triggers[i].isTP ? _isLong : !_isLong;
            if (order.triggers[i].status == TriggerStatus.OPEN && order.triggers[i].triggeredAmount == 0 && (pricesAreUpperBounds ? order.triggers[i].price <= price : price <= order.triggers[i].price)) {
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
