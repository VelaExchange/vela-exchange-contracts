// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IComplexRewarder.sol";
import "./interfaces/ITokenFarm.sol";
import "./libraries/BoringERC20.sol";
import "../core/interfaces/IOperators.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IMintable.sol";

contract TokenFarm is ITokenFarm, Constants, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using BoringERC20 for IBoringERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 startTimestamp;
    }

    struct VelaUserInfo {
        uint256 velaAmount;
        uint256 esvelaAmount;
        uint256 startTimestamp;
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 totalLp; // Total token in Pool
        IComplexRewarder[] rewarders; // Array of rewarder contract for pools with incentives
        bool enableCooldown;
    }
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // The precision factor
    uint256 private immutable ACC_TOKEN_PRECISION = 1e12;
    IBoringERC20 public immutable esVELA;
    IBoringERC20 public immutable VELA;
    IBoringERC20 public immutable VLP;
    IOperators public immutable operators;
    EnumerableSet.AddressSet private cooldownWhiteList;
    uint256 public cooldownDuration = 1 weeks;
    uint256 public totalLockedVestingAmount;
    uint256 public vestingDuration;
    uint256[] public tierLevels;
    uint256[] public tierPercents;
    // Info of each pool
    PoolInfo public velaPoolInfo;
    PoolInfo public vlpPoolInfo;
    //PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public unlockedVestingAmounts;
    mapping(address => uint256) public lastVestingUpdateTimes;
    mapping(address => VelaUserInfo) public velaUserInfo;
    mapping(address => UserInfo) public vlpUserInfo;
    mapping(address => uint256) public lockedVestingAmounts;

    event FarmDeposit(address indexed user, IBoringERC20 indexed token, uint256 amount);
    event EmergencyWithdraw(address indexed user, IBoringERC20 indexed token, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousValue, uint256 newValue);
    event MintVestingToken(address indexed account, uint256 amount);
    event RewardLockedUp(address indexed user, IBoringERC20 indexed token, uint256 amountLockedUp);
    event Set(IBoringERC20 indexed token, IComplexRewarder[] indexed rewarders);
    event UpdateCooldownDuration(uint256 cooldownDuration);
    event UpdateVestingPeriod(uint256 vestingPeriod);
    event UpdateRewardTierInfo(uint256[] levels, uint256[] percents);
    event VestingClaim(address receiver, uint256 amount);
    event VestingDeposit(address account, uint256 amount);
    event VestingTransfer(address indexed from, address indexed to, uint256 value);
    event VestingWithdraw(address account, uint256 claimedAmount, uint256 balance);
    event FarmWithdraw(address indexed user, IBoringERC20 indexed token, uint256 amount);

    constructor(
        uint256 _vestingDuration,
        IBoringERC20 _esVELA,
        IBoringERC20 _VELA,
        IBoringERC20 _vlp,
        address _operators
    ) {
        //StartBlock always many years later from contract const ruct, will be set later in StartFarming function
        require(Address.isContract(_operators), "operators invalid");
        operators = IOperators(_operators);
        VELA = _VELA;
        esVELA = _esVELA;
        VLP = _vlp;
        vestingDuration = _vestingDuration;
    }
    function addDelegatesToCooldownWhiteList(address[] memory _delegates) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.add(cooldownWhiteList, _delegates[i]);
        }
    }

    function removeDelegatesFromCooldownWhiteList(address[] memory _delegates) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSet.remove(cooldownWhiteList, _delegates[i]);
        }
    }

    function checkCooldownWhiteList(address _delegate) public view returns (bool) {
        return EnumerableSet.contains(cooldownWhiteList, _delegate);
    }
    

    // ----- START: Operator Logic -----
    // Update rewarders and enableCooldown for pools
    function setVelaPool(IComplexRewarder[] calldata _rewarders, bool _enableCooldown) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_rewarders.length <= 10, "set: too many rewarders");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "set: rewarder must be contract");
        }

        velaPoolInfo.rewarders = _rewarders;
        velaPoolInfo.enableCooldown = _enableCooldown;

        emit Set(VELA, _rewarders);
    }

    function setVlpPool(IComplexRewarder[] calldata _rewarders, bool _enableCooldown) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_rewarders.length <= 10, "set: too many rewarders");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "set: rewarder must be contract");
        }

        vlpPoolInfo.rewarders = _rewarders;
        vlpPoolInfo.enableCooldown = _enableCooldown;

        emit Set(VLP, _rewarders);
    }

    function updateCooldownDuration(uint256 _newCooldownDuration) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_newCooldownDuration <= MAX_TOKENFARM_COOLDOWN_DURATION, "cooldown duration exceeds max");
        cooldownDuration = _newCooldownDuration;
        emit UpdateCooldownDuration(_newCooldownDuration);
    }

    function updateRewardTierInfo(uint256[] memory _levels, uint256[] memory _percents) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        uint256 totalLength = tierLevels.length;
        require(_levels.length == _percents.length, "the length should the same");
        require(_validateLevels(_levels), "levels not sorted");
        require(_validatePercents(_percents), "percents exceed 100%");
        for (uint256 i = 0; i < totalLength; i++) {
            tierLevels.pop();
            tierPercents.pop();
        }
        for (uint256 j = 0; j < _levels.length; j++) {
            tierLevels.push(_levels[j]);
            tierPercents.push(_percents[j]);
        }
        emit UpdateRewardTierInfo(_levels, _percents);
    }

    function updateVestingDuration(uint256 _vestingDuration) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_vestingDuration <= MAX_VESTING_DURATION, "vesting duration exceeds max");
        vestingDuration = _vestingDuration;
        emit UpdateVestingPeriod(_vestingDuration);
    }

    // ----- END: Operator Logic -----

    // ----- START: Vesting esVELA -> VELA -----

    function claim() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        _claim(account, _receiver);
    }

    function claimable(address _account) public view returns (uint256) {
        uint256 amount = unlockedVestingAmounts[_account] - claimedAmounts[_account];
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        return (amount + nextClaimable);
    }

    function getVestedAmount(address _account) public view returns (uint256) {
        uint256 balance = lockedVestingAmounts[_account];
        uint256 cumulativeClaimAmount = unlockedVestingAmounts[_account];
        return (balance + cumulativeClaimAmount);
    }

    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 lockedAmount = lockedVestingAmounts[_account];
        if (lockedAmount == 0) {
            return 0;
        }
        uint256 timeDiff = block.timestamp - lastVestingUpdateTimes[_account];
        // `timeDiff == block.timestamp` means `lastVestingTimes[_account]` has not been initialized
        if (timeDiff == 0 || timeDiff == block.timestamp) {
            return 0;
        }

        uint256 vestedAmount = lockedAmount + unlockedVestingAmounts[_account];
        uint256 claimableAmount = (vestedAmount * timeDiff) / vestingDuration;

        if (claimableAmount < lockedAmount) {
            return claimableAmount;
        }

        return lockedAmount;
    }

    function withdrawVesting() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        uint256 totalClaimed = _claim(account, _receiver);

        uint256 totalLocked = lockedVestingAmounts[account];
        require(totalLocked + totalClaimed > 0, "Vester: vested amount is zero");

        esVELA.safeTransfer(_receiver, totalLocked);
        _decreaseLockedVestingAmount(account, totalLocked);

        delete unlockedVestingAmounts[account];
        delete claimedAmounts[account];
        delete lastVestingUpdateTimes[account];

        emit VestingWithdraw(account, totalClaimed, totalLocked);
    }

    function _claim(address _account, address _receiver) internal returns (uint256) {
        _updateVesting(_account);
        uint256 amount = claimable(_account);
        claimedAmounts[_account] = claimedAmounts[_account] + amount;
        VELA.safeTransfer(_receiver, amount);
        emit VestingClaim(_account, amount);
        return amount;
    }

    function depositVesting(uint256 _amount) external nonReentrant {
        _depositVesting(msg.sender, _amount);
    }

    function depositVelaForVesting(uint256 _amount) external nonReentrant {
        require(_amount > 0, "zero amount");
        VELA.safeTransferFrom(msg.sender, address(this), _amount); //transfer VELA in
        esVELA.mint(msg.sender, _amount);
        emit MintVestingToken(msg.sender, _amount);
    }

    function _decreaseLockedVestingAmount(address _account, uint256 _amount) internal {
        lockedVestingAmounts[_account] -= _amount;
        totalLockedVestingAmount -= _amount;

        emit VestingTransfer(_account, ZERO_ADDRESS, _amount);
    }

    function _depositVesting(address _account, uint256 _amount) internal {
        require(_amount > 0, "Vester: invalid _amount");
        // note: the check here were moved to `_getNextClaimableAmount`, which is the only place
        //      that reads `lastVestingTimes[_account]`. Now `_getNextClaimableAmount(..)` is safe to call
        //      in any context, because it handles uninitialized `lastVestingTimes[_account]` on it's own.
        _updateVesting(_account);

        esVELA.safeTransferFrom(_account, address(this), _amount);

        _increaseLockedVestingAmount(_account, _amount);

        emit VestingDeposit(_account, _amount);
    }

    function _increaseLockedVestingAmount(address _account, uint256 _amount) internal {
        require(_account != ZERO_ADDRESS, "Vester: mint to the zero address");

        totalLockedVestingAmount += _amount;
        lockedVestingAmounts[_account] += _amount;

        emit VestingTransfer(ZERO_ADDRESS, _account, _amount);
    }

    function _updateVesting(address _account) internal {
        uint256 unlockedThisTime = _getNextClaimableAmount(_account);
        lastVestingUpdateTimes[_account] = block.timestamp;

        if (unlockedThisTime == 0) {
            return;
        }

        // transfer claimableAmount from balances to unlocked amounts
        _decreaseLockedVestingAmount(_account, unlockedThisTime);
        unlockedVestingAmounts[_account] += unlockedThisTime;
        IMintable(address(esVELA)).burn(address(this), unlockedThisTime);
    }

    function getTotalVested(address _account) external view returns (uint256) {
        return (lockedVestingAmounts[_account] + unlockedVestingAmounts[_account]);
    }

    // ----- END: Vesting esVELA -> VELA -----

    // ----- START: VELA Pool, pid=0, token VELA -----
    function depositVela(uint256 _amount) external nonReentrant {
        _depositVela(_amount);
    }

    function _depositVela(uint256 _amount) internal {
        uint256 _pid = 0;
        PoolInfo storage pool = velaPoolInfo;
        VelaUserInfo storage user = velaUserInfo[msg.sender];

        if (_amount > 0) {
            VELA.safeTransferFrom(msg.sender, address(this), _amount);
            user.velaAmount += _amount;
            user.startTimestamp = block.timestamp;
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.velaAmount + user.esvelaAmount);
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }
        emit FarmDeposit(msg.sender, VELA, _amount);
    }

    //withdraw tokens
    function withdrawVela(uint256 _amount) external nonReentrant {
        uint256 _pid = 0;
        PoolInfo storage pool = velaPoolInfo;
        VelaUserInfo storage user = velaUserInfo[msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.velaAmount >= _amount, "withdraw: user amount not enough");

        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration < block.timestamp,
                "didn't pass cooldownDuration"
            );
            user.velaAmount -= _amount;
            VELA.safeTransfer(msg.sender, _amount);
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.velaAmount + user.esvelaAmount);
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit FarmWithdraw(msg.sender, VELA, _amount);
    }

    // ----- END: VELA Pool, pid=0, token VELA -----

    // ----- START: VELA Pool, pid=0, token esVELA -----
    function depositEsvela(uint256 _amount) external nonReentrant {
        _depositEsvela(_amount);
    }

    function _depositEsvela(uint256 _amount) internal {
        uint256 _pid = 0;
        PoolInfo storage pool = velaPoolInfo;
        VelaUserInfo storage user = velaUserInfo[msg.sender];

        if (_amount > 0) {
            esVELA.safeTransferFrom(msg.sender, address(this), _amount);
            user.esvelaAmount += _amount;
            user.startTimestamp = block.timestamp;
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.velaAmount + user.esvelaAmount);
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }
        emit FarmDeposit(msg.sender, esVELA, _amount);
    }

    //withdraw tokens
    function withdrawEsvela(uint256 _amount) external nonReentrant {
        uint256 _pid = 0;
        PoolInfo storage pool = velaPoolInfo;
        VelaUserInfo storage user = velaUserInfo[msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.esvelaAmount >= _amount, "withdraw: user amount not enough");

        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration < block.timestamp,
                "didn't pass cooldownDuration"
            );
            user.esvelaAmount -= _amount;
            esVELA.safeTransfer(msg.sender, _amount);
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.velaAmount + user.esvelaAmount);
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit FarmWithdraw(msg.sender, esVELA, _amount);
    }

    // ----- END: VELA Pool, pid=0, token esVELA -----

    // ----- START: both VELA and esVELA, pid=0
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // token VELA and esVELA
    function emergencyWithdrawVela() external nonReentrant {
        PoolInfo storage pool = velaPoolInfo;
        VelaUserInfo storage user = velaUserInfo[msg.sender];
        uint256 _amount = user.velaAmount;
        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration <= block.timestamp,
                "didn't pass cooldownDuration"
            );
            VELA.safeTransfer(msg.sender, _amount);
            pool.totalLp -= _amount;
        }
        user.velaAmount = 0;
        emit EmergencyWithdraw(msg.sender, VELA, _amount);
        _amount = user.esvelaAmount;
        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration <= block.timestamp,
                "didn't pass cooldownDuration"
            );
            esVELA.safeTransfer(msg.sender, _amount);
            pool.totalLp -= _amount;
        }
        user.velaAmount = 0;
        emit EmergencyWithdraw(msg.sender, esVELA, _amount);
    }

    // ----- END: both VELA and esVELA, pid=0

    // ----- START: VLP Pool, pid=1, token VLP -----

    function depositVlp(uint256 _amount) external {
        _depositVlp(_amount);
    }

    function _depositVlp(uint256 _amount) internal {
        uint256 _pid = 1;
        PoolInfo storage pool = vlpPoolInfo;
        UserInfo storage user = vlpUserInfo[msg.sender];
        if (_amount > 0) {
            VLP.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount += _amount;
            user.startTimestamp = block.timestamp;
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.amount);
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }
        emit FarmDeposit(msg.sender, VLP, _amount);
    }

    function emergencyWithdrawVlp() external {
        PoolInfo storage pool = vlpPoolInfo;
        UserInfo storage user = vlpUserInfo[msg.sender];
        uint256 _amount = user.amount;
        if (_amount > 0) {
            if (!checkCooldownWhiteList(msg.sender)) {
                require(
                    !pool.enableCooldown || user.startTimestamp + cooldownDuration <= block.timestamp,
                    "didn't pass cooldownDuration"
                );
            }
            VLP.safeTransfer(msg.sender, _amount);
            pool.totalLp -= _amount;
        }
        user.amount = 0;
        emit EmergencyWithdraw(msg.sender, VLP, _amount);
    }

    //withdraw tokens
    function withdrawVlp(uint256 _amount) external nonReentrant {
        uint256 _pid = 1;
        PoolInfo storage pool = vlpPoolInfo;
        UserInfo storage user = vlpUserInfo[msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.amount >= _amount, "withdraw: user amount not enough");

        if (_amount > 0) {
            if (!checkCooldownWhiteList(msg.sender)) {
                require(
                    !pool.enableCooldown || user.startTimestamp + cooldownDuration < block.timestamp,
                    "didn't pass cooldownDuration"
                );
            }
            user.amount -= _amount;
            VLP.safeTransfer(msg.sender, _amount);
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.amount);
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit FarmWithdraw(msg.sender, VLP, _amount);
    }

    // ----- END: VLP Pool, pid=1, token VLP -----

    // View function to see rewarders for a pool
    function poolRewarders(bool _isVelaPool) external view returns (address[] memory rewarders) {
        PoolInfo storage pool;
        if (_isVelaPool) {
            pool = velaPoolInfo;
        } else {
            pool = vlpPoolInfo;
        }
        rewarders = new address[](pool.rewarders.length);
        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            rewarders[rewarderId] = address(pool.rewarders[rewarderId]);
        }
    }

    /// @notice View function to see pool rewards per sec
    function poolRewardsPerSec(
        bool _isVelaPool
    )
        external
        view
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory rewardsPerSec
        )
    {
        uint256 _pid;
        PoolInfo storage pool;
        if (_isVelaPool) {
            _pid = 0;
            pool = velaPoolInfo;
        } else {
            _pid = 1;
            pool = vlpPoolInfo;
        }

        addresses = new address[](pool.rewarders.length);
        symbols = new string[](pool.rewarders.length);
        decimals = new uint256[](pool.rewarders.length);
        rewardsPerSec = new uint256[](pool.rewarders.length);

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            addresses[rewarderId] = address(pool.rewarders[rewarderId].rewardToken());

            symbols[rewarderId] = IBoringERC20(pool.rewarders[rewarderId].rewardToken()).safeSymbol();

            decimals[rewarderId] = IBoringERC20(pool.rewarders[rewarderId].rewardToken()).safeDecimals();

            rewardsPerSec[rewarderId] = pool.rewarders[rewarderId].poolRewardsPerSec(_pid);
        }
    }

    function poolTotalLp(uint256 _pid) external view returns (uint256) {
        PoolInfo storage pool;
        if (_pid == 0) {
            pool = velaPoolInfo;
        } else {
            pool = vlpPoolInfo;
        }
        return pool.totalLp;
    }

    // View function to see pending rewards on frontend.
    function pendingTokens(
        bool _isVelaPool,
        address _user
    )
        external
        view
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        )
    {
        uint256 _pid;
        PoolInfo storage pool;
        if (_isVelaPool) {
            _pid = 0;
            pool = velaPoolInfo;
        } else {
            _pid = 1;
            pool = vlpPoolInfo;
        }
        addresses = new address[](pool.rewarders.length);
        symbols = new string[](pool.rewarders.length);
        amounts = new uint256[](pool.rewarders.length);
        decimals = new uint256[](pool.rewarders.length);

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            addresses[rewarderId] = address(pool.rewarders[rewarderId].rewardToken());

            symbols[rewarderId] = IBoringERC20(pool.rewarders[rewarderId].rewardToken()).safeSymbol();

            decimals[rewarderId] = IBoringERC20(pool.rewarders[rewarderId].rewardToken()).safeDecimals();
            amounts[rewarderId] = pool.rewarders[rewarderId].pendingTokens(_pid, _user);
        }
    }

    // Function to harvest many pools in a single transaction
    function harvestMany(bool _vela, bool _esvela, bool _vlp) external nonReentrant {
        if (_vela) {
            _depositVela(0);
        }
        if (_esvela) {
            _depositEsvela(0);
        }
        if (_vlp) {
            _depositVlp(0);
        }
    }

    function getTierVela(address _account) external view override returns (uint256) {
        VelaUserInfo storage user = velaUserInfo[_account];
        uint256 amount = user.velaAmount + user.esvelaAmount;
        if (tierLevels.length == 0 || amount < tierLevels[0]) {
            return BASIS_POINTS_DIVISOR;
        }
        unchecked {
            for (uint16 i = 1; i != tierLevels.length; ++i) {
                if (amount < tierLevels[i]) {
                    return tierPercents[i - 1];
                }
            }
            return tierPercents[tierLevels.length - 1];
        }
    }

    function _validateLevels(uint256[] memory _levels) internal pure returns (bool) {
        unchecked {
            for (uint16 i = 1; i != _levels.length; ++i) {
                if (_levels[i - 1] >= _levels[i]) {
                    return false;
                }
            }
            return true;
        }
    }

    function _validatePercents(uint256[] memory _percents) internal pure returns (bool) {
        unchecked {
            for (uint16 i = 0; i != _percents.length; ++i) {
                if (_percents[i] > BASIS_POINTS_DIVISOR) {
                    return false;
                }
            }
            return true;
        }
    }
}
