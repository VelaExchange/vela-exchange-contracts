// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSD.sol";
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

    uint256 public openMarketQueueIndex;
    uint256[] public openMarketQueuePosIds;
    // uint256 public addMarketQueueIndex;
    // uint256[] public addMarketQueuePosIds;
    // uint256 public closeMarketQueueIndex;
    // uint256[] public closeMarketQueuePosIds;

    bool private isInitialized;
    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) private userPositionIds;
    mapping(uint256 => uint256) private userAliveIndexOf; //posId => index of userPositionIds[user], note that a position can only have a user
    mapping(uint256 => Order) public orders;
    mapping(uint256 => address) public liquidateRegistrant;
    mapping(uint256 => uint256) public liquidateRegisterTime;

    event AddOrRemoveCollateral(uint256 posId, bool isPlus, uint256 amount, uint256 collateral, uint256 size);
    event AddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 acceptedPrice);
    event AddTrailingStop(uint256 posId, uint256[] data);
    event ExecuteAddPosition(uint256 posId, uint256 collateral, uint256 size, uint256 feeUsd);
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
    event UpdateTrailingStop(uint256 posId, uint256 stpPrice);
    event RegisterLiquidation(
        address account,
        address token,
        bool isLong,
        uint256 posId,
        address caller,
        uint256 marginFees
    );
    event MarketOrderExecutionError(uint256 indexed posId, address indexed account, string err);

    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault");
        _;
    }

    constructor() {}

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
            position.owner,
            position.indexToken,
            _collateralDelta + fee,
            _sizeDelta,
            _posId,
            price,
            position.isLong
        );
        emit AddPosition(_posId, _collateralDelta, _sizeDelta, _acceptedPrice);
    }

    function addTrailingStop(address _account, uint256 _posId, uint256[] memory _params) external override onlyVault {
        Order storage order = orders[_posId];
        require(_account == positions[_posId].owner, "you are not allowed to add trailing stop");
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
        require(_account == positions[_posId].owner, "You are not allowed to cancel");
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

    function decreasePosition(address _account, uint256 _sizeDelta, uint256 _posId) external override onlyVault {
        Position memory position = positions[_posId];
        uint256 price = priceManager.getLastPrice(position.indexToken);
        require(_account == position.owner, "Not allowed");
        _decreasePosition(_account, position.indexToken, _sizeDelta, price, position.isLong, _posId);
    }

    function initialize(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager,
        ITriggerOrderManager _triggerOrderManager,
        IVault _vault,
        IVaultUtils _vaultUtils
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "priceManager invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager invalid");
        require(Address.isContract(address(_triggerOrderManager)), "triggerOrderManager address is invalid");
        require(Address.isContract(address(_vault)), "vault invalid");
        require(Address.isContract(address(_vaultUtils)), "vaultUtils address is invalid");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        triggerOrderManager = _triggerOrderManager;
        vault = _vault;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    }

    function registerLiquidatePosition(uint256 _posId) external nonReentrant {
        require(liquidateRegistrant[_posId] == address(0), "not the firstCaller");

        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(_posId, false);
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");

        liquidateRegistrant[_posId] = msg.sender;
        liquidateRegisterTime[_posId] = block.timestamp;
        emit RegisterLiquidation(position.owner, position.indexToken, position.isLong, _posId, msg.sender, marginFees);
    }

    function liquidatePosition(uint256 _posId) external nonReentrant {
        require(
            settingsManager.isManager(msg.sender) ||
                (msg.sender == liquidateRegistrant[_posId] &&
                    liquidateRegisterTime[_posId] + settingsManager.liquidationPendingTime() <= block.timestamp),
            "not manager or not allowed before pendingTime"
        );

        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(_posId, false);
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");

        (uint32 teamPercent, uint32 firstCallerPercent, uint32 resolverPercent) = settingsManager.bountyPercent();
        uint256 bountyTeam = (marginFees * teamPercent) / BASIS_POINTS_DIVISOR;
        //uint256 bounty = bountyTeam; //this can be used in log, leave to future
        vault.transferBounty(settingsManager.feeManager(), bountyTeam);
        if (msg.sender == liquidateRegistrant[_posId] || liquidateRegistrant[_posId] == address(0)) {
            // same address to receive firstCaller bounty and resolver bounty
            uint256 bountyCaller = (marginFees * (firstCallerPercent + resolverPercent)) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(msg.sender, bountyCaller);
            //bounty += bountyCaller;
        } else {
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
            vaultUtils.emitLiquidatePositionEvent(
                position.owner,
                position.indexToken,
                position.isLong,
                _posId,
                marginFees
            );
            _decreasePosition(position.owner, position.indexToken, position.size, price, position.isLong, _posId);
            return;
        }
        vault.accountDeltaAndFeeIntoTotalUSD(true, 0, marginFees);
        settingsManager.decreaseOpenInterest(position.indexToken, position.owner, position.isLong, position.size);
        vaultUtils.emitLiquidatePositionEvent(position.owner, position.indexToken, position.isLong, _posId, marginFees);
        delete positions[_posId];
        _removeUserAlivePosition(position.owner, _posId);
        delete orders[_posId];
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
        require(
            !settingsManager.isIncreasingPositionDisabled(_indexToken),
            "current asset is disabled from increasing position"
        );
        require(_params[2] > MIN_COLLATERAL, "collateral is too small");
        require(_params[3] > MIN_COLLATERAL, "size is too small");

        Order storage order = orders[lastPosId];
        Position storage position = positions[lastPosId];

        order.collateral = _params[2];
        order.size = _params[3];
        position.owner = _account;
        position.refer = _refer;
        position.indexToken = _indexToken;
        position.isLong = _isLong;

        if (_orderType == OrderType.MARKET) {
            require(_params[0] > 0, "market price is invalid");

            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_MARKET;
            order.lmtPrice = _params[0];

            openMarketQueuePosIds.push(lastPosId);
        } else if (_orderType == OrderType.LIMIT) {
            require(_params[0] > 0, "limit price is invalid");

            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_LIMIT;
            order.lmtPrice = _params[0];
        } else if (_orderType == OrderType.STOP) {
            require(_params[1] > 0, "stop price is invalid");

            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_MARKET;
            order.stpPrice = _params[1];
        } else if (_orderType == OrderType.STOP_LIMIT) {
            require(_params[0] > 0 && _params[1] > 0, "stop limit price is invalid");

            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_LIMIT;
            order.lmtPrice = _params[0];
            order.stpPrice = _params[1];
        }

        lastPosId += 1;
        emit NewOrder(_account, _indexToken, _isLong, lastPosId - 1, order.positionType, order.status, _params);
    }

    function executeOpenMarketOrder(uint256 _posId) public nonReentrant {
        require(settingsManager.isManager(msg.sender) || msg.sender == address(this), "You are not allowed to trigger");

        Position memory position = positions[_posId];
        Order storage order = orders[_posId];
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
            position.owner,
            position.indexToken,
            order.collateral + fee,
            order.size,
            _posId,
            price,
            position.isLong
        );

        order.collateral = 0;
        order.size = 0;
        order.status = OrderStatus.FILLED;
        _addUserAlivePosition(position.owner, _posId);

        emit UpdateOrder(_posId, order.positionType, order.status);
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
                cancelMarketOrder(posId);
                emit MarketOrderExecutionError(posId, positions[posId].owner, err);
            } catch (bytes memory err) {
                cancelMarketOrder(posId);
                emit MarketOrderExecutionError(posId, positions[posId].owner, string(err));
            }

            delete openMarketQueuePosIds[index];
            ++index;
        }

        openMarketQueueIndex = index;
    }

    function executeOpenMarketOrders(
        uint256 numOfOrders
    ) external {
        require(settingsManager.isManager(msg.sender), "You are not allowed to trigger");
        _executeOpenMarketOrders(numOfOrders);
    }

    function cancelMarketOrder(uint256 _posId) internal {
        Order storage order = orders[_posId];
        order.status = OrderStatus.CANCELED;
        emit UpdateOrder(_posId, order.positionType, order.status);
    }

    function getNumOfUnexecutedMarketOrders() external view returns (uint256) {
        return openMarketQueuePosIds.length - openMarketQueueIndex;
    }

    function triggerForOpenOrders(address _account, uint256 _posId) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        Order storage order = orders[_posId];
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
                    _account,
                    position.indexToken,
                    order.collateral + fee,
                    order.size,
                    _posId,
                    price,
                    position.isLong
                );
                order.collateral = 0;
                order.size = 0;
                order.status = OrderStatus.FILLED;
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
                    _account,
                    position.indexToken,
                    order.collateral + fee,
                    order.size,
                    _posId,
                    price,
                    position.isLong
                );
                order.collateral = 0;
                order.size = 0;
                order.status = OrderStatus.FILLED;
                _addUserAlivePosition(_account, lastPosId);
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

    function triggerForTPSL(address _account, uint256 _posId) external nonReentrant {
        Position memory position = positions[_posId];
        settingsManager.updateFunding(position.indexToken);
        Order storage order = orders[_posId];
        require(
            position.owner == msg.sender || settingsManager.isManager(msg.sender),
            "You are not allowed to trigger"
        );
        (bool hitTrigger, uint256 triggerAmountPercent, uint256 triggerPrice) = triggerOrderManager
            .executeTriggerOrders(position.indexToken, position.isLong, _posId);
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

    function updateTrailingStop(uint256 _posId) external nonReentrant {
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

    function _decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _price,
        bool _isLong,
        uint256 _posId
    ) internal {
        settingsManager.updateFunding(_indexToken);
        Position storage position = positions[_posId];
        require(position.size > 0, "position size is zero");
        settingsManager.decreaseOpenInterest(_indexToken, _account, _isLong, _sizeDelta);
        (uint256 usdOut, uint256 usdOutFee) = _reduceCollateral(
            _account,
            _indexToken,
            _sizeDelta,
            _price,
            _isLong,
            _posId
        );
        if (position.size != _sizeDelta) {
            position.size -= _sizeDelta;
            vaultUtils.validateMinLeverage(position.size, position.collateral);
            vaultUtils.validateMaxLeverage(_indexToken, position.size, position.collateral);
            vaultUtils.emitDecreasePositionEvent(_account, _indexToken, _isLong, _posId, _sizeDelta, usdOutFee);
        } else {
            vaultUtils.emitClosePositionEvent(_account, _indexToken, _isLong, _posId);
            delete positions[_posId];
            _removeUserAlivePosition(_account, _posId);
            delete orders[_posId];
        }
        if (usdOutFee <= usdOut) {
            vault.takeVUSDOut(_account, position.refer, usdOutFee, usdOut);
        } else if (usdOutFee != 0) {
            vault.distributeFee(_account, position.refer, usdOutFee);
        }
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
            position.accruedBorrowFee += settingsManager.getBorrowFee(position.indexToken, position.size, position.lastIncreasedTime);
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
            (bool _hasProfit, uint256 delta) = settingsManager.getPnl(
                _indexToken,
                _isLong,
                position.size,
                position.averagePrice,
                _price,
                position.lastIncreasedTime,
                position.accruedBorrowFee,
                position.fundingIndex
            );
            hasProfit = _hasProfit;
            // get the proportional change in pnl
            adjustedDelta = (_sizeDelta * delta) / position.size;

            uint256 countedBorrowFee = (_sizeDelta * position.accruedBorrowFee) / position.size;
            if (position.accruedBorrowFee > countedBorrowFee) {
                position.accruedBorrowFee -= countedBorrowFee;
            } else {
                position.accruedBorrowFee = 0;
            }
        }

        uint256 usdOut;
        // transfer profits
        uint256 fee = settingsManager.collectMarginFees(_account, _indexToken, _isLong, _sizeDelta);
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
        vault.accountDeltaAndFeeIntoTotalUSD(!hasProfit, adjustedDelta, fee);
        // if the usdOut is more or equal than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        if (usdOut < fee) {
            position.collateral -= fee;
        }
        vaultUtils.validateDecreasePosition(_posId, _price, true);
        return (usdOut, fee);
    }

    function getPosition(uint256 _posId) external view override returns (Position memory, Order memory) {
        Position memory position = positions[_posId];
        Order memory order = orders[_posId];
        return (position, order);
    }

    function getVaultUSDBalance() external view override returns (uint256) {
        return vault.getVaultUSDBalance();
    }

    function getUserAlivePositions(
        address _user
    ) public view returns (uint256[] memory, Position[] memory, Order[] memory) {
        uint256 length = userPositionIds[_user].length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        uint256[] storage posIds = userPositionIds[_user];
        for (uint i; i < length; i++) {
            uint256 posId = posIds[i];
            positions_[i] = positions[posId];
            orders_[i] = orders[posId];
        }
        return (userPositionIds[_user], positions_, orders_);
    }

    function _addUserAlivePosition(address _user, uint256 _posId) internal {
        userAliveIndexOf[_posId] = userPositionIds[_user].length;
        userPositionIds[_user].push(_posId);
    }

    function _removeUserAlivePosition(address _user, uint256 _posId) internal {
        uint256 index = userAliveIndexOf[_posId];
        uint256 lastIndex = userPositionIds[_user].length - 1;
        uint256 lastId = userPositionIds[_user][lastIndex];

        userAliveIndexOf[lastId] = index;
        delete userAliveIndexOf[_posId];

        userPositionIds[_user][index] = lastId;
        userPositionIds[_user].pop();
    }
}
