// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSD.sol";
import "./interfaces/ILiquidateVault.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IOrderVault.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus} from "./structs.sol";

contract PositionVault is Constants, ReentrancyGuard, IPositionVault {
    uint256 public lastPosId;
    IPriceManager private priceManager;
    ISettingsManager private settingsManager;
    IVault immutable private vault;
    ILiquidateVault private liquidateVault;
    IOrderVault private orderVault;
    IVaultUtils private vaultUtils;

    uint256 public openMarketQueueIndex;
    uint256[] public openMarketQueuePosIds;

    bool private isInitialized;
    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) private userPositionIds;
    mapping(uint256 => uint256) private userAliveIndexOf; //posId => index of userPositionIds[user], note that a position can only have a user

    event AddOrRemoveCollateral(uint256 posId, bool isPlus, uint256 amount, uint256 collateral, uint256 size);
    event AddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 acceptedPrice);
    event ExecuteAddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 feeUsd);
    event MarketOrderExecutionError(uint256 indexed posId, address indexed account, string err);

    modifier onlyVault() {
        require(msg.sender == address(vault) || msg.sender == address(liquidateVault), "Only vault");
        _;
    }

    constructor(address _vault, address _priceManager) {
        vault = IVault(_vault);
        priceManager = IPriceManager(_priceManager);
    }

    function addOrRemoveCollateral(
        address _account,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external override onlyVault {
        Position storage position = positions[_posId];
        require(_account == position.owner, "you are not allowed to add position");

        if (isPlus) {
            position.collateral += _amount;
            vaultUtils.validateMinLeverage(position.size, position.collateral);
            vault.takeVUSDIn(_account, position.refer, _amount, 0);
        } else {
            position.collateral -= _amount;
            vaultUtils.validateMaxLeverage(position.indexToken, position.size, position.collateral);
            vaultUtils.validateLiquidation(_posId, true);
            vault.takeVUSDOut(_account, position.refer, 0, _amount);
        }

        emit AddOrRemoveCollateral(_posId, isPlus, _amount, position.collateral, position.size);
    }

    function addPosition(
        address _account,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptedPrice
    ) external override onlyVault {
        Position memory position = positions[_posId];

        require(
            !settingsManager.isIncreasingPositionDisabled(position.indexToken),
            "current asset is disabled from increasing position"
        );
        require(position.size > 0, "Position not Open");
        require(_collateralDelta > MIN_COLLATERAL, "collateral is too small");
        require(_sizeDelta > MIN_COLLATERAL, "size is too small");
        require(_account == position.owner, "you are not allowed to add position");

        uint256 price = priceManager.getLastPrice(position.indexToken);
        uint256 fee = settingsManager.collectMarginFees(
            position.owner,
            position.indexToken,
            position.isLong,
            _sizeDelta
        );
        checkSlippage(position.isLong, _acceptedPrice, price);
        _increasePosition(
            _posId,
            position.owner,
            position.indexToken,
            position.isLong,
            price,
            _collateralDelta + fee,
            _sizeDelta
        );
        emit AddPosition(_posId, _collateralDelta, _sizeDelta, _acceptedPrice);
    }

    function decreasePosition(uint256 _posId, address _account, uint256 _sizeDelta) external override onlyVault {
        Position memory position = positions[_posId];
        uint256 price = priceManager.getLastPrice(position.indexToken);
        require(_account == position.owner, "Not allowed");
        _decreasePosition(_posId, price, _sizeDelta);
    }

    function executeOpenMarketOrders(
        uint256 numOfOrders
    ) external {
        require(settingsManager.isManager(msg.sender), "You are not allowed to trigger");
        _executeOpenMarketOrders(numOfOrders);
    }
    
    function initialize(
        IOrderVault _orderVault,
        ILiquidateVault _liquidateVault,
        ISettingsManager _settingsManager,
        IVaultUtils _vaultUtils
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_settingsManager)), "settingsManager invalid");
        require(Address.isContract(address(_liquidateVault)), "liquidateVault invalid");
        require(Address.isContract(address(_vaultUtils)), "vaultUtils address is invalid");
        liquidateVault = _liquidateVault;
        orderVault = _orderVault;
        settingsManager = _settingsManager;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    } 

    function newPositionOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external nonReentrant onlyVault {
        require(
            !settingsManager.isIncreasingPositionDisabled(_indexToken),
            "current asset is disabled from increasing position"
        );
        require(_params[2] > MIN_COLLATERAL, "collateral is too small");
        require(_params[3] > MIN_COLLATERAL, "size is too small");
        Position storage position = positions[lastPosId];
        position.owner = _account;
        position.refer = _refer;
        position.indexToken = _indexToken;
        position.isLong = _isLong;

        if (_orderType == OrderType.MARKET) {
            require(_params[0] > 0, "market price is invalid");
            orderVault.createNewOrder(lastPosId, POSITION_MARKET, _params, OrderStatus.PENDING);
            openMarketQueuePosIds.push(lastPosId);
        } else if (_orderType == OrderType.LIMIT) {
            require(_params[0] > 0, "limit price is invalid");
            orderVault.createNewOrder(lastPosId, POSITION_LIMIT, _params, OrderStatus.PENDING);
        } else if (_orderType == OrderType.STOP) {
            require(_params[1] > 0, "stop price is invalid");
            orderVault.createNewOrder(lastPosId, POSITION_STOP_MARKET, _params, OrderStatus.PENDING);
        } else if (_orderType == OrderType.STOP_LIMIT) {
            require(_params[0] > 0 && _params[1] > 0, "stop limit price is invalid");
            orderVault.createNewOrder(lastPosId, POSITION_STOP_LIMIT, _params, OrderStatus.PENDING);
        }

        lastPosId += 1;
    }

    function triggerForOpenOrders(address _account, uint256 _posId) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        Order memory order = orderVault.getOrder(_posId);
        require(
            position.owner == msg.sender || settingsManager.isManager(msg.sender),
            "You are not allowed to trigger"
        );
        uint8 statusFlag = vaultUtils.validateTrigger(position.indexToken, position.isLong, _posId);
        require(statusFlag == ORDER_FILLED, "trigger not ready");
        if (statusFlag == ORDER_FILLED) {
            if (order.positionType == POSITION_LIMIT) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    position.indexToken,
                    position.isLong,
                    order.size
                );
                uint256 price = priceManager.getLastPrice(position.indexToken);
                _increasePosition(
                    _posId,
                    _account,
                    position.indexToken,
                    position.isLong,
                    price,
                    order.collateral + fee,
                    order.size
                );
                orderVault.updateOrder(_posId, order.positionType, 0, 0, OrderStatus.FILLED);
                _addUserAlivePosition(_account, lastPosId);
            } else if (order.positionType == POSITION_STOP_MARKET) {
                uint256 fee = settingsManager.collectMarginFees(
                    _account,
                    position.indexToken,
                    position.isLong,
                    order.size
                );
                uint256 price = priceManager.getLastPrice(position.indexToken);
                _increasePosition(
                    _posId,
                    _account,
                    position.indexToken,
                    position.isLong,
                    price,
                    order.collateral + fee,
                    order.size
                );
                orderVault.updateOrder(_posId, order.positionType, 0, 0, OrderStatus.FILLED);
                _addUserAlivePosition(_account, lastPosId);
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                orderVault.updateOrder(_posId, POSITION_STOP_LIMIT, order.collateral, order.size, order.status);
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                _decreasePosition(_posId, order.stpPrice, order.size);
                orderVault.updateOrder(_posId, POSITION_MARKET, 0, 0, OrderStatus.FILLED);
            }
        }
    }
    
    function triggerForTPSL(uint256 _posId) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        require(
            position.owner == msg.sender || settingsManager.isManager(msg.sender),
            "You are not allowed to trigger"
        );
        (bool hitTrigger, uint256 triggerAmountPercent, uint256 triggerPrice) = orderVault
            .executeTriggerOrders(position.indexToken, position.isLong, _posId);
        require(hitTrigger, "trigger not ready");
        if (hitTrigger) {
            _decreasePosition(
                _posId,
                (position.size * (triggerAmountPercent)) / BASIS_POINTS_DIVISOR,
                triggerPrice
            );
        }
    }

    function executeOpenMarketOrder(uint256 _posId) public nonReentrant {
        require(settingsManager.isManager(msg.sender) || msg.sender == address(this), "You are not allowed to trigger");

        Position memory position = positions[_posId];
        Order memory order = orderVault.getOrder(_posId);
        require(order.size > 0, "order size is 0");
        require(order.positionType == POSITION_MARKET, "not market order");
        require(order.status == OrderStatus.PENDING, "not pending order");

        settingsManager.updateFunding(position.indexToken);

        uint256 fee = settingsManager.collectMarginFees(
            position.owner,
            position.indexToken,
            position.isLong,
            order.size
        );
        uint256 price = priceManager.getLastPrice(position.indexToken);
        checkSlippage(position.isLong, order.lmtPrice, price);

        _increasePosition(
            _posId,
            position.owner,
            position.indexToken,
            position.isLong,
            price,
            order.collateral + fee,
            order.size
        );
        orderVault.updateOrder(_posId, order.positionType, 0, 0, OrderStatus.FILLED);
        _addUserAlivePosition(position.owner, _posId);
    }

    function _decreasePosition(
        uint256 _posId,
        uint256 _price,
        uint256 _sizeDelta
    ) internal {
        Position storage position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        require(position.size > 0, "position size is zero");
        settingsManager.decreaseOpenInterest(position.indexToken, position.owner, position.isLong, _sizeDelta);
        (uint256 usdOut, uint256 usdOutFee) = _reduceCollateral(
            _posId,
            _price,
            _sizeDelta
        );
        if (usdOutFee <= usdOut) {
            vault.takeVUSDOut(position.owner, position.refer, usdOutFee, usdOut);
        } else if (usdOutFee != 0) {
            vault.distributeFee(position.owner, position.refer, usdOutFee);
        }
        if (position.size > _sizeDelta) {
            position.size -= _sizeDelta;
            vaultUtils.validateMinLeverage(position.size, position.collateral);
            vaultUtils.validateMaxLeverage(position.indexToken, position.size, position.collateral);
            vaultUtils.emitDecreasePositionEvent(position.owner, position.indexToken, position.isLong, _posId, _sizeDelta, usdOutFee);
        } else {
            vaultUtils.emitClosePositionEvent(position.owner, position.indexToken, position.isLong, _posId);
            _removeUserAlivePosition(position.owner, _posId);
            orderVault.removeOrder(_posId);
        }
    }

    function _executeOpenMarketOrders(uint256 numOfOrders) internal {
        uint256 index = openMarketQueueIndex;
        uint256 endIndex = index + numOfOrders;
        uint256 length = openMarketQueuePosIds.length;

        if (index >= length) return;
        if (endIndex > length) endIndex = length;

        while (index < endIndex) {
            uint256 posId = openMarketQueuePosIds[index];

            try this.executeOpenMarketOrder(posId) {} catch Error(string memory err) {
                orderVault.cancelMarketOrder(posId);
                emit MarketOrderExecutionError(posId, positions[posId].owner, err);
            } catch (bytes memory err) {
                orderVault.cancelMarketOrder(posId);
                emit MarketOrderExecutionError(posId, positions[posId].owner, string(err));
            }

            delete openMarketQueuePosIds[index];
            ++index;
        }

        openMarketQueueIndex = index;
    }

    function _increasePosition(
        uint256 _posId,
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _price,
        uint256 _amountIn,
        uint256 _sizeDelta
    ) internal {
        settingsManager.updateFunding(_indexToken);

        Position storage position = positions[_posId];
        if (position.size == 0) {
            position.averagePrice = _price;
            position.fundingIndex = settingsManager.fundingIndex(_indexToken);
        } else {
            position.averagePrice =
                (position.size * position.averagePrice + _sizeDelta * _price) /
                (position.size + _sizeDelta);
            position.fundingIndex =
                (int256(position.size) *
                    position.fundingIndex +
                    int256(_sizeDelta) *
                    settingsManager.fundingIndex(_indexToken)) /
                int256(position.size + _sizeDelta);
            position.accruedBorrowFee += settingsManager.getBorrowFee(position.size, position.lastIncreasedTime);
        }
        uint256 fee = settingsManager.collectMarginFees(_account, _indexToken, _isLong, _sizeDelta);
        uint256 _amountInAfterFee = _amountIn - fee;
        position.collateral += _amountInAfterFee;
        position.size += _sizeDelta;
        position.lastIncreasedTime = block.timestamp;
        position.lastPrice = _price;
        vault.accountDeltaAndFeeIntoTotalUSD(true, 0, fee);
        vault.takeVUSDIn(_account, position.refer, _amountIn, fee);
        settingsManager.validatePosition(_account, _indexToken, _isLong, position.size, position.collateral);
        vaultUtils.validateMaxLeverage(_indexToken, position.size, position.collateral);
        settingsManager.increaseOpenInterest(_indexToken, _account, _isLong, _sizeDelta);
        vaultUtils.emitIncreasePositionEvent(_account, _indexToken, _isLong, _posId, _amountIn, _sizeDelta, fee);
    }

    function _updatePnlAndUsdOut(
        uint256 _posId,
        bool hasProfit,
        uint256 adjustedDelta,
        uint256 _sizeDelta,
        uint256 fee
    ) internal returns (uint256) {
        Position storage position = positions[_posId];
        uint256 usdOut;
        // transfer profits
        if (adjustedDelta > 0) {
            if (hasProfit) {
                usdOut = adjustedDelta;
                position.realisedPnl += int256(adjustedDelta);
            } else {
                if (position.collateral < adjustedDelta) {
                    position.collateral = 0;
                } else {
                    position.collateral -= adjustedDelta;
                }
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
        vault.accountDeltaAndFeeIntoTotalUSD(!hasProfit, adjustedDelta, fee);
        // if the usdOut is more or equal than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        if (usdOut < fee) {
            if (position.collateral < fee) {
                position.collateral = 0;
            } else {
                position.collateral -= fee;
            }
        }
        return usdOut;
    }

    function _reduceCollateral(uint256 _posId, uint256 _price, uint256 _sizeDelta) internal returns (uint256, uint256) {
        Position storage position = positions[_posId];
        uint256 adjustedDelta;
        (bool _hasProfit, uint256 delta) = settingsManager.getPnl(
            position.indexToken,
            position.isLong,
            position.size,
            position.averagePrice,
            _price,
            position.lastIncreasedTime,
            position.accruedBorrowFee,
            position.fundingIndex
        );
        // get the proportional change in pnl
        adjustedDelta = (_sizeDelta * delta) / position.size;
        if (position.accruedBorrowFee > 0) {
            uint256 countedBorrowFee = (_sizeDelta * position.accruedBorrowFee) / position.size;
            if (position.accruedBorrowFee > countedBorrowFee) {
                position.accruedBorrowFee -= countedBorrowFee;
            } else {
                position.accruedBorrowFee = 0;
            }
        }

        uint256 fee = settingsManager.collectMarginFees(
            position.owner,
            position.indexToken,
            position.isLong,
            _sizeDelta
        );
        uint256 usdOut = _updatePnlAndUsdOut(_posId, _hasProfit, adjustedDelta, _sizeDelta, fee);
        vaultUtils.validateDecreasePosition(_posId, _price, true);
        return (usdOut, fee);
    }

    function getNumOfUnexecutedMarketOrders() external view returns (uint256) {
        return openMarketQueuePosIds.length - openMarketQueueIndex;
    }

    function getPosition(uint256 _posId) external view override returns (Position memory) {
        Position memory position = positions[_posId];
        return position;
    }

    function getVaultUSDBalance() external view override returns (uint256) {
        return vault.getVaultUSDBalance();
    }

    function _addUserAlivePosition(address _user, uint256 _posId) internal {
        userAliveIndexOf[_posId] = userPositionIds[_user].length;
        userPositionIds[_user].push(_posId);
    }
    function removeUserAlivePosition(address _user, uint256 _posId) external override {
        _removeUserAlivePosition(_user, _posId);
    }
    function _removeUserAlivePosition(address _user, uint256 _posId) internal {
        uint256 index = userAliveIndexOf[_posId];
        uint256 lastIndex = userPositionIds[_user].length - 1;
        uint256 lastId = userPositionIds[_user][lastIndex];
        delete positions[_posId];
        userAliveIndexOf[lastId] = index;
        delete userAliveIndexOf[_posId];

        userPositionIds[_user][index] = lastId;
        userPositionIds[_user].pop();
    }

    function getUserPositionIds(address _account) external override view returns (uint256[] memory) {
        return userPositionIds[_account];
    }

    function removePosition(uint256 _posId) external {
        delete userAliveIndexOf[_posId];
    }
}
