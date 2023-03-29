// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IOperators.sol";
import "../staking/interfaces/ITokenFarm.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IVUSD.sol";

contract SettingsManager is ISettingsManager, Ownable, Constants {
    using EnumerableSet for EnumerableSet.AddressSet;
    address public immutable vusd;
    IPositionVault public immutable positionVault;
    IOperators public immutable operators;
    ITokenFarm public immutable tokenFarm;

    address public override feeManager;
    bool public override marketOrderEnabled = true;
    bool public override pauseForexForCloseTime;
    bool public override referEnabled = true;
    EnumerableSet.AddressSet private banWalletList;
    uint256 public maxOpenInterestPerUser;
    uint256 public priceMovementPercent = 500; // 0.5%

    struct BountyPercent {
        uint32 team;
        uint32 firstCaller;
        uint32 resolver;
    } // pack to save gas
    BountyPercent private bountyPercent_ = BountyPercent({team: 10000, firstCaller: 5000, resolver: 15000}); //team 10%, first caller 5% and resolver 15%
    uint256 public override liquidationPendingTime = 10; // allow 10 seconds for manager to resolve liquidation

    uint256 public override closeDeltaTime = 1 hours;
    uint256 public override cooldownDuration = 3 hours;
    uint256 public override delayDeltaTime = 1 minutes;
    uint256 public override feeRewardBasisPoints = 50000; // 50%
    uint256 public override liquidationFeeUsd; // 0 usd
    uint256 public override referFee = 5000; // 5%
    uint256 public override triggerGasFee = 0; //100 gwei;
    uint256 public override globalGasFee = 0;

    uint256 public override maxFundingRate = 10000;
    uint256 public override basisFundingRateFactor = 10000;

    mapping(address => bool) public override isDeposit;
    mapping(address => bool) public override isWithdraw;
    mapping(address => bool) public override isManager;
    mapping(address => bool) public override isStakingEnabled;
    mapping(address => bool) public override isUnstakingEnabled;
    mapping(address => uint256) public override deductFeePercent;
    mapping(address => uint256) public override depositFee;
    mapping(address => uint256) public override withdrawFee;
    mapping(address => uint256) public override stakingFee;
    mapping(address => uint256) public override unstakingFee;
    mapping(address => int256) public override fundingIndex;
    mapping(address => uint256) public override fundingRateFactor;
    mapping(address => mapping(bool => uint256)) public override marginFeeBasisPoints; // = 100; // 0.1%
    mapping(address => uint256) public override lastFundingTimes;

    mapping(address => uint256) public liquidateThreshold;
    mapping(address => mapping(bool => uint256)) public maxOpenInterestPerAssetPerSide;
    mapping(address => mapping(bool => uint256)) public override openInterestPerAssetPerSide;
    mapping(address => uint256) public override openInterestPerUser;
    mapping(address => uint256) public maxOpenInterestPerWallet;
    mapping(address => EnumerableSet.AddressSet) private _delegatesByMaster;
    event ChangedReferEnabled(bool referEnabled);
    event ChangedReferFee(uint256 referFee);
    event PauseForexMarket(bool _paused);
    event EnableMarketOrder(bool _enabled);
    event SetAssetManagerWallet(address manager);
    event SetBountyPercent(uint256 bountyPercentTeam, uint256 bountyPercentFirstCaller, uint256 bountyPercentResolver);
    event SetDeductFeePercent(address indexed account, uint256 deductFee);
    event SetDepositFee(address indexed token, uint256 indexed fee);
    event SetWithdrawFee(address indexed token, uint256 indexed fee);
    event SetEnableDeposit(address indexed token, bool isEnabled);
    event SetEnableWithdraw(address indexed token, bool isEnabled);
    event SetEnableStaking(address indexed token, bool isEnabled);
    event SetEnableUnstaking(address indexed token, bool isEnabled);
    event SetFundingRateFactor(address indexed token, uint256 fundingRateFactor);
    event SetLiquidationFeeUsd(uint256 indexed _liquidationFeeUsd);
    event SetMarginFeeBasisPoints(address indexed token, bool isLong, uint256 marginFeeBasisPoints);
    event SetMaxOpenInterestPerAssetPerSide(address indexed token, bool isLong, uint256 maxOIAmount);
    event SetMaxOpenInterestPerUser(uint256 maxOIAmount);
    event SetMaxOpenInterestPerWallet(address indexed account, uint256 maxOIAmount);
    event SetPositionManager(address manager, bool isManager);
    event SetPriceMovementPercent(uint256 priceMovementPercent);
    event SetStakingFee(address indexed token, uint256 indexed fee);
    event SetUnstakingFee(address indexed token, uint256 indexed fee);
    event SetTriggerGasFee(uint256 indexed fee);
    event SetGlobalGasFee(uint256 indexed fee);
    event SetVaultSettings(uint256 indexed cooldownDuration, uint256 feeRewardBasisPoints);
    event UpdateFunding(address indexed token, int256 fundingIndex);
    event UpdateTotalOpenInterest(address indexed token, bool isLong, uint256 amount);
    event UpdateLiquidationPendingTime(uint256 liquidationPendingTime);
    event UpdateCloseDeltaTime(uint256 deltaTime);
    event UpdateDelayDeltaTime(uint256 deltaTime);
    event UpdateFeeManager(address indexed feeManager);
    event UpdateThreshold(uint256 oldThreshold, uint256 newThredhold);

    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault has access");
        _;
    }

    constructor(address _positionVault, address _operators, address _vusd, address _tokenFarm) {
        require(Address.isContract(_positionVault), "vault address is invalid");
        require(Address.isContract(_operators), "operators address is invalid");
        require(Address.isContract(_vusd), "VUSD address is invalid");
        require(Address.isContract(_tokenFarm), "tokenFarm address is invalid");
        positionVault = IPositionVault(_positionVault);
        operators = IOperators(_operators);
        tokenFarm = ITokenFarm(_tokenFarm);
        vusd = _vusd;
    }

    function delegate(address[] memory _delegates) external {
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.add(_delegatesByMaster[msg.sender], _delegates[i]);
        }
    }

    function addDelegatesToBanList(address[] memory _delegates) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.add(banWalletList, _delegates[i]);
        }
    }

    function removeDelegatesFromBanList(address[] memory _delegates) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.remove(banWalletList, _delegates[i]);
        }
    }

    function decreaseOpenInterest(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override onlyVault {
        if (openInterestPerUser[_sender] < _amount) {
            openInterestPerUser[_sender] = 0;
        } else {
            openInterestPerUser[_sender] -= _amount;
        }
        if (openInterestPerAssetPerSide[_token][_isLong] < _amount) {
            openInterestPerAssetPerSide[_token][_isLong] = 0;
        } else {
            openInterestPerAssetPerSide[_token][_isLong] -= _amount;
        }
        emit UpdateTotalOpenInterest(_token, _isLong, _amount);
    }

    function pauseForexMarket(bool _paused) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        pauseForexForCloseTime = _paused;
        emit PauseForexMarket(_paused);
    }

    function enableMarketOrder(bool _enable) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        marketOrderEnabled = _enable;
        emit EnableMarketOrder(_enable);
    }

    function increaseOpenInterest(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override onlyVault {
        openInterestPerUser[_sender] += _amount;
        openInterestPerAssetPerSide[_token][_isLong] += _amount;

        emit UpdateTotalOpenInterest(_token, _isLong, _amount);
    }

    function setBountyPercent(
        uint32 _bountyPercentTeam,
        uint32 _bountyPercentFirstCaller,
        uint32 _bountyPercentResolver
    ) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(
            _bountyPercentTeam + _bountyPercentFirstCaller + _bountyPercentResolver <= BASIS_POINTS_DIVISOR,
            "invalid bountyPercent"
        );
        bountyPercent_.team = _bountyPercentTeam;
        bountyPercent_.firstCaller = _bountyPercentFirstCaller;
        bountyPercent_.resolver = _bountyPercentResolver;
        emit SetBountyPercent(_bountyPercentTeam, _bountyPercentFirstCaller, _bountyPercentResolver);
    }

    function bountyPercent() external view returns (uint32, uint32, uint32) {
        return (bountyPercent_.team, bountyPercent_.firstCaller, bountyPercent_.resolver);
    }

    function setFeeManager(address _feeManager) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        feeManager = _feeManager;
        emit UpdateFeeManager(_feeManager);
    }

    function setVaultSettings(uint256 _cooldownDuration, uint256 _feeRewardsBasisPoints) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "invalid cooldownDuration");
        require(_feeRewardsBasisPoints >= MIN_FEE_REWARD_BASIS_POINTS, "feeRewardsBasisPoints not greater than min");
        require(_feeRewardsBasisPoints < MAX_FEE_REWARD_BASIS_POINTS, "feeRewardsBasisPoints not smaller than max");
        cooldownDuration = _cooldownDuration;
        feeRewardBasisPoints = _feeRewardsBasisPoints;
        emit SetVaultSettings(cooldownDuration, feeRewardBasisPoints);
    }

    function setLiquidationPendingTime(uint256 _liquidationPendingTime) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(_liquidationPendingTime <= 60, "liquidationPendingTime is bigger than max");
        liquidationPendingTime = _liquidationPendingTime;
        emit UpdateLiquidationPendingTime(_liquidationPendingTime);
    }

    function setCloseDeltaTime(uint256 _deltaTime) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_deltaTime <= MAX_DELTA_TIME, "closeDeltaTime is bigger than max");
        closeDeltaTime = _deltaTime;
        emit UpdateCloseDeltaTime(_deltaTime);
    }

    function setDelayDeltaTime(uint256 _deltaTime) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_deltaTime <= MAX_DELTA_TIME, "delayDeltaTime is bigger than max");
        delayDeltaTime = _deltaTime;
        emit UpdateDelayDeltaTime(_deltaTime);
    }

    function setDepositFee(address token, uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_DEPOSIT_WITHDRAW_FEE, "deposit fee is bigger than max");
        depositFee[token] = _fee;
        emit SetDepositFee(token, _fee);
    }

    function setWithdrawFee(address token, uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_DEPOSIT_WITHDRAW_FEE, "withdraw fee is bigger than max");
        withdrawFee[token] = _fee;
        emit SetWithdrawFee(token, _fee);
    }

    function setEnableDeposit(address _token, bool _isEnabled) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        isDeposit[_token] = _isEnabled;
        emit SetEnableDeposit(_token, _isEnabled);
    }

    function setEnableWithdraw(address _token, bool _isEnabled) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        isWithdraw[_token] = _isEnabled;
        emit SetEnableWithdraw(_token, _isEnabled);
    }

    function setEnableStaking(address _token, bool _isEnabled) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        isStakingEnabled[_token] = _isEnabled;
        emit SetEnableStaking(_token, _isEnabled);
    }

    function setEnableUnstaking(address _token, bool _isEnabled) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        isUnstakingEnabled[_token] = _isEnabled;
        emit SetEnableUnstaking(_token, _isEnabled);
    }

    function setDeductFeePercentForUser(address _account, uint256 _deductFee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_deductFee <= BASIS_POINTS_DIVISOR, "it cant exceed max value");
        deductFeePercent[_account] = _deductFee;
        emit SetDeductFeePercent(_account, _deductFee);
    }

    function setFundingRateFactor(address _token, uint256 _fundingRateFactor) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        fundingRateFactor[_token] = _fundingRateFactor;
        emit SetFundingRateFactor(_token, _fundingRateFactor);
    }

    function setLiquidateThreshold(uint256 _newThreshold, address _token) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        emit UpdateThreshold(liquidateThreshold[_token], _newThreshold);
        require(_newThreshold < LIQUIDATE_THRESHOLD_DIVISOR, "threshold should be smaller than MAX");
        liquidateThreshold[_token] = _newThreshold;
    }

    function setLiquidationFeeUsd(uint256 _liquidationFeeUsd) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "liquidationFeeUsd should be smaller than MAX");
        liquidationFeeUsd = _liquidationFeeUsd;
        emit SetLiquidationFeeUsd(_liquidationFeeUsd);
    }

    function setMarginFeeBasisPoints(address _token, bool _isLong, uint256 _marginFeeBasisPoints) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "marginFeeBasisPoints should be smaller than MAX");
        marginFeeBasisPoints[_token][_isLong] = _marginFeeBasisPoints;
        emit SetMarginFeeBasisPoints(_token, _isLong, _marginFeeBasisPoints);
    }

    function setMaxOpenInterestPerAssetPerSide(address _token, bool _isLong, uint256 _maxAmount) public {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        maxOpenInterestPerAssetPerSide[_token][_isLong] = _maxAmount;
        emit SetMaxOpenInterestPerAssetPerSide(_token, _isLong, _maxAmount);
    }

    function setMaxOpenInterestPerAsset(address _token, uint256 _maxAmount) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        setMaxOpenInterestPerAssetPerSide(_token, true, _maxAmount);
        setMaxOpenInterestPerAssetPerSide(_token, false, _maxAmount);
    }

    function setMaxOpenInterestPerUser(uint256 _maxAmount) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        maxOpenInterestPerUser = _maxAmount;
        emit SetMaxOpenInterestPerUser(_maxAmount);
    }

    function setMaxOpenInterestPerWallet(address _account, uint256 _maxAmount) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        maxOpenInterestPerWallet[_account] = _maxAmount;
        emit SetMaxOpenInterestPerWallet(_account, _maxAmount);
    }

    function setPositionManager(address _manager, bool _isManager) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        isManager[_manager] = _isManager;
        emit SetPositionManager(_manager, _isManager);
    }

    function setPriceMovementPercent(uint256 _priceMovementPercent) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(
            _priceMovementPercent <= MAX_PRICE_MOVEMENT_PERCENT,
            "price percent should be smaller than max percent"
        );
        priceMovementPercent = _priceMovementPercent;
        emit SetPriceMovementPercent(_priceMovementPercent);
    }

    function setReferEnabled(bool _referEnabled) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        referEnabled = _referEnabled;
        emit ChangedReferEnabled(referEnabled);
    }

    function setReferFee(uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(2), "Invalid operator");
        require(_fee <= BASIS_POINTS_DIVISOR, "fee should be smaller than feeDivider");
        referFee = _fee;
        emit ChangedReferFee(_fee);
    }

    function setStakingFee(address token, uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_STAKING_UNSTAKING_FEE, "staking fee is bigger than max");
        stakingFee[token] = _fee;
        emit SetStakingFee(token, _fee);
    }

    function setUnstakingFee(address token, uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_STAKING_UNSTAKING_FEE, "unstaking fee is bigger than max");
        unstakingFee[token] = _fee;
        emit SetUnstakingFee(token, _fee);
    }

    function setTriggerGasFee(uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_TRIGGER_GAS_FEE, "trigger gas fee exceed max");
        triggerGasFee = _fee;
        emit SetTriggerGasFee(_fee);
    }

    function setGlobalGasFee(uint256 _fee) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_fee <= MAX_GLOBAL_GAS_FEE, "global gas fee exceed max");
        globalGasFee = _fee;
        emit SetGlobalGasFee(_fee);
    }

    function undelegate(address[] memory _delegates) external {
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.remove(_delegatesByMaster[msg.sender], _delegates[i]);
        }
    }

    function collectMarginFees(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) external view override returns (uint256) {
        uint256 feeUsd = ((BASIS_POINTS_DIVISOR - deductFeePercent[_account]) *
            getPositionFee(_indexToken, _isLong, _sizeDelta)) / BASIS_POINTS_DIVISOR;

        return (feeUsd * tokenFarm.getTier(STAKING_PID_FOR_CHARGE_FEE, _account)) / BASIS_POINTS_DIVISOR;
    }

    function getDelegates(address _master) external view override returns (address[] memory) {
        return enumerate(_delegatesByMaster[_master]);
    }

    function validatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _collateral
    ) external view override {
        if (_size == 0) {
            require(_collateral == 0, "collateral is not zero");
            return;
        }
        require(_size >= _collateral, "position size should be greater than collateral");
        require(
            openInterestPerUser[_account] + _size <=
                (
                    maxOpenInterestPerWallet[_account] == 0
                        ? DEFAULT_MAX_OI_PER_WALLET
                        : maxOpenInterestPerWallet[_account]
                ),
            "exceed max open interest for this account"
        );
        require(
            openInterestPerAssetPerSide[_indexToken][_isLong] + _size <=
                maxOpenInterestPerAssetPerSide[_indexToken][_isLong],
            "exceed max open interest per asset and per side"
        );
        require(openInterestPerUser[_account] + _size <= maxOpenInterestPerUser, "exceed max open interest per user");
    }

    function enumerate(EnumerableSet.AddressSet storage set) internal view returns (address[] memory) {
        uint256 length = EnumerableSet.length(set);
        address[] memory output = new address[](length);
        for (uint256 i; i < length; ++i) {
            output[i] = EnumerableSet.at(set, i);
        }
        return output;
    }

    function checkBanList(address _delegate) public view override returns (bool) {
        return EnumerableSet.contains(banWalletList, _delegate);
    }

    function checkDelegation(address _master, address _delegate) public view override returns (bool) {
        require(!checkBanList(_master), "prevent banners from delegation");
        return _master == _delegate || EnumerableSet.contains(_delegatesByMaster[_master], _delegate);
    }

    function getPnl(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        uint256 _lastPrice,
        int256 _fundingIndex,
        bool _isLong
    ) public view override returns (bool, uint256) {
        require(_averagePrice > 0, "average price should be greater than zero");
        int256 pnl;

        if (_isLong) {
            if (_lastPrice >= _averagePrice) {
                pnl = int256((_size * (_lastPrice - _averagePrice)) / _averagePrice);
            } else {
                pnl = -1 * int256((_size * (_averagePrice - _lastPrice)) / _averagePrice);
            }
        } else {
            if (_lastPrice <= _averagePrice) {
                pnl = int256((_size * (_averagePrice - _lastPrice)) / _averagePrice);
            } else {
                pnl = -1 * int256((_size * (_lastPrice - _averagePrice)) / _averagePrice);
            }
        }

        pnl += getFundingFee(_indexToken, _isLong, _size, _fundingIndex);

        if (pnl > 0) {
            return (true, uint256(pnl));
        }
        return (false, uint256(-1 * pnl));
    }

    function updateFunding(address _indexToken) external override {
        if (lastFundingTimes[_indexToken] != 0) {
            int256 fundingRate = getFundingRate(_indexToken);
            fundingIndex[_indexToken] += fundingRate * int256(block.timestamp - lastFundingTimes[_indexToken]);

            emit UpdateFunding(_indexToken, fundingIndex[_indexToken]);
        }

        lastFundingTimes[_indexToken] = block.timestamp;
    }

    function getFundingRate(address _indexToken) public view override returns (int256) {
        if (positionVault.getVaultUSDBalance() == 0) {
            return 0;
        }
        uint256 assetLongOI = openInterestPerAssetPerSide[_indexToken][true];
        uint256 assetShortOI = openInterestPerAssetPerSide[_indexToken][false];

        if (assetLongOI >= assetShortOI) {
            uint256 fundingRate = ((assetLongOI - assetShortOI) *
                fundingRateFactor[_indexToken] *
                basisFundingRateFactor) / positionVault.getVaultUSDBalance();
            if (fundingRate > maxFundingRate) {
                return int256(maxFundingRate);
            } else {
                return int256(fundingRate);
            }
        } else {
            uint256 fundingRate = ((assetShortOI - assetLongOI) *
                fundingRateFactor[_indexToken] *
                basisFundingRateFactor) / positionVault.getVaultUSDBalance();
            if (fundingRate > maxFundingRate) {
                return -1 * int256(maxFundingRate);
            } else {
                return -1 * int256(fundingRate);
            }
        }
    }

    function getFundingFee(
        address _indexToken,
        bool _isLong,
        uint256 _size,
        int256 _fundingIndex
    ) public view override returns (int256) {
        return
            _isLong
                ? (int256(_size) * (fundingIndex[_indexToken] - _fundingIndex)) / int256(FUNDING_RATE_PRECISION)
                : (int256(_size) * (_fundingIndex - fundingIndex[_indexToken])) / int256(FUNDING_RATE_PRECISION);
    }

    function getPositionFee(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) public view override returns (uint256) {
        return (_sizeDelta * marginFeeBasisPoints[_indexToken][_isLong]) / BASIS_POINTS_DIVISOR;
    }
}
