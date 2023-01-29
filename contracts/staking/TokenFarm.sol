// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IComplexRewarder.sol";
import "./interfaces/ITokenFarm.sol";
import "./libraries/BoringERC20.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IMintable.sol";

contract TokenFarm is ITokenFarm, Constants, Ownable, ReentrancyGuard {
    using BoringERC20 for IBoringERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 startTimestamp;
    }

    // Info of each pool.
    struct PoolInfo {
        IBoringERC20 lpToken; // Address of LP token contract.
        uint256 totalLp; // Total token in Pool
        IComplexRewarder[] rewarders; // Array of rewarder contract for pools with incentives
        bool enableCooldown;
    }
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // The precision factor
    uint256 private immutable ACC_TOKEN_PRECISION = 1e12;
    IBoringERC20 public immutable esToken;
    IBoringERC20 public immutable claimableToken;

    uint256 public cooldownDuration = 1 weeks;
    uint256 public totalLockedVestingAmount;
    uint256 public vestingDuration;
    uint256[] public tierLevels;
    uint256[] public tierPercents;
    // Info of each pool
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public unlockedVestingAmounts;
    mapping(address => uint256) public lastVestingUpdateTimes;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256) public lockedVestingAmounts;

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }

    event Add(
        uint256 indexed pid,
        IBoringERC20 indexed lpToken,
        IComplexRewarder[] indexed rewarders,
        bool _enableCooldown
    );
    event FarmDeposit(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousValue, uint256 newValue);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event Set(uint256 indexed pid, IComplexRewarder[] indexed rewarders);
    event UpdateCooldownDuration(uint256 cooldownDuration);
    event UpdateVestingPeriod(uint256 vestingPeriod);
    event UpdateRewardTierInfo(uint256[] levels, uint256[] percents);
    event VestingClaim(address receiver, uint256 amount);
    event VestingDeposit(address account, uint256 amount);
    event VestingTransfer(address indexed from, address indexed to, uint256 value);
    event VestingWithdraw(address account, uint256 claimedAmount, uint256 balance);
    event FarmWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(uint256 _vestingDuration, IBoringERC20 _esToken, IBoringERC20 _claimableToken) {
        //StartBlock always many years later from contract const ruct, will be set later in StartFarming function
        claimableToken = _claimableToken;
        esToken = _esToken;
        vestingDuration = _vestingDuration;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Can add multiple pool with same lp token without messing up rewards, because each pool's balance is tracked using its own totalLp
    function add(
        IBoringERC20 _lpToken,
        IComplexRewarder[] calldata _rewarders,
        bool _enableCooldown
    ) external onlyOwner {
        require(_rewarders.length <= 10, "add: too many rewarders");
        require(Address.isContract(address(_lpToken)), "add: LP token must be a valid contract");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "add: rewarder must be contract");
        }

        poolInfo.push(
            PoolInfo({lpToken: _lpToken, totalLp: 0, rewarders: _rewarders, enableCooldown: _enableCooldown})
        );

        emit Add(poolInfo.length - 1, _lpToken, _rewarders, _enableCooldown);
    }

    // Function to harvest many pools in a single transaction
    function harvestMany(uint256[] calldata _pids) external nonReentrant {
        require(_pids.length <= 30, "harvest many: too many pool ids");
        for (uint256 index = 0; index < _pids.length; ++index) {
            _deposit(_pids[index], 0);
        }
    }

    // Deposit tokens for Vela allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        _deposit(_pid, _amount);
    }

    function depositVesting(uint256 _amount) external nonReentrant {
        _depositVesting(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration <= block.timestamp,
                "didn't pass cooldownDuration"
            );
            pool.lpToken.safeTransfer(msg.sender, _amount);
            pool.totalLp -= _amount;
        }
        user.amount = 0;
        emit EmergencyWithdraw(msg.sender, _amount, _pid);
    }

    // Update the given pool's Vela allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, IComplexRewarder[] calldata _rewarders) external onlyOwner validatePoolByPid(_pid) {
        require(_rewarders.length <= 10, "set: too many rewarders");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "set: rewarder must be contract");
        }

        poolInfo[_pid].rewarders = _rewarders;

        emit Set(_pid, _rewarders);
    }

    function updateCooldownDuration(uint256 _newCooldownDuration) external onlyOwner {
        require(_newCooldownDuration <= MAX_TOKENFARM_COOLDOWN_DURATION, "cooldown duration exceeds max");
        cooldownDuration = _newCooldownDuration;
        emit UpdateCooldownDuration(_newCooldownDuration);
    }

    function updateRewardTierInfo(uint256[] memory _levels, uint256[] memory _percents) external onlyOwner {
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

    function updateVestingDuration(uint256 _vestingDuration) external onlyOwner {
        require(_vestingDuration <= MAX_VESTING_DURATION, "vesting duration exceeds max");
        vestingDuration = _vestingDuration;
        emit UpdateVestingPeriod(_vestingDuration);
    }

    //withdraw tokens
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.amount >= _amount, "withdraw: user amount not enough");

        if (_amount > 0) {
            require(
                !pool.enableCooldown || user.startTimestamp + cooldownDuration < block.timestamp,
                "didn't pass cooldownDuration"
            );
            user.amount -= _amount;
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.amount);
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit FarmWithdraw(msg.sender, _pid, _amount);
    }

    function withdrawVesting() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        uint256 totalClaimed = _claim(account, _receiver);

        uint256 totalLocked = lockedVestingAmounts[account];
        require(totalLocked + totalClaimed > 0, "Vester: vested amount is zero");

        esToken.safeTransfer(_receiver, totalLocked);
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
        claimableToken.safeTransfer(_receiver, amount);
        emit VestingClaim(_account, amount);
        return amount;
    }

    function _decreaseLockedVestingAmount(address _account, uint256 _amount) internal {
        lockedVestingAmounts[_account] -= _amount;
        totalLockedVestingAmount -= _amount;

        emit VestingTransfer(_account, ZERO_ADDRESS, _amount);
    }

    // Deposit tokens for Vela allocation.
    function _deposit(uint256 _pid, uint256 _amount) internal validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount > 0) {
            uint256 beforeDeposit = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 afterDeposit = pool.lpToken.balanceOf(address(this));

            _amount = afterDeposit - beforeDeposit;
            user.amount += _amount;
            user.startTimestamp = block.timestamp;
        }

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            pool.rewarders[rewarderId].onVelaReward(_pid, msg.sender, user.amount);
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }

        emit FarmDeposit(msg.sender, _pid, _amount);
    }

    function _depositVesting(address _account, uint256 _amount) internal {
        require(_amount > 0, "Vester: invalid _amount");
        // note: the check here were moved to `_getNextClaimableAmount`, which is the only place
        //      that reads `lastVestingTimes[_account]`. Now `_getNextClaimableAmount(..)` is safe to call
        //      in any context, because it handles uninitialized `lastVestingTimes[_account]` on it's own.
        _updateVesting(_account);

        esToken.safeTransferFrom(_account, address(this), _amount);

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
        IMintable(address(esToken)).burn(address(this), unlockedThisTime);
    }

    function getTier(uint256 _pid, address _account) external view override returns (uint256) {
        UserInfo storage user = userInfo[_pid][_account];
        if (tierLevels.length == 0 || user.amount < tierLevels[0]) {
            return BASIS_POINTS_DIVISOR;
        }
        unchecked {
            for (uint16 i = 1; i != tierLevels.length; ++i) {
                if (user.amount < tierLevels[i]) {
                    return tierPercents[i - 1];
                }
            }
            return tierPercents[tierLevels.length - 1];
        }
    }

    function getTotalVested(address _account) external view returns (uint256) {
        return (lockedVestingAmounts[_account] + unlockedVestingAmounts[_account]);
    }

    // View function to see pending rewards on frontend.
    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
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

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see rewarders for a pool
    function poolRewarders(uint256 _pid) external view validatePoolByPid(_pid) returns (address[] memory rewarders) {
        PoolInfo storage pool = poolInfo[_pid];
        rewarders = new address[](pool.rewarders.length);
        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            rewarders[rewarderId] = address(pool.rewarders[rewarderId]);
        }
    }

    /// @notice View function to see pool rewards per sec
    function poolRewardsPerSec(
        uint256 _pid
    )
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory rewardsPerSec
        )
    {
        PoolInfo storage pool = poolInfo[_pid];

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

    function poolTotalLp(uint256 pid) external view returns (uint256) {
        return poolInfo[pid].totalLp;
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
    function _validateLevels(uint256[] memory _levels) internal pure returns (bool) {
        unchecked {
            for (uint16 i = 1; i != _levels.length; ++i) {
                if (_levels[i-1] >= _levels[i]) {
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
