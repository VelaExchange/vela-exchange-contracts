// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/ITriggerOrderManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Constants} from "../access/Constants.sol";
import {Position, TriggerStatus, TriggerOrder} from "./structs.sol";

contract TriggerOrderManager is ITriggerOrderManager, ReentrancyGuard, Constants {
    IPositionVault public immutable positionVault;
    ISettingsManager public immutable settingsManager;
    IPriceManager public priceManager;

    mapping(bytes32 => TriggerOrder) public triggerOrders;

    event ExecuteTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status
    );
    event UpdateTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status
    );
    event UpdateTriggerStatus(bytes32 key, TriggerStatus status);

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

    function cancelTriggerOrders(address _token, bool _isLong, uint256 _posId) external {
        bytes32 key = _getPositionKey(msg.sender, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        require(order.status == TriggerStatus.OPEN, "TriggerOrder was cancelled");
        order.status = TriggerStatus.CANCELLED;
        emit UpdateTriggerStatus(key, order.status);
    }

    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault returns (bool, uint256) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        (Position memory position, , ) = positionVault.getPosition(_account, _token, _isLong, _posId);
        require(order.status == TriggerStatus.OPEN, "TriggerOrder not Open");
        uint256 price = priceManager.getLastPrice(_token);
        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;
            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= price : price <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                    triggeredAmounts[i] = (position.size * amountPercents[i]) / BASIS_POINTS_DIVISOR;
                }
            }
            if (closeAmountPercent != 0) {
                emit ExecuteTriggerOrders(
                    key,
                    order.tpPrices,
                    order.slPrices,
                    order.tpAmountPercents,
                    order.slAmountPercents,
                    order.tpTriggeredAmounts,
                    order.slTriggeredAmounts,
                    order.status
                );
                if (closeAmountPercent >= BASIS_POINTS_DIVISOR) {
                    order.status = TriggerStatus.TRIGGERED;
                    return (true, BASIS_POINTS_DIVISOR);
                }
                return (true, closeAmountPercent);
            }
            if (!tp) {
                break;
            }
        }
        return (false, 0);
    }

    function updateTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpAmountPercents,
        uint256[] memory _slAmountPercents,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external payable nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        (Position memory position, , ) = positionVault.getPosition(msg.sender, _indexToken, _isLong, _posId);
        require(position.size > 0, "position size should be greater than zero");
        payable(settingsManager.positionManager()).transfer(msg.value);
        bool validateTriggerData = validateTriggerOrdersData(
            _indexToken,
            _isLong,
            _tpPrices,
            _slPrices,
            _tpTriggeredAmounts,
            _slTriggeredAmounts
        );
        require(validateTriggerData, "triggerOrder data are incorrect");
        if (triggerOrders[key].tpPrices.length + triggerOrders[key].slPrices.length < _tpPrices.length + _slPrices.length) {
            require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        }
        triggerOrders[key] = TriggerOrder({
            key: key,
            tpTriggeredAmounts: _tpTriggeredAmounts,
            slTriggeredAmounts: _slTriggeredAmounts,
            tpPrices: _tpPrices,
            tpAmountPercents: _tpAmountPercents,
            slPrices: _slPrices,
            slAmountPercents: _slAmountPercents,
            status: TriggerStatus.OPEN
        });
        emit UpdateTriggerOrders(
            key,
            _tpPrices,
            _slPrices,
            _tpAmountPercents,
            _slAmountPercents,
            _tpTriggeredAmounts,
            _slTriggeredAmounts,
            TriggerStatus.OPEN
        );
    }

    function getTriggerOrderInfo(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (TriggerOrder memory) {
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
        TriggerOrder storage order = triggerOrders[key];
        if (order.status != TriggerStatus.OPEN) {
            return false;
        }
        uint256 price = priceManager.getLastPrice(_token);
        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;
            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= price : price <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                }
            }
            if (closeAmountPercent != 0) {
                return true;
            }
            if (!tp) {
                break;
            }
        }
        return false;
    }

    function validateTriggerOrdersData(
        address _indexToken,
        bool _isLong,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) internal view returns (bool) {
        uint256 price = priceManager.getLastPrice(_indexToken);
        for (bool tp = true; ; tp = false) {
            uint256[] memory prices = tp ? _tpPrices : _slPrices;
            uint256[] memory triggeredAmounts = tp ? _tpTriggeredAmounts : _slTriggeredAmounts;
            bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
            for (uint256 i = 0; i < prices.length; ++i) {
                if (triggeredAmounts[i] == 0 && (price < prices[i]) != pricesAreUpperBounds) {
                    return false;
                }
            }
            if (!tp) {
                break;
            }
        }
        return true;
    }
}
