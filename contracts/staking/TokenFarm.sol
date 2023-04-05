// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ITokenFarm.sol";
import "./libraries/BoringERC20.sol";
import "../core/interfaces/IOperators.sol";
import {Constants} from "../access/Constants.sol";
import "../tokens/interfaces/IMintable.sol";

contract TokenFarm is ITokenFarm, Constants, Ownable, ReentrancyGuard {
    using BoringERC20 for IBoringERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 startTimestamp;
        uint256 rewardDebt; /// `rewardDebt` The amount of REWARD entitled to the user.
    }

    // Info of each pool.
    struct PoolInfo {
        bool enableCooldown;
        IBoringERC20 lpToken; // Address of LP token contract.
        IBoringERC20[] rewarders; // Array of rewarder contract for pools with incentives
        uint256 totalLp; // Total token in Pool
    }

    struct PoolRewarder {
        uint256 accTokenPerShare; /// `accTokenPerShare` Amount of REWARD each LP token is worth.
        uint256 startTimestamp; /// `startTimestamp` The start timestamp of rewards.
        uint256 lastRewardTimestamp; /// `lastRewardTimestamp` The last timestamp REWARD was rewarded to the poolInfo.
        uint256 totalRewards; /// `totalRewards` The amount of rewards added to the pool.
    }

    struct RewardInfo {
        uint256 startTimestamp; /// `startTimestamp` The start timestamp of rewards
        uint256 endTimestamp; /// `endTimestamp` The end timestamp of rewards
        uint256 rewardPerSec; /// `rewardPerSec` The amount of rewards per second
    }
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // The precision factor
    uint256 private immutable ACC_TOKEN_PRECISION = 1e12;
    IBoringERC20 public immutable esToken;
    IBoringERC20 public immutable claimableToken;
    IOperators public immutable operators;

    uint256 public cooldownDuration = 1 weeks;
    uint256 public totalLockedVestingAmount;
    uint256 public vestingDuration;
    uint256[] public tierLevels;
    uint256[] public tierPercents;
    uint256 public immutable rewardInfoLimit = 52; //1y /// how many phases are allowed
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public lastVestingUpdateTimes;
    mapping(address => uint256) public lockedVestingAmounts;
    mapping(address => uint256) public unlockedVestingAmounts;
    mapping(uint256 => mapping(uint256 => PoolRewarder)) public poolRewarder;
    mapping(uint256 => mapping(uint256 => RewardInfo[])) public rewardsInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }

    event AddPoolInfo(
        uint256 indexed pid,
        IBoringERC20 indexed lpToken,
        IBoringERC20[] indexed rewarders,
        bool _enableCooldown
    );
    event AddRewardInfo(uint256 indexed pid, uint256 rewardId, uint256 indexed phase, uint256 endTimestamp, uint256 rewardPerSec);
    event FarmConvert(address indexed user, uint256 amount);
    event FarmDeposit(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousValue, uint256 newValue);
    event MintVestingToken(address indexed account, uint256 amount);
    event OnReward(address indexed user, uint256 pid, uint256 rewardId, uint256 amount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event Set(uint256 indexed pid, IBoringERC20[] indexed rewarders);
    event UpdateCooldownDuration(uint256 cooldownDuration);
    event UpdateVestingPeriod(uint256 vestingPeriod);
    event UpdateRewardTierInfo(uint256[] levels, uint256[] percents);
    event VestingClaim(address receiver, uint256 amount);
    event VestingDeposit(address account, uint256 amount);
    event VestingTransfer(address indexed from, address indexed to, uint256 value);
    event VestingWithdraw(address account, uint256 claimedAmount, uint256 balance);
    event FarmWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(uint256 _vestingDuration, IBoringERC20 _esToken, IBoringERC20 _claimableToken, address _operators) {
        //StartBlock always many years later from contract const ruct, will be set later in StartFarming function
        require(Address.isContract(_operators), "operators invalid");
        operators = IOperators(_operators);
        claimableToken = _claimableToken;
        esToken = _esToken;
        vestingDuration = _vestingDuration;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Can add multiple pool with same lp token without messing up rewards, because each pool's balance is tracked using its own totalLp
    function addPoolInfo(
        IBoringERC20 _lpToken,
        IBoringERC20[] calldata _rewarders,
        bool _enableCooldown,
        uint256 _startTimestamp
    ) external {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_rewarders.length <= 10, "add: too many rewarders");
        require(Address.isContract(address(_lpToken)), "add: LP token must be a valid contract");
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "add: rewarder must be contract");
        }

        poolInfo.push(
            PoolInfo({lpToken: _lpToken, totalLp: 0, rewarders: _rewarders, enableCooldown: _enableCooldown})
        );
        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
                poolRewarder[poolInfo.length - 1][rewarderId] = PoolRewarder({
                startTimestamp: _startTimestamp,
                lastRewardTimestamp: _startTimestamp,
                accTokenPerShare: 0,
                totalRewards: 0
            });

        }
        emit AddPoolInfo(poolInfo.length - 1, _lpToken, _rewarders, _enableCooldown);
    }

    /// @notice if the new reward info is added, the reward & its end timestamp will be extended by the newly pushed reward info.
    function addRewardInfo(uint256 _pid, uint256 _endTimestamp, uint256[] calldata _rewardPerSecs) external payable {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        PoolInfo storage pool = poolInfo[_pid];
        for (uint256 rewardId = 0; rewardId < _rewardPerSecs.length; rewardId++) {
            RewardInfo[] storage rewardInfo = rewardsInfo[_pid][rewardId];
            PoolRewarder storage rewarderPool = poolRewarder[_pid][rewardId];
            require(rewardInfo.length < rewardInfoLimit, "add reward info: reward info length exceeds the limit");
            require(
                rewardInfo.length == 0 || rewardInfo[rewardInfo.length - 1].endTimestamp >= block.timestamp,
                "add reward info: reward period ended"
            );
            require(
                rewardInfo.length == 0 || rewardInfo[rewardInfo.length - 1].endTimestamp < _endTimestamp,
                "add reward info: bad new endTimestamp"
            );

            uint256 startTimestamp = rewardInfo.length == 0
                ? rewarderPool.startTimestamp
                : rewardInfo[rewardInfo.length - 1].endTimestamp;

            uint256 timeRange = _endTimestamp - startTimestamp;
            uint256 totalRewards = timeRange * _rewardPerSecs[rewardId];
            pool.rewarders[rewardId].safeTransferFrom(msg.sender, address(this), totalRewards);

            rewarderPool.totalRewards += totalRewards;

            rewardInfo.push(
                RewardInfo({startTimestamp: startTimestamp, endTimestamp: _endTimestamp, rewardPerSec: _rewardPerSecs[rewardId]})
            );

            emit AddRewardInfo(_pid, rewardId, rewardInfo.length - 1, _endTimestamp, _rewardPerSecs[rewardId]);
        }
    }

    // Function to harvest many pools in a single transaction
    function harvestMany(uint256[] calldata _pids) external nonReentrant {
        require(_pids.length <= 30, "harvest many: too many pool ids");
        for (uint256 index = 0; index < _pids.length; ++index) {
            _deposit(_pids[index], 0);
        }
    }

    function claim() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        _claim(account, _receiver);
    }

    // Deposit tokens for Vela allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        _deposit(_pid, _amount);
    }

    function depositVesting(uint256 _amount) external nonReentrant {
        _depositVesting(msg.sender, _amount);
    }

    function depositVelaForVesting(uint256 _amount) external nonReentrant {
        require (_amount > 0, "zero amount");
        claimableToken.safeTransferFrom(msg.sender, address(this), _amount); //transfer VELA in
        esToken.mint(msg.sender, _amount);
        emit MintVestingToken(msg.sender, _amount);
    }

    function depositWithConvert(uint256 _pid, uint256 _amount) external nonReentrant {
        require (_amount > 0, "zero amount");
        claimableToken.safeTransferFrom(msg.sender, address(this), _amount); //transfer VELA in

        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lpToken == esToken, "target pool not esVELA"); // target _pid must be esVELA pool
        UserInfo storage user = userInfo[_pid][msg.sender];

        esToken.mint(address(this), _amount);

        user.amount += _amount;
        user.startTimestamp = block.timestamp;

        for (uint256 rewarderId = 0; rewarderId < pool.rewarders.length; ++rewarderId) {
            onReward(_pid, rewarderId, msg.sender, user.amount);
        }

        pool.totalLp += _amount;

        emit FarmConvert(msg.sender, _amount);
        emit MintVestingToken(address(this), _amount);
        emit FarmDeposit(msg.sender, _pid, _amount);
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

    function onReward(uint256 _pid, uint256 _rewarderId, address _user, uint256 _amount) internal {
        PoolRewarder memory rewarderPool = _updatePool(_pid, _rewarderId);
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        uint256 pending = 0;
        uint256 rewardBalance = 0;

        rewardBalance = pool.rewarders[_rewarderId].balanceOf(address(this));

        if (user.amount > 0) {
            pending = (((user.amount * rewarderPool.accTokenPerShare) / ACC_TOKEN_PRECISION) - user.rewardDebt);

            if (pending > 0) {
                if (pending > rewardBalance) {
                    pool.rewarders[_rewarderId].safeTransfer(_user, rewardBalance);
                } else {
                    pool.rewarders[_rewarderId].safeTransfer(_user, pending);
                }
            }
        }

        user.amount = _amount;

        user.rewardDebt = (user.amount * rewarderPool.accTokenPerShare) / ACC_TOKEN_PRECISION;

        emit OnReward(_user, _pid, _rewarderId, pending);
    }

    // Update the given pool's Vela allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, IBoringERC20[] calldata _rewarders, uint256 _startTimestamp) external validatePoolByPid(_pid) {
        require(operators.getOperatorLevel(msg.sender) >= uint8(1), "Invalid operator");
        require(_rewarders.length <= 10, "set: too many rewarders");

        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
            require(Address.isContract(address(_rewarders[rewarderId])), "set: rewarder must be contract");
        }

        poolInfo[_pid].rewarders = _rewarders;
        for (uint256 rewarderId = 0; rewarderId < _rewarders.length; ++rewarderId) {
                poolRewarder[poolInfo.length - 1][rewarderId] = PoolRewarder({
                startTimestamp: _startTimestamp,
                lastRewardTimestamp: _startTimestamp,
                accTokenPerShare: 0,
                totalRewards: 0
            });
        }
        emit Set(_pid, _rewarders);
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
            onReward(_pid, rewarderId, msg.sender, user.amount);
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
            onReward(_pid, rewarderId, msg.sender, user.amount);
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

    function getTimeElapsed(uint256 _from, uint256 _to, uint256 _endTimestamp) public pure returns (uint256) {
        if ((_from >= _endTimestamp) || (_from > _to)) {
            return 0;
        }
        if (_to <= _endTimestamp) {
            return _to - _from;
        }
        return _endTimestamp - _from;
    }

    function _endTimestampOf(uint256 _pid, uint256 _rewarderId, uint256 _timestamp) internal view returns (uint256) {
        RewardInfo[] memory rewardInfo = rewardsInfo[_pid][_rewarderId];
        uint256 len = rewardInfo.length;
        if (len == 0) {
            return 0;
        }
        for (uint256 i = 0; i < len; ++i) {
            if (_timestamp <= rewardInfo[i].endTimestamp) return rewardInfo[i].endTimestamp;
        }

        /// @dev when couldn't find any reward info, it means that _timestamp exceed endTimestamp
        /// so return the latest reward info.
        return rewardInfo[len - 1].endTimestamp;
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function _updatePool(uint256 pid, uint256 rewarderId) internal returns (PoolRewarder memory pool) {
        RewardInfo[] storage rewardInfo = rewardsInfo[pid][rewarderId];
        pool = poolRewarder[pid][rewarderId];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return pool;
        }

        uint256 lpSupply = poolInfo[pid].totalLp;

        if (lpSupply == 0) {
            // if there is no total supply, return and use the pool's start timestamp as the last reward timestamp
            // so that ALL reward will be distributed.
            // however, if the first deposit is out of reward period, last reward timestamp will be its timestamp
            // in order to keep the multiplier = 0
            if (block.timestamp > _endTimestampOf(pid, rewarderId, block.timestamp)) {
                pool.lastRewardTimestamp = block.timestamp;
                // emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accTokenPerShare);
            }

            return pool;
        }

        /// @dev for each reward info
        for (uint256 i = 0; i < rewardInfo.length; ++i) {
            // @dev get multiplier based on current timestamp and rewardInfo's end timestamp
            // multiplier will be a range of either (current timestamp - pool.timestamp)
            // or (reward info's endtimestamp - pool.timestamp) or 0
            uint256 timeElapsed = getTimeElapsed(pool.lastRewardTimestamp, block.timestamp, rewardInfo[i].endTimestamp);
            if (timeElapsed == 0) continue;

            // @dev if currentTimestamp exceed end timestamp, use end timestamp as the last reward timestamp
            // so that for the next iteration, previous endTimestamp will be used as the last reward timestamp
            if (block.timestamp > rewardInfo[i].endTimestamp) {
                pool.lastRewardTimestamp = rewardInfo[i].endTimestamp;
            } else {
                pool.lastRewardTimestamp = block.timestamp;
            }

            uint256 tokenReward = (timeElapsed * rewardInfo[i].rewardPerSec);

            pool.accTokenPerShare += ((tokenReward * ACC_TOKEN_PRECISION) / lpSupply);
        }

        poolRewarder[pid][rewarderId] = pool;

        // emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accTokenPerShare);

        return pool;
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
            addresses[rewarderId] = address(pool.rewarders[rewarderId]);

            symbols[rewarderId] = IBoringERC20(pool.rewarders[rewarderId]).safeSymbol();

            decimals[rewarderId] = IBoringERC20(pool.rewarders[rewarderId]).safeDecimals();
            amounts[rewarderId] = _pendingToken(_pid, rewarderId, userInfo[_pid][_user].amount, userInfo[_pid][_user].rewardDebt);
        }
    }

    function _pendingToken(
        uint256 _pid,
        uint256 _rewarderId,
        uint256 _amount,
        uint256 _rewardDebt
    ) internal view returns (uint256 pending) {
        PoolRewarder memory rewarderpool = poolRewarder[_pid][_rewarderId];
        RewardInfo[] memory rewardInfo = rewardsInfo[_pid][_rewarderId];
        uint256 accTokenPerShare = rewarderpool.accTokenPerShare;
        uint256 lpSupply = poolInfo[_pid].totalLp;

        if (block.timestamp > rewarderpool.lastRewardTimestamp && lpSupply != 0) {
            uint256 cursor = rewarderpool.lastRewardTimestamp;

            for (uint256 i = 0; i < rewardInfo.length; ++i) {
                uint256 timeElapsed = getTimeElapsed(cursor, block.timestamp, rewardInfo[i].endTimestamp);
                if (timeElapsed == 0) continue;
                cursor = rewardInfo[i].endTimestamp;

                uint256 tokenReward = (timeElapsed * rewardInfo[i].rewardPerSec);

                accTokenPerShare += (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
            }
        }

        pending = (((_amount * accTokenPerShare) / ACC_TOKEN_PRECISION) - _rewardDebt);
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
            addresses[rewarderId] = address(pool.rewarders[rewarderId]);

            symbols[rewarderId] = IBoringERC20(pool.rewarders[rewarderId]).safeSymbol();

            decimals[rewarderId] = IBoringERC20(pool.rewarders[rewarderId]).safeDecimals();

            rewardsPerSec[rewarderId] = _rewardPerSecOf(_pid, rewarderId, block.timestamp) ;
        }
    }

    function _rewardPerSecOf(uint256 _pid, uint256 _rewarderId, uint256 _blockTimestamp) internal view returns (uint256) {
        PoolRewarder memory rewaderPool = poolRewarder[_pid][_rewarderId];
        RewardInfo[] memory rewardInfo = rewardsInfo[_pid][_rewarderId];
        uint256 len = rewardInfo.length;
        if (len == 0) {
            return 0;
        }
        if (rewaderPool.startTimestamp > _blockTimestamp) {
            return 0;
        }
        for (uint256 i = 0; i < len; ++i) {
            if (_blockTimestamp <= rewardInfo[i].endTimestamp) return rewardInfo[i].rewardPerSec;
        }
        /// @dev when couldn't find any reward info, it means that timestamp exceed endblock
        /// so return 0
        return 0;
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
