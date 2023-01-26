// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IPositionVault.sol";
import "../staking/interfaces/ITokenFarm.sol";
import {Constants} from "../access/Constants.sol";
import "../access/Governable.sol";
import "../tokens/interfaces/IVUSDC.sol";

contract SettingsManager is ISettingsManager, Governable, Constants {
    using EnumerableSet for EnumerableSet.AddressSet;
    address public immutable vUSDC;
    IPositionVault public immutable positionVault;
    ITokenFarm public immutable tokenFarm;

    address public override feeManager;
    bool public override marketOrderEnabled = true;
    address public override positionManager;
    bool public override referEnabled;
    uint256 public maxBorrowUSDAmountPerUser;
    uint256 public priceMovementPercent = 500; // 0.5%

    uint256 public override bountyPercent = 20000; // 20%
    uint256 public override closeDeltaTime = 1 hours;
    uint256 public override cooldownDuration = 3 hours;
    uint256 public override delayDeltaTime = 1 minutes;
    uint256 public override depositFee = 300; // 0.3%
    uint256 public override feeRewardBasisPoints = 70000; // 70%
    uint256 public override fundingInterval = 8 hours;
    uint256 public override liquidationFeeUsd; // 0 usd
    uint256 public override stakingFee = 300; // 0.3%
    uint256 public override referFee = 5000; // 5%
    uint256 public override triggerGasFee = 0; //100 gwei;

    mapping(address => bool) public isCustomFees;
    mapping(address => bool) public override isDeposit;
    mapping(address => bool) public override isManager;
    mapping(address => bool) public override isStaking;

    mapping(address => mapping(bool => uint256)) public override cumulativeFundingRates;
    mapping(address => mapping(bool => uint256)) public override fundingRateFactor;
    mapping(address => mapping(bool => uint256)) public override marginFeeBasisPoints; // = 100; // 0.1%
    mapping(address => mapping(bool => uint256)) public override lastFundingTimes;

    mapping(bool => uint256) public maxBorrowUSDAmountPerSide;

    mapping(address => uint256) public customFeePoints;
    mapping(address => uint256) public liquidateThreshold;
    mapping(address => uint256) public maxBorrowUSDAmountPerAsset;
    mapping(address => uint256) public override borrowedUsdPerAsset;
    mapping(address => uint256) public override borrowedUsdPerUser;
    mapping(bool => uint256) public override borrowedUsdPerSide;
    mapping(address => EnumerableSet.AddressSet) private _delegatesByMaster;

    event ChangedReferEnabled(bool referEnabled);
    event ChangedReferFee(uint256 referFee);
    event EnableMarketOrder(bool _enabled);
    event SetCustomFeeForUser(uint256 indexed feePoints, bool isEnabled);
    event SetDepositFee(uint256 indexed fee);
    event SetEnableDeposit(address indexed token, bool isEnabled);
    event SetEnableStaking(address indexed token, bool isEnabled);
    event SetFundingInterval(uint256 indexed fundingInterval);
    event SetFundingRateFactor(address indexed token, bool isLong, uint256 fundingRateFactor);
    event SetLiquidationFeeUsd(uint256 indexed _liquidationFeeUsd);
    event SetMarginFeeBasisPoints(address indexed token, bool isLong, uint256 marginFeeBasisPoints);
    event SetMaxBorrowAmountPerAsset(address indexed token, uint256 maxBorrowAmount);
    event SetMaxBorrowAmountPerSide(bool isLong, uint256 maxBorrowAmount);
    event SetMaxBorrowAmountPerUser(uint256 maxBorrowAmount);
    event SetPositionManager(address manager, bool isManager);
    event SetStakingFee(uint256 indexed fee);
    event SetTriggerGasFee(uint256 indexed fee);
    event SetVaultSettings(uint256 indexed cooldownDuration, uint256 feeRewardBasisPoints);
    event UpdateFundingRate(address indexed token, bool isLong, uint256 fundingRate, uint256 lastFundingTime);
    event UpdateTotalBorrowedAmount(address indexed token, bool isLong, uint256 amount);
    event UpdateCloseDeltaTime(uint256 deltaTime);
    event UpdateDelayDeltaTime(uint256 deltaTime);
    event UpdateFeeManager(address indexed feeManager);
    event UpdateThreshold(uint256 oldThreshold, uint256 newThredhold);

    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault has access");
        _;
    }

    constructor(address _positionVault, address _vUSDC, address _tokenFarm) {
        require(Address.isContract(_positionVault), "vault address is invalid");
        require(Address.isContract(_vUSDC), "vUSD address is invalid");
        require(Address.isContract(_tokenFarm), "tokenFarm address is invalid");
        positionVault = IPositionVault(_positionVault);
        tokenFarm = ITokenFarm(_tokenFarm);
        vUSDC = _vUSDC;
    }

    function delegate(address[] memory _delegates) external {
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.add(_delegatesByMaster[msg.sender], _delegates[i]);
        }
    }

    function decreaseBorrowedUsd(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override onlyVault {
        if (borrowedUsdPerUser[_sender] < _amount) {
            borrowedUsdPerUser[_sender] = 0;
        } else {
            borrowedUsdPerUser[_sender] -= _amount;
        }
        if (borrowedUsdPerAsset[_token] < _amount) {
            borrowedUsdPerAsset[_token] -= 0;
        } else {
            borrowedUsdPerAsset[_token] -= _amount;
        }
        if (borrowedUsdPerSide[_isLong] < _amount) {
            borrowedUsdPerSide[_isLong] -= 0;
        } else {
            borrowedUsdPerSide[_isLong] -= _amount;
        }
        emit UpdateTotalBorrowedAmount(_token, _isLong, _amount);
    }

    function enableMarketOrder(bool _enable) external onlyGov {
        marketOrderEnabled = _enable;
        emit EnableMarketOrder(_enable);
    }

    function increaseBorrowedUsd(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override onlyVault {
        borrowedUsdPerUser[_sender] += _amount;
        borrowedUsdPerAsset[_token] += _amount;
        borrowedUsdPerSide[_isLong] += _amount;
        emit UpdateTotalBorrowedAmount(_token, _isLong, _amount);
    }

    function setFeeManager(address _feeManager) external onlyGov {
        feeManager = _feeManager;
        emit UpdateFeeManager(_feeManager);
    }

    function setVaultSettings(uint256 _cooldownDuration, uint256 _feeRewardsBasisPoints) external onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "invalid cooldownDuration");
        require(_feeRewardsBasisPoints >= MIN_FEE_REWARD_BASIS_POINTS, "feeRewardsBasisPoints not greater than min");
        require(_feeRewardsBasisPoints < MAX_FEE_REWARD_BASIS_POINTS, "feeRewardsBasisPoints not smaller than max");
        cooldownDuration = _cooldownDuration;
        feeRewardBasisPoints = _feeRewardsBasisPoints;
        emit SetVaultSettings(cooldownDuration, feeRewardBasisPoints);
    }

    function setCloseDeltaTime(uint256 _deltaTime) external onlyGov {
        require(_deltaTime <= MAX_DELTA_TIME, "closeDeltaTime is bigger than max");
        closeDeltaTime = _deltaTime;
        emit UpdateCloseDeltaTime(_deltaTime);
    }

    function setCustomFeeForUser(address _account, uint256 _feePoints, bool _isEnabled) external override onlyGov {
        isCustomFees[_account] = _isEnabled;
        require(_feePoints <= MAX_CUSTOM_FEE_POINTS, "custom fee exceeds MAX");
        customFeePoints[_account] = _feePoints;
        emit SetCustomFeeForUser(_feePoints, _isEnabled);
    }

    function setDelayDeltaTime(uint256 _deltaTime) external onlyGov {
        require(_deltaTime <= MAX_DELTA_TIME, "delayDeltaTime is bigger than max");
        delayDeltaTime = _deltaTime;
        emit UpdateDelayDeltaTime(_deltaTime);
    }

    function setDepositFee(uint256 _fee) external onlyGov {
        require(_fee <= MAX_DEPOSIT_FEE, "deposit fee is bigger than max");
        depositFee = _fee;
        emit SetDepositFee(_fee);
    }

    function setEnableDeposit(address _token, bool _isEnabled) external onlyGov {
        isDeposit[_token] = _isEnabled;
        emit SetEnableDeposit(_token, _isEnabled);
    }

    function setEnableStaking(address _token, bool _isEnabled) external onlyGov {
        isStaking[_token] = _isEnabled;
        emit SetEnableStaking(_token, _isEnabled);
    }

    function setFundingInterval(uint256 _fundingInterval) external onlyGov {
        require(_fundingInterval >= MIN_FUNDING_RATE_INTERVAL, "fundingInterval should be greater than MIN");
        require(_fundingInterval <= MAX_FUNDING_RATE_INTERVAL, "fundingInterval should be smaller than MAX");
        fundingInterval = _fundingInterval;
        emit SetFundingInterval(fundingInterval);
    }

    function setFundingRateFactor(address _token, bool _isLong, uint256 _fundingRateFactor) external onlyGov {
        require(_fundingRateFactor <= MAX_FUNDING_RATE_FACTOR, "fundingRateFactor should be smaller than MAX");
        fundingRateFactor[_token][_isLong] = _fundingRateFactor;
        emit SetFundingRateFactor(_token, _isLong, _fundingRateFactor);
    }

    function setLiquidateThreshold(uint256 _newThreshold, address _token) external onlyGov {
        emit UpdateThreshold(liquidateThreshold[_token], _newThreshold);
        require(_newThreshold < BASIS_POINTS_DIVISOR, "threshold should be smaller than MAX");
        liquidateThreshold[_token] = _newThreshold;
    }

    function setLiquidationFeeUsd(uint256 _liquidationFeeUsd) external onlyGov {
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "liquidationFeeUsd should be smaller than MAX");
        liquidationFeeUsd = _liquidationFeeUsd;
        emit SetLiquidationFeeUsd(_liquidationFeeUsd);
    }

    function setMarginFeeBasisPoints(address _token, bool _isLong, uint256 _marginFeeBasisPoints) external onlyGov {
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "marginFeeBasisPoints should be smaller than MAX");
        marginFeeBasisPoints[_token][_isLong] = _marginFeeBasisPoints;
        emit SetMarginFeeBasisPoints(_token, _isLong, _marginFeeBasisPoints);
    }

    function setMaxBorrowAmountPerAsset(address _token, uint256 _maxAmount) external onlyGov {
        maxBorrowUSDAmountPerAsset[_token] = _maxAmount;
        emit SetMaxBorrowAmountPerAsset(_token, _maxAmount);
    }

    function setMaxBorrowAmountPerSide(bool _isLong, uint256 _maxAmount) external onlyGov {
        maxBorrowUSDAmountPerSide[_isLong] = _maxAmount;
        emit SetMaxBorrowAmountPerSide(_isLong, _maxAmount);
    }

    function setMaxBorrowAmountPerUser(uint256 _maxAmount) external onlyGov {
        maxBorrowUSDAmountPerUser = _maxAmount;
        emit SetMaxBorrowAmountPerUser(_maxAmount);
    }

    function setPositionManager(address _manager, bool _isManager) external onlyGov {
        isManager[_manager] = _isManager;
        positionManager = _manager;
        emit SetPositionManager(_manager, _isManager);
    }

    function setReferEnabled(bool _referEnabled) external onlyGov {
        referEnabled = _referEnabled;
        emit ChangedReferEnabled(referEnabled);
    }

    function setReferFee(uint256 _fee) external onlyGov {
        require(_fee <= BASIS_POINTS_DIVISOR, "fee should be smaller than feeDivider");
        referFee = _fee;
        emit ChangedReferFee(_fee);
    }

    function setStakingFee(uint256 _fee) external onlyGov {
        require(_fee <= MAX_STAKING_FEE, "staking fee is bigger than max");
        stakingFee = _fee;
        emit SetStakingFee(_fee);
    }

    function setTriggerGasFee(uint256 _fee) external onlyGov {
        require(_fee <= MAX_TRIGGER_GAS_FEE, "gasFee exceed max");
        triggerGasFee = _fee;
        emit SetTriggerGasFee(_fee);
    }

    function updateCumulativeFundingRate(address _token, bool _isLong) external override onlyVault {
        if (lastFundingTimes[_token][_isLong] == 0) {
            lastFundingTimes[_token][_isLong] = uint256(block.timestamp / fundingInterval) * fundingInterval;
            return;
        }

        if (lastFundingTimes[_token][_isLong] + fundingInterval > block.timestamp) {
            return;
        }

        cumulativeFundingRates[_token][_isLong] += getNextFundingRate(_token, _isLong);
        lastFundingTimes[_token][_isLong] = uint256(block.timestamp / fundingInterval) * fundingInterval;
        emit UpdateFundingRate(
            _token,
            _isLong,
            cumulativeFundingRates[_token][_isLong],
            lastFundingTimes[_token][_isLong]
        );
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
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view override returns (uint256) {
        uint256 feeUsd = getPositionFee(_indexToken, _isLong, _sizeDelta);

        feeUsd += getFundingFee(_indexToken, _isLong, _size, _entryFundingRate);
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
        uint256 borrowedAmount = _size - _collateral;
        require(
            borrowedUsdPerSide[_isLong] + borrowedAmount <=
                (
                    maxBorrowUSDAmountPerSide[_isLong] > 0
                        ? maxBorrowUSDAmountPerSide[_isLong]
                        : DEFAULT_MAX_BORROW_AMOUNT
                ),
            "exceed max borrow amount per side"
        );
        require(
            borrowedUsdPerAsset[_indexToken] + borrowedAmount <=
                (
                    maxBorrowUSDAmountPerAsset[_indexToken] > 0
                        ? maxBorrowUSDAmountPerAsset[_indexToken]
                        : DEFAULT_MAX_BORROW_AMOUNT
                ),
            "exceed max borrow amount per asset"
        );
        require(
            borrowedUsdPerUser[_account] + borrowedAmount <=
                (maxBorrowUSDAmountPerUser > 0 ? maxBorrowUSDAmountPerUser : DEFAULT_MAX_BORROW_AMOUNT),
            "exceed max borrow amount per user"
        );
    }

    function enumerate(EnumerableSet.AddressSet storage set) internal view returns (address[] memory) {
        uint256 length = EnumerableSet.length(set);
        address[] memory output = new address[](length);
        for (uint256 i; i < length; ++i) {
            output[i] = EnumerableSet.at(set, i);
        }
        return output;
    }

    function getNextFundingRate(address _token, bool _isLong) internal view returns (uint256) {
        uint256 intervals = (block.timestamp - lastFundingTimes[_token][_isLong]) / fundingInterval;
        if (positionVault.poolAmounts(_token, _isLong) == 0) {
            return 0;
        }
        return
            ((
                fundingRateFactor[_token][_isLong] > 0
                    ? fundingRateFactor[_token][_isLong]
                    : DEFAULT_FUNDING_RATE_FACTOR
            ) *
                positionVault.reservedAmounts(_token, _isLong) *
                intervals) / positionVault.poolAmounts(_token, _isLong);
    }

    function checkDelegation(address _master, address _delegate) public view override returns (bool) {
        return _master == _delegate || EnumerableSet.contains(_delegatesByMaster[_master], _delegate);
    }

    function getFundingFee(
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryFundingRate
    ) public view override returns (uint256) {
        if (_size == 0) {
            return 0;
        }

        uint256 fundingRate = cumulativeFundingRates[_indexToken][_isLong] - _entryFundingRate;
        if (fundingRate == 0) {
            return 0;
        }

        return (_size * fundingRate) / FUNDING_RATE_PRECISION;
    }

    function getPositionFee(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) public view override returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        return (_sizeDelta * marginFeeBasisPoints[_indexToken][_isLong]) / BASIS_POINTS_DIVISOR;
    }
}
