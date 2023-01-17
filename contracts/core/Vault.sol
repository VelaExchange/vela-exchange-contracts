// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSDC.sol";
import "../staking/interfaces/ITokenFarm.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/ITriggerOrderManager.sol";
import "./interfaces/IPriceManager.sol";

contract Vault is Constants, ReentrancyGuard, Ownable, IVault {
    using SafeERC20 for IERC20;

    uint256 public totalVLP;
    uint256 public totalUSDC;

    IVaultUtils private vaultUtils;
    ISettingsManager private settingsManager;
    ITriggerOrderManager private triggerOrderManager;
    IPriceManager private priceManager;
    ITokenFarm private immutable tokenFarm;
    address private immutable vlp;
    address private immutable vUSDC;
    bool private isInitialized;

    mapping(address => mapping(bool => uint256)) public override poolAmounts;
    mapping(address => mapping(bool => uint256))
        public
        override reservedAmounts;
    uint256 public lastPosId;
    mapping(address => uint256) public lastStakedAt;
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
    event AddPosition(
        bytes32 indexed key,
        bool confirmDelayStatus,
        uint256 collateral,
        uint256 size
    );
    event AddTrailingStop(bytes32 key, uint256[] data);
    event ConfirmDelayTransaction(
        bytes32 indexed key,
        bool confirmDelayStatus,
        uint256 collateral,
        uint256 size,
        uint256 feeUsd
    );
    event Deposit(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event DecreasePoolAmount(
        address indexed token,
        bool isLong,
        uint256 amount
    );
    event DecreaseReservedAmount(
        address indexed token,
        bool isLong,
        uint256 amount
    );
    event IncreasePoolAmount(
        address indexed token,
        bool isLong,
        uint256 amount
    );
    event IncreaseReservedAmount(
        address indexed token,
        bool isLong,
        uint256 amount
    );
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
    event Stake(
        address indexed account,
        address token,
        uint256 amount,
        uint256 mintAmount
    );
    event Unstake(
        address indexed account,
        address token,
        uint256 vlpAmount,
        uint256 amountOut
    );
    event UpdateOrder(
        bytes32 key,
        uint256 positionType,
        OrderStatus orderStatus
    );
    event UpdateTrailingStop(bytes32 key, uint256 stpPrice);
    event Withdraw(
        address indexed account,
        address indexed token,
        uint256 amount
    );

    constructor(address _vlp, address _vUSDC, address _tokenFarm) {
        vlp = _vlp;
        vUSDC = _vUSDC;
        tokenFarm = ITokenFarm(_tokenFarm);
    }

    function addOrRemoveCollateral(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        Position storage position = positions[key];
        if (isPlus) {
            position.collateral += _amount;
            vaultUtils.validateSizeCollateralAmount(
                position.size,
                position.collateral
            );
            position.reserveAmount += _amount;
            vaultUtils.takeVUSDIn(msg.sender, position.refer, _amount, 0);
            settingsManager.decreaseBorrowedUsd(
                _indexToken,
                msg.sender,
                _isLong,
                _amount
            );
            _increasePoolAmount(_indexToken, _isLong, _amount);
        } else {
            position.collateral -= _amount;
            vaultUtils.validateSizeCollateralAmount(
                position.size,
                position.collateral
            );
            vaultUtils.validateLiquidation(
                msg.sender,
                _indexToken,
                _isLong,
                _posId,
                true
            );
            position.reserveAmount -= _amount;
            vaultUtils.takeVUSDOut(msg.sender, position.refer, 0, _amount);
            settingsManager.increaseBorrowedUsd(
                _indexToken,
                msg.sender,
                _isLong,
                _amount
            );
            _decreasePoolAmount(_indexToken, _isLong, _amount);
        }
        emit AddOrRemoveCollateral(
            key,
            isPlus,
            _amount,
            position.reserveAmount,
            position.collateral,
            position.size
        );
    }

    function addPosition(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        ConfirmInfo storage confirm = confirms[key];
        confirm.delayStartTime = block.timestamp;
        confirm.confirmDelayStatus = true;
        confirm.pendingDelayCollateral = _collateralDelta;
        confirm.pendingDelaySize = _sizeDelta;
        emit AddPosition(
            key,
            confirm.confirmDelayStatus,
            _collateralDelta,
            _sizeDelta
        );
    }

    function addTrailingStop(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory triggerPrices
    ) external nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        OrderInfo storage order = orders[key];
        vaultUtils.validateTrailingStopInputData(
            msg.sender,
            _indexToken,
            _isLong,
            _posId,
            triggerPrices
        );
        order.pendingCollateral = triggerPrices[0];
        order.pendingSize = triggerPrices[1];
        order.status = OrderStatus.PENDING;
        order.positionType = POSITION_TRAILING_STOP;
        order.stepType = triggerPrices[2];
        order.stpPrice = triggerPrices[3];
        order.stepAmount = triggerPrices[4];
        emit AddTrailingStop(key, triggerPrices);
    }

    function cancelPendingOrder(
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
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
        require(
            position.owner == msg.sender ||
                settingsManager.isManager(msg.sender),
            "not allowed"
        );
        ConfirmInfo storage confirm = confirms[key];
        vaultUtils.validateConfirmDelay(
            _account,
            _indexToken,
            _isLong,
            _posId,
            true
        );
        uint256 fee = _collectMarginFees(
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
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external override nonReentrant {
        _decreasePosition(msg.sender, _indexToken, _sizeDelta, _isLong, _posId);
    }

    function deposit(
        address _account,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        uint256 collateralDeltaUsd = priceManager.tokenToUsd(_token, _amount);
        require(settingsManager.isDeposit(_token), "deposit not allowed");
        require(
            (settingsManager.checkDelegation(_account, msg.sender)) &&
                _amount > 0,
            "Vault: zero amount not allowed for deposit"
        );
        _transferIn(_account, _token, _amount);
        uint256 fee = (collateralDeltaUsd * settingsManager.depositFee()) /
            BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = collateralDeltaUsd - fee;
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        IVUSDC(vUSDC).mint(_account, afterFeeAmount);
        vaultUtils.distributeFee(_account, ZERO_ADDRESS, fee);
        emit Deposit(_account, _token, _amount);
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
        (uint256 liquidationState, uint256 marginFees) = vaultUtils
            .validateLiquidation(_account, _indexToken, _isLong, _posId, false);
        require(
            liquidationState != LIQUIDATE_NONE_EXCEED,
            "not exceed or allowed"
        );
        if (liquidationState == LIQUIDATE_THRESHOLD_EXCEED) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(
                _account,
                _indexToken,
                position.size,
                _isLong,
                _posId
            );
            return;
        }
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, marginFees);
        uint256 bounty = (marginFees * settingsManager.bountyPercent()) /
            BASIS_POINTS_DIVISOR;
        vaultUtils.transferBounty(msg.sender, bounty);
        totalUSDC -= bounty;
        settingsManager.decreaseBorrowedUsd(
            _indexToken,
            _account,
            _isLong,
            position.size - position.collateral
        );
        _decreasePoolAmount(_indexToken, _isLong, marginFees);
        vaultUtils.emitLiquidatePositionEvent(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        delete positions[key];
        // pay the fee receive using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
    }

    function newPositionOrder(
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory triggerPrices,
        address _refer
    ) external nonReentrant {
        bytes32 key = _getPositionKey(
            msg.sender,
            _indexToken,
            _isLong,
            lastPosId
        );
        OrderInfo storage order = orders[key];
        vaultUtils.validatePosData(
            _isLong,
            _indexToken,
            _orderType,
            triggerPrices,
            true
        );
        order.pendingCollateral = triggerPrices[2];
        order.pendingSize = triggerPrices[3];
        if (_orderType == OrderType.MARKET) {
            order.positionType = POSITION_MARKET;
            uint256 fee = _collectMarginFees(
                msg.sender,
                _indexToken,
                _isLong,
                order.pendingSize,
                positions[key].size,
                positions[key].entryFundingRate
            );
            _increasePosition(
                msg.sender,
                _indexToken,
                triggerPrices[2] + fee,
                order.pendingSize,
                lastPosId,
                _isLong,
                _refer
            );
            order.pendingCollateral = 0;
            order.pendingSize = 0;
            order.status = OrderStatus.FILLED;
        } else if (_orderType == OrderType.LIMIT) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_LIMIT;
            order.lmtPrice = triggerPrices[0];
        } else if (_orderType == OrderType.STOP) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_MARKET;
            order.stpPrice = triggerPrices[1];
        } else if (_orderType == OrderType.STOP_LIMIT) {
            order.status = OrderStatus.PENDING;
            order.positionType = POSITION_STOP_LIMIT;
            order.lmtPrice = triggerPrices[0];
            order.stpPrice = triggerPrices[1];
        }
        lastPosId += 1;
        emit NewOrder(
            key,
            msg.sender,
            _indexToken,
            _isLong,
            lastPosId - 1,
            order.positionType,
            order.status,
            triggerPrices
        );
    }

    function setVaultSettings(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager,
        ITriggerOrderManager _triggerOrderManager,
        IVaultUtils _vaultUtils
    ) external onlyOwner {
        require(!isInitialized, "Not initialized");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        triggerOrderManager = _triggerOrderManager;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    }

    function stake(
        address _account,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        require(settingsManager.isStaking(_token), "stake not allowed");
        require(
            (settingsManager.checkDelegation(_account, msg.sender)) &&
                _amount > 0,
            "Vault: zero amount not allowed for stake"
        );
        uint256 usdAmount = priceManager.tokenToUsd(_token, _amount);
        _transferIn(_account, _token, _amount);
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee()) /
            BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        uint256 mintAmount;
        if (totalVLP == 0) {
            mintAmount =
                (usdAmountAfterFee * DEFAULT_VLP_PRICE * (10 ** VLP_DECIMALS)) /
                (PRICE_PRECISION * BASIS_POINTS_DIVISOR);
        } else {
            mintAmount = (usdAmountAfterFee * totalVLP) / totalUSDC;
        }
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, usdAmountFee);
        vaultUtils.distributeFee(_account, ZERO_ADDRESS, usdAmountFee);
        IMintable(vlp).mint(_account, mintAmount);
        lastStakedAt[_account] = block.timestamp;
        totalVLP += mintAmount;
        totalUSDC += usdAmountAfterFee;
        emit Stake(_account, _token, _amount, mintAmount);
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
        uint8 statusFlag = vaultUtils.validateTrigger(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        (bool hitTrigger, uint256 triggerAmountPercent) = triggerOrderManager
            .executeTriggerOrders(_account, _indexToken, _isLong, _posId);
        require(
            (statusFlag == ORDER_FILLED || hitTrigger) &&
                (position.owner == msg.sender ||
                    settingsManager.isManager(msg.sender)),
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
                uint256 fee = _collectMarginFees(
                    _account,
                    _indexToken,
                    _isLong,
                    order.pendingSize,
                    positions[key].size,
                    positions[key].entryFundingRate
                );
                _increasePosition(
                    _account,
                    _indexToken,
                    order.pendingCollateral + fee,
                    order.pendingSize,
                    _posId,
                    _isLong,
                    ZERO_ADDRESS
                );
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_MARKET) {
                uint256 fee = _collectMarginFees(
                    _account,
                    _indexToken,
                    _isLong,
                    order.pendingSize,
                    positions[key].size,
                    positions[key].entryFundingRate
                );
                // checkSlippage(..) should be here, because it's a kind of market order, even though it's not instantly executed.
                //      the ability to cancel this by the user mitigates risks of unexpected price change, but slippage checks are more firm
                _increasePosition(
                    _account,
                    _indexToken,
                    order.pendingCollateral + fee,
                    order.pendingSize,
                    _posId,
                    _isLong,
                    ZERO_ADDRESS
                );
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            } else if (order.positionType == POSITION_STOP_LIMIT) {
                order.positionType = POSITION_LIMIT;
            } else if (order.positionType == POSITION_TRAILING_STOP) {
                _decreasePosition(
                    _account,
                    _indexToken,
                    order.pendingSize,
                    _isLong,
                    _posId
                );
                order.positionType = POSITION_MARKET;
                order.pendingCollateral = 0;
                order.pendingSize = 0;
                order.status = OrderStatus.FILLED;
            }
        }
        emit UpdateOrder(key, order.positionType, order.status);
    }

    function unstake(
        address _tokenOut,
        uint256 _vlpAmount,
        address _receiver
    ) external nonReentrant {
        require(settingsManager.isStaking(_tokenOut), "unstake not allowed");
        require(
            _vlpAmount > 0 && _vlpAmount <= totalVLP,
            "Vault: zero amount not allowed and cant exceed totalVLP"
        );
        require(
            lastStakedAt[msg.sender] + settingsManager.cooldownDuration() <=
                block.timestamp,
            "cooldown duration not yet passed"
        );
        IMintable(vlp).burn(msg.sender, _vlpAmount);
        uint256 usdAmount = (_vlpAmount * totalUSDC) / totalVLP;
        totalVLP -= _vlpAmount;
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee()) /
            BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        totalUSDC -= usdAmount;
        uint256 amountOut = priceManager.usdToToken(
            _tokenOut,
            usdAmountAfterFee
        );
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, usdAmountFee);
        vaultUtils.distributeFee(msg.sender, ZERO_ADDRESS, usdAmountFee);
        _transferOut(_tokenOut, amountOut, _receiver);
        emit Unstake(msg.sender, _tokenOut, _vlpAmount, amountOut);
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
        require(
            position.owner == msg.sender ||
                settingsManager.isManager(msg.sender),
            "updateTStop not allowed"
        );
        vaultUtils.validateTrailingStopPrice(
            _account,
            _indexToken,
            _isLong,
            _posId
        );
        if (_isLong) {
            order.stpPrice = order.stepType == 0
                ? price - order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR - order.stepAmount)) /
                    BASIS_POINTS_DIVISOR;
        } else {
            order.stpPrice = order.stepType == 0
                ? price + order.stepAmount
                : (price * (BASIS_POINTS_DIVISOR + order.stepAmount)) /
                    BASIS_POINTS_DIVISOR;
        }
        emit UpdateTrailingStop(key, order.stpPrice);
    }

    function withdraw(
        address _token,
        address _account,
        uint256 _amount
    ) external nonReentrant {
        uint256 fee = (_amount * settingsManager.depositFee()) /
            BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = _amount - fee;
        uint256 collateralDelta = priceManager.usdToToken(
            _token,
            afterFeeAmount
        );
        require(settingsManager.isDeposit(_token), "withdraw not allowed");
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        IVUSDC(vUSDC).burn(address(msg.sender), _amount);
        vaultUtils.distributeFee(_account, ZERO_ADDRESS, fee);
        _transferOut(_token, collateralDelta, _account);
        emit Withdraw(address(msg.sender), _token, collateralDelta);
    }

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    )
        external
        view
        override
        returns (Position memory, OrderInfo memory, ConfirmInfo memory)
    {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position memory position = positions[key];
        OrderInfo memory order = orders[key];
        ConfirmInfo memory confirm = confirms[key];
        return (position, order, confirm);
    }

    function getVLPPrice() external view returns (uint256) {
        if (totalVLP == 0) {
            return DEFAULT_VLP_PRICE;
        } else {
            return
                (BASIS_POINTS_DIVISOR * (10 ** VLP_DECIMALS) * totalUSDC) /
                (totalVLP * PRICE_PRECISION);
        }
    }

    function _collectMarginFees(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) internal view returns (uint256) {
        uint256 feeUsd = settingsManager.getPositionFee(
            _indexToken,
            _isLong,
            _sizeDelta
        );

        feeUsd += settingsManager.getFundingFee(
            _indexToken,
            _isLong,
            _size,
            _entryFundingRate
        );
        return
            (feeUsd * tokenFarm.getTier(STAKING_PID_FOR_CHARGE_FEE, _account)) /
            BASIS_POINTS_DIVISOR;
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
        require(
            position.size > 0,
            "position size should be greather than zero"
        );
        settingsManager.decreaseBorrowedUsd(
            _indexToken,
            _account,
            _isLong,
            (_sizeDelta * (position.size - position.collateral)) / position.size
        );
        _decreaseReservedAmount(_indexToken, _isLong, _sizeDelta);
        position.reserveAmount -=
            (position.reserveAmount * _sizeDelta) /
            position.size;
        (uint256 usdOut, uint256 usdOutFee) = _reduceCollateral(
            _account,
            _indexToken,
            _sizeDelta,
            _isLong,
            _posId
        );
        if (position.size != _sizeDelta) {
            position.entryFundingRate = settingsManager.cumulativeFundingRates(
                _indexToken,
                _isLong
            );
            position.size -= _sizeDelta;
            vaultUtils.validateSizeCollateralAmount(
                position.size,
                position.collateral
            );
            vaultUtils.validateLiquidation(
                _account,
                _indexToken,
                _isLong,
                _posId,
                true
            );
            vaultUtils.emitDecreasePositionEvent(
                _account,
                _indexToken,
                _isLong,
                _posId,
                _sizeDelta,
                usdOutFee
            );
        } else {
            vaultUtils.emitClosePositionEvent(
                _account,
                _indexToken,
                _isLong,
                _posId
            );
            delete positions[key];
        }
        if (usdOutFee <= usdOut) {
            if (usdOutFee != usdOut) {
                _decreasePoolAmount(_indexToken, _isLong, usdOut - usdOutFee);
            }
            vaultUtils.takeVUSDOut(_account, _refer, usdOutFee, usdOut);
        } else if (usdOutFee != 0) {
            vaultUtils.distributeFee(_account, _refer, usdOutFee);
        }
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
        position.owner = _account;
        position.refer = _refer;
        uint256 fee = _collectMarginFees(
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
        position.entryFundingRate = settingsManager.cumulativeFundingRates(
            _indexToken,
            _isLong
        );
        position.size += _sizeDelta;
        position.lastIncreasedTime = block.timestamp;
        position.lastPrice = price;
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        vaultUtils.takeVUSDIn(_account, _refer, _amountIn, fee);
        settingsManager.validatePosition(
            _account,
            _indexToken,
            _isLong,
            position.size,
            position.collateral
        );
        vaultUtils.validateLiquidation(
            _account,
            _indexToken,
            _isLong,
            _posId,
            true
        );
        settingsManager.increaseBorrowedUsd(
            _indexToken,
            _account,
            _isLong,
            _sizeDelta - _amountInAfterFee
        );
        _increaseReservedAmount(_indexToken, _isLong, _sizeDelta);
        _increasePoolAmount(_indexToken, _isLong, _amountInAfterFee);
        vaultUtils.emitIncreasePositionEvent(
            _account,
            _indexToken,
            _isLong,
            _posId,
            _amountIn,
            _sizeDelta,
            fee
        );
    }

    function _accountDeltaAndFeeIntoTotalUSDC(
        bool _hasProfit,
        uint256 _adjustDelta,
        uint256 _fee
    ) internal {
        if (_adjustDelta != 0) {
            uint256 _feeRewardOnDelta = (_adjustDelta *
                settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            if (_hasProfit) {
                totalUSDC += _feeRewardOnDelta;
            } else {
                require(totalUSDC >= _feeRewardOnDelta, "exceeded VLP bottom");
                totalUSDC -= _feeRewardOnDelta;
            }
        }
        totalUSDC +=
            (_fee * settingsManager.feeRewardBasisPoints()) /
            BASIS_POINTS_DIVISOR;
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
        uint256 fee = _collectMarginFees(
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
            uint256 _collateralDelta = (position.collateral * _sizeDelta) /
                position.size;
            usdOut += _collateralDelta;
            position.collateral -= _collateralDelta;
        }
        _accountDeltaAndFeeIntoTotalUSDC(hasProfit, adjustedDelta, fee);
        // if the usdOut is more or equal than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        if (usdOut < fee) {
            position.collateral -= fee;
        }
        vaultUtils.validateDecreasePosition(
            _account,
            _indexToken,
            _isLong,
            _posId,
            true
        );
        return (usdOut, fee);
    }

    function _transferIn(
        address _account,
        address _token,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(_account, address(this), _amount);
    }

    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) internal {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function _decreasePoolAmount(
        address _indexToken,
        bool _isLong,
        uint256 _amount
    ) private {
        require(
            poolAmounts[_indexToken][_isLong] >= _amount,
            "Vault: poolAmount exceeded"
        );
        poolAmounts[_indexToken][_isLong] -= _amount;
        emit DecreasePoolAmount(
            _indexToken,
            _isLong,
            poolAmounts[_indexToken][_isLong]
        );
    }

    function _decreaseReservedAmount(
        address _token,
        bool _isLong,
        uint256 _amount
    ) private {
        require(
            reservedAmounts[_token][_isLong] >= _amount,
            "Vault: reservedAmounts exceeded"
        );
        reservedAmounts[_token][_isLong] -= _amount;
        emit DecreaseReservedAmount(
            _token,
            _isLong,
            reservedAmounts[_token][_isLong]
        );
    }

    function _increasePoolAmount(
        address _indexToken,
        bool _isLong,
        uint256 _amount
    ) private {
        poolAmounts[_indexToken][_isLong] += _amount;
        emit IncreasePoolAmount(
            _indexToken,
            _isLong,
            poolAmounts[_indexToken][_isLong]
        );
    }

    function _increaseReservedAmount(
        address _token,
        bool _isLong,
        uint256 _amount
    ) private {
        reservedAmounts[_token][_isLong] += _amount;
        emit IncreaseReservedAmount(
            _token,
            _isLong,
            reservedAmounts[_token][_isLong]
        );
    }
}
