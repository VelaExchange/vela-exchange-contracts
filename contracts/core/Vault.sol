// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSD.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/ILiquidateVault.sol";
import "./interfaces/IOrderVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOperators.sol";
import {Constants} from "../access/Constants.sol";
import {Position, OrderStatus, OrderType} from "./structs.sol";

contract Vault is Constants, ReentrancyGuard, Ownable, IVault {
    using SafeERC20 for IERC20;

    uint256 public totalVLP;
    uint256 public totalUSD;
    IPositionVault private positionVault;
    IOrderVault private orderVault;
    ILiquidateVault private liquidateVault;
    IOperators public immutable operators;
    IPriceManager private priceManager;
    ISettingsManager private settingsManager;
    address private immutable vlp;
    address private immutable vusd;
    bool private isInitialized;

    mapping(address => uint256) public override lastStakedAt;

    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Stake(address indexed account, address token, uint256 amount, uint256 mintAmount);
    event Unstake(address indexed account, address token, uint256 vlpAmount, uint256 amountOut);
    event Withdraw(address indexed account, address indexed token, uint256 amount);
    event TakeVUSDIn(address indexed account, address indexed refer, uint256 amount, uint256 fee);
    event TakeVUSDOut(address indexed account, address indexed refer, uint256 amount, uint256 fee);
    event TransferBounty(address indexed account, uint256 amount);

    modifier onlyVault() {
        require(msg.sender == address(positionVault) || msg.sender == address(liquidateVault), "Only vault");
        _;
    }

    modifier preventBanners(address _account) {
        require(!settingsManager.checkBanList(_account), "Account banned");
        _;
    }

    constructor(address _operators, address _vlp, address _vusd) {
        require(Address.isContract(_operators), "operators invalid");
        operators = IOperators(_operators);
        vlp = _vlp;
        vusd = _vusd;
    }

    function accountDeltaAndFeeIntoTotalUSD(
        bool _hasProfit,
        uint256 _adjustDelta,
        uint256 _fee
    ) external override onlyVault {
        _accountDeltaAndFeeIntoTotalUSD(_hasProfit, _adjustDelta, _fee);
    }

    function addOrRemoveCollateral(
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external nonReentrant preventBanners(msg.sender) {
        positionVault.addOrRemoveCollateral(msg.sender, _posId, isPlus, _amount);
    }

    function addPosition(
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _acceptedPrice
    ) external payable nonReentrant preventBanners(msg.sender) {
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");

        positionVault.addPosition(msg.sender, _posId, _collateralDelta, _sizeDelta, _acceptedPrice);
    }

    function addTrailingStop(
        uint256 _posId,
        uint256[] memory _params
    ) external payable nonReentrant preventBanners(msg.sender) {
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");

        orderVault.addTrailingStop(msg.sender, _posId, _params);
    }

    function cancelPendingOrder(uint256 _posId) public nonReentrant preventBanners(msg.sender) {
        orderVault.cancelPendingOrder(msg.sender, _posId);
    }

    function forceClosePosition(uint256 _posId) external payable nonReentrant {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        // put a require here to call something like positionVault.getPositionProfit(_posId)
        // compare to maxProfitPercent and totalUSD, if the position profit > max profit % of totalUSD, close
        Position memory position = positionVault.getPosition(_posId);
        uint256 price = priceManager.getLastPrice(position.indexToken);
        (bool isProfit, uint256 pnl) = settingsManager.getPnl(
            position.indexToken,
            position.isLong,
            position.size,
            position.averagePrice,
            price,
            position.lastIncreasedTime,
            position.accruedBorrowFee,
            position.fundingIndex
        );
        require(
            isProfit && pnl >= (totalUSD * settingsManager.maxProfitPercent()) / BASIS_POINTS_DIVISOR,
            "not allowed"
        );
        positionVault.decreasePosition(_posId, position.owner, position.size);
    }

    function decreasePosition(
        uint256 _sizeDelta,
        uint256 _acceptedPrice,
        uint256 _posId
    ) external payable nonReentrant preventBanners(msg.sender) {
        require(msg.value == settingsManager.globalGasFee(), "invalid globalGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");

        positionVault.createDecreasePositionOrder(_posId, msg.sender, _sizeDelta, _acceptedPrice);
    }

    function _closePosition(uint256 _posId) internal {
        Position memory pos = positionVault.getPosition(_posId);
        positionVault.decreasePosition(_posId, msg.sender, pos.size);
    }

    function closePosition(uint256 _posId) external payable nonReentrant preventBanners(msg.sender) {
        require(msg.value == settingsManager.globalGasFee(), "invalid globalGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");
        _closePosition(_posId);
    }

    function closePositions(uint256[] memory _posIds) external payable nonReentrant preventBanners(msg.sender) {
        require(msg.value == settingsManager.globalGasFee() * _posIds.length, "invalid globalGasFee");
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");
        for (uint i = 0; i < _posIds.length; i++) {
            _closePosition(_posIds[i]);
        }
    }

    function cancelPendingOrders(uint256[] memory _posIds) external preventBanners(msg.sender) {
        for (uint i = 0; i < _posIds.length; i++) {
            orderVault.cancelPendingOrder(msg.sender, _posIds[i]);
        }
    }

    function deposit(
        address _account,
        address _token,
        uint256 _amount
    ) external nonReentrant preventBanners(msg.sender) {
        uint256 collateralDeltaUsd = priceManager.tokenToUsd(_token, _amount);
        require(settingsManager.isDeposit(_token), "deposit not allowed");
        require(_amount > 0, "zero amount");
        if (_account != msg.sender) {
            require(settingsManager.checkDelegation(_account, msg.sender), "Not allowed");
        }
        _transferIn(msg.sender, _token, _amount);
        uint256 fee = (collateralDeltaUsd * settingsManager.depositFee(_token)) / BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = collateralDeltaUsd - fee;
        _accountDeltaAndFeeIntoTotalUSD(true, 0, fee);
        IVUSD(vusd).mint(_account, afterFeeAmount);
        _distributeFee(_account, ZERO_ADDRESS, fee);
        emit Deposit(_account, _token, _amount);
    }

    function distributeFee(address _account, address _refer, uint256 _fee) external override onlyVault {
        _distributeFee(_account, _refer, _fee);
    }

    function newPositionOrder(
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external payable nonReentrant preventBanners(msg.sender) {
        if (_orderType != OrderType.MARKET) {
            require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        } else {
            require(msg.value == settingsManager.globalGasFee(), "invalid globalGasFee");
        }
        (bool success, ) = payable(settingsManager.feeManager()).call{value: msg.value}("");
        require(success, "failed to send fee");
        require(_refer != msg.sender, "Refer error");
        positionVault.newPositionOrder(msg.sender, _indexToken, _isLong, _orderType, _params, _refer);
    }

    function setVaultSettings(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager,
        IPositionVault _positionVault,
        IOrderVault _orderVault,
        ILiquidateVault _liquidateVault
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "priceManager invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager invalid");
        require(Address.isContract(address(_positionVault)), "positionVault invalid");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        positionVault = _positionVault;
        orderVault = _orderVault;
        liquidateVault = _liquidateVault;
        isInitialized = true;
    }

    function stake(address _account, address _token, uint256 _amount) external nonReentrant preventBanners(msg.sender) {
        require(settingsManager.isStakingEnabled(_token), "staking disabled");
        require(_amount > 0, "zero amount");
        uint256 usdAmount = priceManager.tokenToUsd(_token, _amount);
        if (_account != msg.sender) {
            require(settingsManager.checkDelegation(_account, msg.sender), "Not allowed");
        }
        _transferIn(msg.sender, _token, _amount);
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee(_token)) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        uint256 mintAmount;
        if (totalVLP == 0) {
            mintAmount =
                (usdAmountAfterFee * DEFAULT_VLP_PRICE * (10 ** VLP_DECIMALS)) /
                (PRICE_PRECISION * BASIS_POINTS_DIVISOR);
        } else {
            mintAmount = (usdAmountAfterFee * totalVLP) / totalUSD;
        }
        _accountDeltaAndFeeIntoTotalUSD(true, 0, usdAmountFee);
        _distributeFee(_account, ZERO_ADDRESS, usdAmountFee);
        IMintable(vlp).mint(_account, mintAmount);
        lastStakedAt[_account] = block.timestamp;
        totalVLP += mintAmount;
        totalUSD += usdAmountAfterFee;
        emit Stake(_account, _token, _amount, mintAmount);
    }

    function takeVUSDIn(address _account, address _refer, uint256 _amount, uint256 _fee) external override onlyVault {
        IVUSD(vusd).burn(_account, _amount);
        _mintOrBurnVUSDForVault(true, _amount, _fee, _refer);
        emit TakeVUSDIn(_account, _refer, _amount, _fee);
    }

    function takeVUSDOut(address _account, address _refer, uint256 _fee, uint256 _usdOut) external override onlyVault {
        uint256 _usdOutAfterFee = _usdOut - _fee;
        IVUSD(vusd).mint(_account, _usdOutAfterFee);
        _mintOrBurnVUSDForVault(false, _usdOutAfterFee, _fee, _refer);
        emit TakeVUSDOut(_account, _refer, _usdOut, _fee);
    }

    function unstake(
        address _tokenOut,
        uint256 _vlpAmount,
        address _receiver
    ) external nonReentrant preventBanners(msg.sender) {
        require(_vlpAmount > 0 && _vlpAmount <= totalVLP, "vlpAmount error");
        if (_receiver != msg.sender) {
            require(settingsManager.checkDelegation(_receiver, msg.sender), "Not allowed");
        }
        require(
            lastStakedAt[_receiver] + settingsManager.cooldownDuration() <= block.timestamp,
            "cooldown duration not yet passed"
        );
        IMintable(vlp).burn(_receiver, _vlpAmount);
        uint256 usdAmount = (_vlpAmount * totalUSD) / totalVLP;
        totalVLP -= _vlpAmount;
        uint256 usdAmountFee = (usdAmount * settingsManager.unstakingFee(_tokenOut)) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        totalUSD -= usdAmount;
        uint256 amountOut = priceManager.usdToToken(_tokenOut, usdAmountAfterFee);
        _accountDeltaAndFeeIntoTotalUSD(true, 0, usdAmountFee);
        _distributeFee(_receiver, ZERO_ADDRESS, usdAmountFee);
        _transferOut(_tokenOut, amountOut, _receiver);
        emit Unstake(_receiver, _tokenOut, _vlpAmount, amountOut);
    }

    function withdraw(
        address _token,
        address _account,
        uint256 _amount
    ) external nonReentrant preventBanners(msg.sender) {
        uint256 fee = (_amount * settingsManager.withdrawFee(_token)) / BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = _amount - fee;
        uint256 collateralDelta = priceManager.usdToToken(_token, afterFeeAmount);
        if (_account != msg.sender) {
            require(settingsManager.checkDelegation(_account, msg.sender), "Not allowed");
        }
        _accountDeltaAndFeeIntoTotalUSD(true, 0, fee);
        IVUSD(vusd).burn(address(_account), _amount);
        _distributeFee(_account, ZERO_ADDRESS, fee);
        _transferOut(_token, collateralDelta, _account);
        emit Withdraw(address(_account), _token, collateralDelta);
    }

    function transferBounty(address _account, uint256 _amount) external override onlyVault {
        IVUSD(vusd).burn(address(this), _amount);
        IVUSD(vusd).mint(_account, _amount);
        totalUSD -= _amount;
        emit TransferBounty(_account, _amount);
    }

    function _accountDeltaAndFeeIntoTotalUSD(bool _hasProfit, uint256 _adjustDelta, uint256 _fee) internal {
        if (_adjustDelta != 0) {
            uint256 _feeRewardOnDelta = (_adjustDelta * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            if (_hasProfit) {
                totalUSD += _feeRewardOnDelta;
            } else {
                require(totalUSD >= _feeRewardOnDelta, "exceeded VLP bottom");
                totalUSD -= _feeRewardOnDelta;
            }
        }
        totalUSD += (_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
    }

    function _distributeFee(address _account, address _refer, uint256 _fee) internal {
        _mintOrBurnVUSDForVault(true, _fee, _fee, _refer);
        emit TakeVUSDIn(_account, _refer, 0, _fee);
    }

    function _transferIn(address _account, address _token, uint256 _amount) internal {
        IERC20(_token).safeTransferFrom(_account, address(this), _amount);
    }

    function _transferOut(address _token, uint256 _amount, address _receiver) internal {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function _mintOrBurnVUSDForVault(bool _mint, uint256 _amount, uint256 _fee, address _refer) internal {
        if (_fee != 0 && _refer != ZERO_ADDRESS && settingsManager.referEnabled()) {
            uint256 referFee = (_fee * settingsManager.referFee()) / BASIS_POINTS_DIVISOR;
            IVUSD(vusd).mint(_refer, referFee);
            if (_mint) {
                _amount -= referFee;
            } else {
                _amount += referFee;
            }
            _fee -= referFee;
        }
        address _feeManager = settingsManager.feeManager();
        if (_fee != 0 && _feeManager != ZERO_ADDRESS) {
            uint256 feeReward = (_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            uint256 feeMinusFeeReward = _fee - feeReward;
            IVUSD(vusd).mint(_feeManager, feeMinusFeeReward);
            if (_mint) {
                _amount -= feeMinusFeeReward;
            } else {
                _amount += feeMinusFeeReward;
            }
        }
        if (_mint) {
            IVUSD(vusd).mint(address(this), _amount);
        } else {
            IVUSD(vusd).burn(address(this), _amount);
        }
    }

    function getVLPPrice() external view returns (uint256) {
        if (totalVLP == 0) {
            return DEFAULT_VLP_PRICE;
        } else {
            return (BASIS_POINTS_DIVISOR * (10 ** VLP_DECIMALS) * totalUSD) / (totalVLP * PRICE_PRECISION);
        }
    }

    function getVaultUSDBalance() external view override returns (uint256) {
        return totalUSD;
    }
}
