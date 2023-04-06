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
import "./interfaces/ITriggerOrderManager.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus} from "./structs.sol";

contract OrderVault is Constants, ReentrancyGuard, IOrderVault {
    uint256 public lastPosId;
    IPriceManager private priceManager;
    IPositionVault private positionVault;
    ISettingsManager private settingsManager;
    IVault private vault;
    IVaultUtils private vaultUtils;

    uint256 public openMarketQueueIndex;
    uint256[] public openMarketQueuePosIds;

    bool private isInitialized;
    mapping(uint256 => Order) public orders;
    event AddTrailingStop(uint256 posId, uint256[] data);
    event ExecuteAddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 feeUsd);
    event NewOrder(
        uint256 posId,
        uint256 positionType,
        OrderStatus orderStatus,
        uint256[] triggerData
    );
    event UpdateOrder(uint256 posId, uint256 positionType, OrderStatus orderStatus);
    event UpdateTrailingStop(uint256 posId, uint256 stpPrice);

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

    function updateOrder(uint256 _posId, uint256 _positionType, uint256 _collateral, uint256 _size, OrderStatus _status) public override onlyPositionVault {
        Order storage order = orders[_posId];
        order.positionType = _positionType;
        order.collateral = _collateral;
        order.size = _size;
        order.status = _status;
        emit UpdateOrder(_posId, order.positionType, order.status);
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

    function cancelMarketOrder(uint256 _posId) public override onlyPositionVault {
        Order storage order = orders[_posId];
        order.status = OrderStatus.CANCELED;
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

    function removeOrder(uint256 _posId) external override onlyPositionVault {
        delete orders[_posId];
    }
}
