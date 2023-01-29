// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IVUSDC.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IPriceManager.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import {Constants} from "../access/Constants.sol";
import {OrderStatus, OrderType} from "./structs.sol";

contract Vault is Constants, ReentrancyGuard, Ownable, IVault {
    using SafeERC20 for IERC20;

    uint256 public totalVLP;
    uint256 public totalUSDC;
    IPositionVault private positionVault;
    IPriceManager private priceManager;
    ISettingsManager private settingsManager;
    address private immutable vlp;
    address private immutable vUSDC;
    bool private isInitialized;

    mapping(address => uint256) public lastStakedAt;

    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Stake(address indexed account, address token, uint256 amount, uint256 mintAmount);
    event Unstake(address indexed account, address token, uint256 vlpAmount, uint256 amountOut);
    event Withdraw(address indexed account, address indexed token, uint256 amount);
    event TakeVUSDIn(address indexed account, address indexed refer, uint256 amount, uint256 fee);
    event TakeVUSDOut(address indexed account, address indexed refer, uint256 amount, uint256 fee);
    event TransferBounty(address indexed account, uint256 amount);

    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault has access");
        _;
    }

    modifier preventTradeForForexCloseTime(address _token) {
        if (priceManager.isForex(_token)) {
            require(!settingsManager.pauseForexForCloseTime() , "prevent trade for forex close time");
        }
        _;
    }

    constructor(address _vlp, address _vUSDC) {
        vlp = _vlp;
        vUSDC = _vUSDC;
    }

    function accountDeltaAndFeeIntoTotalUSDC(
        bool _hasProfit,
        uint256 _adjustDelta,
        uint256 _fee
    ) external override onlyVault {
        _accountDeltaAndFeeIntoTotalUSDC(_hasProfit, _adjustDelta, _fee);
    }

    function addOrRemoveCollateral(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external nonReentrant preventTradeForForexCloseTime(_indexToken) {
        positionVault.addOrRemoveCollateral(msg.sender, _indexToken, _isLong, _posId, isPlus, _amount);
    }

    function addPosition(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external payable nonReentrant preventTradeForForexCloseTime(_indexToken) {
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        payable(settingsManager.positionManager()).transfer(msg.value);
        positionVault.addPosition(msg.sender, _indexToken, _isLong, _posId, _collateralDelta, _sizeDelta);
    }

    function addTrailingStop(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external payable nonReentrant {
        require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        payable(settingsManager.positionManager()).transfer(msg.value);
        positionVault.addTrailingStop(msg.sender, _indexToken, _isLong, _posId, _params);
    }

    function cancelPendingOrder(address _indexToken, bool _isLong, uint256 _posId) external nonReentrant {
        positionVault.cancelPendingOrder(msg.sender, _indexToken, _isLong, _posId);
    }

    function decreasePosition(
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant preventTradeForForexCloseTime(_indexToken) {
        positionVault.decreasePosition(msg.sender, _indexToken, _sizeDelta, _isLong, _posId);
    }

    function deposit(address _account, address _token, uint256 _amount) external nonReentrant {
        uint256 collateralDeltaUsd = priceManager.tokenToUsd(_token, _amount);
        require(settingsManager.isDeposit(_token), "deposit not allowed");
        require(
            (settingsManager.checkDelegation(_account, msg.sender)) && _amount > 0,
            "zero amount or not allowed for depositFor"
        );
        _transferIn(_account, _token, _amount);
        uint256 fee = (collateralDeltaUsd * settingsManager.depositFee()) / BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = collateralDeltaUsd - fee;
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        IVUSDC(vUSDC).mint(_account, afterFeeAmount);
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
    ) external payable nonReentrant preventTradeForForexCloseTime(_indexToken) {
        if (_orderType != OrderType.MARKET) {
            require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
            payable(settingsManager.positionManager()).transfer(msg.value);
        }
        positionVault.newPositionOrder(msg.sender, _indexToken, _isLong, _orderType, _params, _refer);
    }

    function setVaultSettings(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager,
        IPositionVault _positionVault
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "priceManager address is invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager address is invalid");
        require(Address.isContract(address(_positionVault)), "positionVault address is invalid");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        positionVault = _positionVault;
        isInitialized = true;
    }

    function stake(address _account, address _token, uint256 _amount) external nonReentrant {
        require(settingsManager.isStaking(_token), "stake not allowed");
        require(
            (settingsManager.checkDelegation(_account, msg.sender)) && _amount > 0,
            "zero amount or not allowed for stakeFor"
        );
        uint256 usdAmount = priceManager.tokenToUsd(_token, _amount);
        _transferIn(_account, _token, _amount);
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee()) / BASIS_POINTS_DIVISOR;
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
        _distributeFee(_account, ZERO_ADDRESS, usdAmountFee);
        IMintable(vlp).mint(_account, mintAmount);
        lastStakedAt[_account] = block.timestamp;
        totalVLP += mintAmount;
        totalUSDC += usdAmountAfterFee;
        emit Stake(_account, _token, _amount, mintAmount);
    }

    function takeVUSDIn(address _account, address _refer, uint256 _amount, uint256 _fee) external override onlyVault {
        IVUSDC(vUSDC).burn(_account, _amount);
        _mintOrBurnVUSDForVault(true, _amount, _fee, _refer);
        emit TakeVUSDIn(_account, _refer, _amount, _fee);
    }

    function takeVUSDOut(address _account, address _refer, uint256 _fee, uint256 _usdOut) external override onlyVault {
        uint256 _usdOutAfterFee = _usdOut - _fee;
        IVUSDC(vUSDC).mint(_account, _usdOutAfterFee);
        _mintOrBurnVUSDForVault(false, _usdOutAfterFee, _fee, _refer);
        emit TakeVUSDOut(_account, _refer, _usdOut, _fee);
    }

    function unstake(address _tokenOut, uint256 _vlpAmount, address _receiver) external nonReentrant {
        require(settingsManager.isStaking(_tokenOut), "unstake not allowed");
        require(_vlpAmount > 0 && _vlpAmount <= totalVLP, "zero amount not allowed and cant exceed totalVLP");
        require(
            lastStakedAt[msg.sender] + settingsManager.cooldownDuration() <= block.timestamp,
            "cooldown duration not yet passed"
        );
        IMintable(vlp).burn(msg.sender, _vlpAmount);
        uint256 usdAmount = (_vlpAmount * totalUSDC) / totalVLP;
        totalVLP -= _vlpAmount;
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee()) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        totalUSDC -= usdAmount;
        uint256 amountOut = priceManager.usdToToken(_tokenOut, usdAmountAfterFee);
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, usdAmountFee);
        _distributeFee(msg.sender, ZERO_ADDRESS, usdAmountFee);
        _transferOut(_tokenOut, amountOut, _receiver);
        emit Unstake(msg.sender, _tokenOut, _vlpAmount, amountOut);
    }

    function withdraw(address _token, address _account, uint256 _amount) external nonReentrant {
        uint256 fee = (_amount * settingsManager.depositFee()) / BASIS_POINTS_DIVISOR;
        uint256 afterFeeAmount = _amount - fee;
        uint256 collateralDelta = priceManager.usdToToken(_token, afterFeeAmount);
        require(settingsManager.isDeposit(_token), "withdraw not allowed");
        _accountDeltaAndFeeIntoTotalUSDC(true, 0, fee);
        IVUSDC(vUSDC).burn(address(msg.sender), _amount);
        _distributeFee(_account, ZERO_ADDRESS, fee);
        _transferOut(_token, collateralDelta, _account);
        emit Withdraw(address(msg.sender), _token, collateralDelta);
    }

    function transferBounty(address _account, uint256 _amount) external override onlyVault {
        IVUSDC(vUSDC).burn(address(this), _amount);
        IVUSDC(vUSDC).mint(_account, _amount);
        totalUSDC -= _amount;
        emit TransferBounty(_account, _amount);
    }

    function _accountDeltaAndFeeIntoTotalUSDC(bool _hasProfit, uint256 _adjustDelta, uint256 _fee) internal {
        if (_adjustDelta != 0) {
            uint256 _feeRewardOnDelta = (_adjustDelta * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            if (_hasProfit) {
                totalUSDC += _feeRewardOnDelta;
            } else {
                require(totalUSDC >= _feeRewardOnDelta, "exceeded VLP bottom");
                totalUSDC -= _feeRewardOnDelta;
            }
        }
        totalUSDC += (_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
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
        address _feeManager = settingsManager.feeManager();
        if (_fee != 0 && _feeManager != ZERO_ADDRESS) {
            uint256 feeReward = (_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            uint256 feeMinusFeeReward = _fee - feeReward;
            IVUSDC(vUSDC).mint(_feeManager, feeMinusFeeReward);
            if (_mint) {
                _amount -= feeMinusFeeReward;
            } else {
                _amount += feeMinusFeeReward;
            }
            _fee = feeReward;
        }
        if (_refer != ZERO_ADDRESS && settingsManager.referEnabled()) {
            uint256 referFee = (_fee * settingsManager.referFee()) / BASIS_POINTS_DIVISOR;
            IVUSDC(vUSDC).mint(_refer, referFee);
            if (_mint) {
                _amount -= referFee;
            } else {
                _amount += referFee;
            }
        }
        if (_mint) {
            IVUSDC(vUSDC).mint(address(this), _amount);
        } else {
            IVUSDC(vUSDC).burn(address(this), _amount);
        }
    }

    function getVLPPrice() external view returns (uint256) {
        if (totalVLP == 0) {
            return DEFAULT_VLP_PRICE;
        } else {
            return (BASIS_POINTS_DIVISOR * (10 ** VLP_DECIMALS) * totalUSDC) / (totalVLP * PRICE_PRECISION);
        }
    }
}
