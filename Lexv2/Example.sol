// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILAXToken} from "./interface/ILAXToken.sol";
import {IReferral} from "./interface/IReferral.sol";
import {IProject} from "./interface/IProject.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {_USDT} from "./Const.sol";
import {IStaking} from "./interface/IStaking.sol";

contract Queue is Owned, Pausable, ReentrancyGuard {
    // ============ Events ============
    event Queued(
        address indexed user,
        uint256 queueIndex,
        uint160 amount,
        uint40 timestamp,
        uint8 stakeIndex
    );
    event QueueCancelled(
        address indexed user,
        uint256 queueIndex,
        uint160 refundAmount,
        uint40 timestamp
    );
    event QueueProcessed(
        address indexed user,
        uint256 queueIndex,
        uint160 amount,
        uint40 timestamp
    );
    event FomoRewardClaimed(
        address indexed user,
        uint256 queueIndex,
        uint256 amount,
        uint40 timestamp
    );
    // ============ Constants ============
    uint256 public constant MIN_BIND_AMOUNT = 1 ether;
    uint256 public constant MIN_STAKE_AMOUNT = 2 ether;
    uint256 public constant QUEUE_ENTRY_FEE = 1 ether;
    uint256 public constant CANCEL_FEE = 1 ether;
    uint256 public constant FOMO_WINNERS_COUNT = 41;

    uint256 public constant STAGE_50M = 50000000 ether;
    uint256 public constant STAGE_100M = 100000000 ether;
    uint256 public constant FIRST_MONTH_RATE = 20; // 2% = 20/1000
    uint256 public constant PENDING_MULTIPLIER = 1430; // 143%

    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 5;
    uint256 public constant CIRCUIT_BREAKER_RECOVERY_MULTIPLE = 3;
    uint256 public constant DAILY_DROP_THRESHOLD = 95;
    uint256 public constant NO_LIMIT_DURATION = 2 days;

    uint256 public constant WORKSHOP_UNSTAKE_RATE = 3;

    IERC20 constant USDT = IERC20(_USDT);

    // ============ State Variables ============
    IStaking public STAKING;
    ILAXToken public LAX;
    IReferral public immutable REFERRAL;
    IProject public PROJECT;

    uint256 public maxStakeAmountValue = 200 ether;
    uint256 public maxProcessCount = 5;
    uint256 public maxFomoScanCount = 200;
    uint256 public oneDayStakeDailyLimit = 100000 ether;

    uint40 public launchTime;
    uint256 public constant FIRST_MONTH_DAYS = 30;
    uint256 public constant LIMIT_PERIOD_DAYS = 180;
    uint256 public maxStakesInLimitPeriod = 50;

    bool public shortTermStakeEnabled = false;
    bool public autoProcessEnabled = true;

    uint256 public multiplierUnder50M = 1020; // × 1.02
    uint256 public multiplier50MTo100M = 1010; // × 1.01
    uint256 public multiplierAbove100M = 1005; // × 1.005

    uint256 public constant MORNING_QUOTA_RATE = 60;
    uint256 public constant AFTERNOON_HOUR_UTC = 6;

    mapping(uint256 => uint256) public dailyTotalStaked;
    mapping(uint256 => uint256) public dailyWorkshopUnstaked;
    mapping(uint256 => uint256) public dailyOneDayStaked;
    mapping(uint256 => uint256) public pendingOutAmount;

    mapping(address => uint256) public userStakeCount;

    uint40 public circuitBreakerTime;
    uint40 public circuitBreakerStartTime;
    uint40 public dailyDropNoLimitTime;
    uint112 public historicalHighU;
    uint112 public recoveryRecordU;

    struct QueueInfo {
        address user;
        uint160 amount;
        uint40 queueTime;
        uint8 stakeIndex;
        bool processed;
        bool cancelled;
        uint256 restakeIndex;
    }

    QueueInfo[] public queueList;
    uint256 public queueHead;

    bool public fomoEnabled = true;
    uint256 public fomoPool;
    uint256 public lastDistributeDay;

    uint256[] public fomoEligibleQueues;
    uint256 public lastFomoIdx;

    mapping(uint256 => uint256) public queueFomoReward;

    uint256 public queuedUsdtAmount;

    mapping(address => bool) public isWorkshop;

    mapping(address => bool) public hasPendingOneDayStake;
    mapping(address => mapping(uint256 => bool)) public hasPendingRestake;

    // ============ Modifiers ============
    modifier onlyAuthorized() {
        require(
            msg.sender == owner || msg.sender == marketingAddress(),
            "not authorized"
        );
        _;
    }

    // ============ Constructor ============
    constructor(
        address _staking,
        address _referral,
        address _project
    ) Owned(msg.sender) {
        require(_staking != address(0), "zero staking");
        require(_referral != address(0), "zero referral");
        require(_project != address(0), "zero project");
        STAKING = IStaking(_staking);
        REFERRAL = IReferral(_referral);
        PROJECT = IProject(_project);
        USDT.approve(address(STAKING), type(uint256).max);
    }

    function marketingAddress() public view returns (address) {
        return PROJECT.marketingAddress();
    }

    // ============ Admin Functions ============
    function setStaking(address _staking) external onlyOwner {
        STAKING = IStaking(_staking);
        USDT.approve(address(STAKING), type(uint256).max);
    }

    function setLAX(address _lax) external onlyOwner {
        LAX = ILAXToken(_lax);
    }

    function setProject(address _project) external onlyOwner {
        require(_project != address(0), "zero address");
        PROJECT = IProject(_project);
    }

    function setMaxStakeAmountValue(uint256 _value) external onlyOwner {
        maxStakeAmountValue = _value;
    }

    function setMaxProcessCount(uint256 _value) external onlyOwner {
        maxProcessCount = _value;
    }

    function setMaxFomoScanCount(uint256 _value) external onlyOwner {
        maxFomoScanCount = _value;
    }

    function setOneDayStakeDailyLimit(uint256 _value) external onlyOwner {
        oneDayStakeDailyLimit = _value;
    }

    function setLaunchTime(uint40 _launchTime) external onlyOwner {
        launchTime = _launchTime;
        if (lastDistributeDay == 0) {
            lastDistributeDay = uint256(_launchTime) / 1 days;
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFomoEnabled(bool _enabled) external onlyOwner {
        fomoEnabled = _enabled;
    }

    function setShortTermStakeEnabled(bool _enabled) external onlyOwner {
        shortTermStakeEnabled = _enabled;
    }

    function setAutoProcessEnabled(bool _enabled) external onlyAuthorized {
        autoProcessEnabled = _enabled;
    }

    function setMaxStakesInLimitPeriod(uint256 _value) external onlyOwner {
        maxStakesInLimitPeriod = _value;
    }

    function setMultipliers(
        uint256 _under50M,
        uint256 _50MTo100M,
        uint256 _above100M
    ) external onlyAuthorized {
        multiplierUnder50M = _under50M;
        multiplier50MTo100M = _50MTo100M;
        multiplierAbove100M = _above100M;
    }

    function processQueue(
        uint256 count
    ) external nonReentrant whenNotPaused onlyAuthorized {
        _distributeFomoInternal();
        _processQueueInternal(count);
    }

    // ============ Workshop Management ============
    function setWorkshop(
        address[] calldata _addrs,
        bool _isWorkshop
    ) external onlyAuthorized {
        for (uint256 i = 0; i < _addrs.length; i++) {
            isWorkshop[_addrs[i]] = _isWorkshop;
        }
    }

    // ============ Data Management ============
    function setPendingOutAmount(
        uint256 _day,
        uint256 _amount
    ) external onlyAuthorized {
        pendingOutAmount[_day] = _amount;
    }

    function setUserStakeCount(
        address[] calldata _users,
        uint256[] calldata _counts
    ) external onlyOwner {
        require(_users.length == _counts.length, "length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            userStakeCount[_users[i]] = _counts[i];
        }
    }

    // ============ Core Functions ============

    function bindReferral(address parent) external nonReentrant whenNotPaused {
        require(!REFERRAL.isBindReferral(msg.sender), "already bound");
        require(REFERRAL.isBindReferral(parent), "parent not bound");

        if (fomoEnabled) {
            USDT.transferFrom(msg.sender, address(this), MIN_BIND_AMOUNT);
            fomoPool += MIN_BIND_AMOUNT;
        }

        REFERRAL.bindReferral(parent, msg.sender);
    }

    function stake(
        uint160 _amount,
        uint8 _stakeIndex
    ) external nonReentrant whenNotPaused {
        _stakeInternal(_amount, _stakeIndex, address(0));
    }

    function stakeWithInviter(
        uint160 _amount,
        uint8 _stakeIndex,
        address parent
    ) external nonReentrant whenNotPaused {
        _stakeInternal(_amount, _stakeIndex, parent);
    }

    function _stakeInternal(
        uint160 _amount,
        uint8 _stakeIndex,
        address parent
    ) private {
        require(_amount >= MIN_STAKE_AMOUNT, ">=2U");
        require(_amount <= maxStakeAmountValue, "exceed max");
        require(_stakeIndex < 3, "invalid index");

        if (isLimitPeriod()) {
            require(
                userStakeCount[msg.sender] < maxStakesInLimitPeriod,
                "limit period: max stakes exceeded"
            );
        }

        if (_stakeIndex == 0) {
            require(
                !STAKING.userOneDayStaked(msg.sender),
                "1day already staked"
            );
            require(
                !hasPendingOneDayStake[msg.sender],
                "pending 1day order exists"
            );
            uint160 actualAmount = fomoEnabled
                ? _amount - uint160(QUEUE_ENTRY_FEE)
                : _amount;
            uint256 today = _today();
            require(
                dailyOneDayStaked[today] + actualAmount <=
                    oneDayStakeDailyLimit,
                "1day daily limit exceeded"
            );
            dailyOneDayStaked[today] += actualAmount;
            hasPendingOneDayStake[msg.sender] = true;
        }

        if (
            parent != address(0) &&
            !REFERRAL.isBindReferral(msg.sender) &&
            REFERRAL.isBindReferral(parent)
        ) {
            REFERRAL.bindReferral(parent, msg.sender);
        }

        _checkStakeRules(msg.sender, _stakeIndex);
        _distributeFomoInternal();
        _enterQueue(msg.sender, _amount, _stakeIndex, 0);
        if (autoProcessEnabled) {
            _processQueueInternal(maxProcessCount);
        }
    }

    function restake(
        uint256 _index,
        uint160 _amount,
        uint8 _stakeIndex
    ) external nonReentrant whenNotPaused {
        require(_amount >= MIN_STAKE_AMOUNT, ">=2U");
        require(_amount <= maxStakeAmountValue, "exceed max");
        require(_stakeIndex < 3, "invalid index");
        require(_stakeIndex > 0, "restake cannot be 1day");

        if (isLimitPeriod()) {
            require(
                userStakeCount[msg.sender] < maxStakesInLimitPeriod,
                "limit period: max stakes exceeded"
            );
        }

        _validateRestake(msg.sender, _index, _amount, _stakeIndex);
        hasPendingRestake[msg.sender][_index] = true;

        _checkStakeRules(msg.sender, _stakeIndex);
        _distributeFomoInternal();
        _enterQueue(msg.sender, _amount, _stakeIndex, _index + 1);

        IStaking.Record memory originalRecord = STAKING.getStakeRecord(
            msg.sender,
            _index
        );
        uint256 restakeQueueIdx = queueList.length - 1;
        QueueInfo storage restakeInfo = queueList[restakeQueueIdx];
        uint256 available = remainingStakeAmount();

        if (
            restakeInfo.amount == originalRecord.amount &&
            available >= restakeInfo.amount
        ) {
            STAKING.restakeFor(
                restakeInfo.user,
                restakeInfo.restakeIndex - 1,
                restakeInfo.amount,
                restakeInfo.stakeIndex
            );
            hasPendingRestake[restakeInfo.user][
                restakeInfo.restakeIndex - 1
            ] = false;
            restakeInfo.processed = true;
            queuedUsdtAmount -= restakeInfo.amount;
            _updateDailyStaked(restakeInfo.amount);
            _addPendingOutAmount(restakeInfo.amount);
            _claimFomoReward(restakeQueueIdx, true);

            emit QueueProcessed(
                restakeInfo.user,
                restakeQueueIdx,
                restakeInfo.amount,
                uint40(block.timestamp)
            );
        } else if (autoProcessEnabled) {
            _processQueueInternal(maxProcessCount);
        }
    }

    function _validateRestake(
        address user,
        uint256 _index,
        uint160 _amount,
        uint8 _stakeIndex
    ) private view {
        IStaking.Record memory record = STAKING.getStakeRecord(user, _index);
        require(record.unstakeTime > 0, "not unstaked");
        require(record.restakeTime == 0, "already restaked");
        require(_amount >= record.amount, "amount too small");
        require(_stakeIndex >= record.stakeIndex, "stake index too small");
        require(!hasPendingRestake[user][_index], "pending restake exists");
    }

    function unstake(
        uint256 index
    ) external nonReentrant whenNotPaused returns (uint256 actualAmount) {
        IStaking.Record memory record = STAKING.getStakeRecord(
            msg.sender,
            index
        );
        uint40 stakeTime = record.stakeTime;
        uint160 amount = record.amount;

        (bool allowed, string memory reason) = checkUnstakeLimit(
            msg.sender,
            amount,
            stakeTime
        );
        require(allowed, reason);

        actualAmount = STAKING.unstakeFor(msg.sender, index);

        if (userStakeCount[msg.sender] > 0) {
            userStakeCount[msg.sender] -= 1;
        }

        _recordUnstake(msg.sender, actualAmount);
    }

    function claim(uint256 index) external nonReentrant whenNotPaused {
        STAKING.claimFor(msg.sender, index);
    }

    function cancelQueue(
        uint256 queueIndex
    ) external nonReentrant whenNotPaused {
        require(queueIndex < queueList.length, "invalid index");

        QueueInfo storage info = queueList[queueIndex];
        require(
            info.user == msg.sender || msg.sender == owner,
            "not authorized"
        );
        require(!info.processed && !info.cancelled, "invalid state");

        info.cancelled = true;
        queuedUsdtAmount -= info.amount;

        if (userStakeCount[info.user] > 0) {
            userStakeCount[info.user] -= 1;
        }

        if (info.restakeIndex == 0) {
            if (info.stakeIndex == 0) {
                hasPendingOneDayStake[info.user] = false;
                uint256 queueDay = uint256(info.queueTime) / 1 days;
                if (dailyOneDayStaked[queueDay] >= info.amount) {
                    dailyOneDayStaked[queueDay] -= info.amount;
                } else {
                    dailyOneDayStaked[queueDay] = 0;
                }
            }
        } else {
            hasPendingRestake[info.user][info.restakeIndex - 1] = false;
        }

        uint256 refund;
        if (fomoEnabled) {
            refund = info.amount - CANCEL_FEE;
            fomoPool += CANCEL_FEE;
            _claimFomoReward(queueIndex, false);
        } else {
            refund = info.amount;
        }

        if (refund > 0) {
            USDT.transfer(info.user, refund);
        }
        emit QueueCancelled(
            info.user,
            queueIndex,
            uint160(refund),
            uint40(block.timestamp)
        );
    }

    function _processQueueInternal(uint256 count) private {
        uint256 available = remainingStakeAmount();
        uint256 processed = 0;

        while (
            processed < count && queueHead < queueList.length && available > 0
        ) {
            QueueInfo storage info = queueList[queueHead];

            if (info.processed || info.cancelled) {
                queueHead++;
                continue;
            }

            if (info.amount > available) {
                break;
            }

            if (info.restakeIndex == 0) {
                STAKING.stakeFor(info.user, info.amount, info.stakeIndex);
                if (info.stakeIndex == 0) {
                    hasPendingOneDayStake[info.user] = false;
                }
            } else {
                STAKING.restakeFor(
                    info.user,
                    info.restakeIndex - 1,
                    info.amount,
                    info.stakeIndex
                );
                hasPendingRestake[info.user][info.restakeIndex - 1] = false;
            }

            info.processed = true;
            queuedUsdtAmount -= info.amount;
            _updateDailyStaked(info.amount);
            _addPendingOutAmount(info.amount);
            _claimFomoReward(queueHead, true);
            available -= info.amount;

            emit QueueProcessed(
                info.user,
                queueHead,
                info.amount,
                uint40(block.timestamp)
            );

            processed++;
            queueHead++;
        }
    }

    // ============ FOMO Functions ============
    function _findFomoWinnersView()
        private
        view
        returns (uint256[] memory indices)
    {
        uint256 eligibleLen = fomoEligibleQueues.length;
        if (eligibleLen <= lastFomoIdx) {
            return new uint256[](0);
        }

        uint256[] memory tempIndices = new uint256[](FOMO_WINNERS_COUNT);
        address[] memory seenUsers = new address[](FOMO_WINNERS_COUNT);
        uint256 added = 0;
        uint256 scanned = 0;

        for (
            uint256 i = eligibleLen - 1;
            i >= lastFomoIdx &&
            added < FOMO_WINNERS_COUNT &&
            scanned < maxFomoScanCount;

        ) {
            scanned++;
            uint256 queueIndex = fomoEligibleQueues[i];
            QueueInfo storage info = queueList[queueIndex];

            if (!info.cancelled && !info.processed) {
                bool duplicate = false;
                for (uint256 j = 0; j < added; j++) {
                    if (seenUsers[j] == info.user) {
                        duplicate = true;
                        break;
                    }
                }

                if (!duplicate) {
                    tempIndices[added] = queueIndex;
                    seenUsers[added] = info.user;
                    added++;
                }
            }

            if (i == 0) break;
            i--;
        }

        indices = new uint256[](added);
        for (uint256 i = 0; i < added; i++) {
            indices[i] = tempIndices[i];
        }
    }

    function _claimFomoReward(uint256 queueIndex, bool toUser) private {
        uint256 reward = queueFomoReward[queueIndex];
        if (reward > 0) {
            queueFomoReward[queueIndex] = 0;
            address to = toUser
                ? queueList[queueIndex].user
                : marketingAddress();
            USDT.transfer(to, reward);
            emit FomoRewardClaimed(
                to,
                queueIndex,
                reward,
                uint40(block.timestamp)
            );
        }
    }

    function getFomoWinners()
        external
        view
        returns (uint256[] memory indices, QueueInfo[] memory infos)
    {
        indices = _findFomoWinnersView();
        infos = new QueueInfo[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            infos[i] = queueList[indices[i]];
        }
    }

    function _distributeFomoInternal() private returns (bool success) {
        if (!fomoEnabled) return false;

        uint256 today = _today();
        if (today <= lastDistributeDay || fomoPool == 0) {
            return false;
        }

        uint256 eligibleLen = fomoEligibleQueues.length;
        if (eligibleLen <= lastFomoIdx) {
            return false;
        }

        uint256[] memory winnerQueueIndices = _findFomoWinnersView();
        if (winnerQueueIndices.length == 0) {
            return false;
        }

        uint256 usdtBalance = USDT.balanceOf(address(this));
        uint256 availableAmount = usdtBalance > queuedUsdtAmount
            ? usdtBalance - queuedUsdtAmount
            : 0;
        uint256 distributeAmount = availableAmount < fomoPool
            ? availableAmount
            : fomoPool;

        if (distributeAmount == 0) {
            return false;
        }

        uint256 winnersShare = (distributeAmount * 10) / 100;
        uint256 rewardPerWinner = winnersShare / winnerQueueIndices.length;
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < winnerQueueIndices.length; i++) {
            uint256 queueIdx = winnerQueueIndices[i];
            queueFomoReward[queueIdx] = rewardPerWinner;
            totalDistributed += rewardPerWinner;
        }

        uint256 marketingShare = distributeAmount - totalDistributed;
        if (marketingShare > 0) {
            USDT.transfer(marketingAddress(), marketingShare);
        }

        fomoPool = 0;
        lastDistributeDay = today;
        lastFomoIdx = eligibleLen;
        return true;
    }

    // ============ Circuit Breaker ============

    function shouldUpdateCircuitBreaker()
        external
        view
        returns (
            bool needUpdate,
            bool willTriggerHard,
            bool willRecoverHard,
            bool willTriggerDailyDrop
        )
    {
        uint112 currentReserveU = LAX.getCurrentReserveU();
        uint112 yesterdayReserveU = LAX.getYesterdayCloseReserveU();

        bool needUpdateHigh = currentReserveU > historicalHighU;

        // 检查是否会触发日跌幅不限购
        if (
            yesterdayReserveU > 0 &&
            currentReserveU * 100 <= yesterdayReserveU * DAILY_DROP_THRESHOLD
        ) {
            uint40 todayStart = uint40((block.timestamp / 1 days) * 1 days);
            if (dailyDropNoLimitTime != todayStart) {
                willTriggerDailyDrop = true;
            }
        }

        if (circuitBreakerTime == 0 && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * CIRCUIT_BREAKER_THRESHOLD
            ) {
                willTriggerHard = true;
            }
        }

        if (circuitBreakerTime > 0) {
            if (recoveryRecordU == 0) {
                if (currentReserveU >= historicalHighU) {
                    needUpdate = true;
                }
            } else {
                if (
                    currentReserveU >=
                    recoveryRecordU * CIRCUIT_BREAKER_RECOVERY_MULTIPLE
                ) {
                    willRecoverHard = true;
                }
            }
        }

        needUpdate =
            needUpdateHigh ||
            willTriggerHard ||
            willRecoverHard ||
            willTriggerDailyDrop;
    }

    function updateCircuitBreaker() external {
        uint112 currentReserveU = LAX.getCurrentReserveU();
        uint112 yesterdayReserveU = LAX.getYesterdayCloseReserveU();

        if (currentReserveU > historicalHighU) {
            historicalHighU = currentReserveU;
        }

        if (
            yesterdayReserveU > 0 &&
            currentReserveU * 100 <= yesterdayReserveU * DAILY_DROP_THRESHOLD
        ) {
            uint40 todayStart = uint40((block.timestamp / 1 days) * 1 days);
            if (dailyDropNoLimitTime != todayStart) {
                dailyDropNoLimitTime = todayStart;
            }
        }

        if (circuitBreakerTime == 0 && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * CIRCUIT_BREAKER_THRESHOLD
            ) {
                circuitBreakerTime = uint40(block.timestamp);
                circuitBreakerStartTime = uint40(block.timestamp);
                recoveryRecordU = 0;
            }
        }

        if (circuitBreakerTime > 0) {
            if (recoveryRecordU == 0) {
                if (currentReserveU >= historicalHighU) {
                    recoveryRecordU = currentReserveU;
                }
            } else {
                if (
                    currentReserveU >=
                    recoveryRecordU * CIRCUIT_BREAKER_RECOVERY_MULTIPLE
                ) {
                    circuitBreakerTime = 0;
                    recoveryRecordU = 0;
                }
            }
        }
    }

    function isOrderAffectedByCircuitBreaker(
        uint40 stakeTime
    ) public view returns (bool) {
        return isCircuitBreakerActive() && stakeTime < circuitBreakerTime;
    }

    function isCircuitBreakerActive() public view returns (bool) {
        return circuitBreakerTime > 0;
    }

    // ============ Limit Calculations ============

    function getDailyStakeLimit() public view returns (uint256) {
        if (isDailyDropNoLimitPeriod()) {
            return type(uint256).max;
        }

        uint112 reserveU = LAX.getYesterdayCloseReserveU();

        if (isFirstMonth() || isCircuitBreakerFirstMonth()) {
            return (uint256(reserveU) * FIRST_MONTH_RATE) / 1000;
        }

        uint256 pending = (pendingOutAmount[_today()] * PENDING_MULTIPLIER) /
            1000;
        uint256 multiplier;
        if (reserveU < STAGE_50M) {
            multiplier = multiplierUnder50M;
        } else if (reserveU < STAGE_100M) {
            multiplier = multiplier50MTo100M;
        } else {
            multiplier = multiplierAbove100M;
        }
        return (pending * multiplier) / 1000;
    }

    function isDailyDropNoLimitPeriod() public view returns (bool) {
        return
            dailyDropNoLimitTime > 0 &&
            block.timestamp < dailyDropNoLimitTime + NO_LIMIT_DURATION;
    }

    function getWorkshopUnstakeLimit() public view returns (uint256) {
        uint112 reserveU = LAX.getYesterdayCloseReserveU();
        return (uint256(reserveU) * WORKSHOP_UNSTAKE_RATE) / 1000;
    }

    function remainingWorkshopUnstakeAmount() public view returns (uint256) {
        uint256 limit = getWorkshopUnstakeLimit();
        uint256 used = dailyWorkshopUnstaked[_today()];
        return used >= limit ? 0 : limit - used;
    }

    function checkUnstakeLimit(
        address user,
        uint256 amount,
        uint40 stakeTime
    ) public view returns (bool allowed, string memory reason) {
        if (isWorkshop[user] && amount > remainingWorkshopUnstakeAmount()) {
            return (false, "workshop daily limit: 0.3%");
        }

        if (isOrderAffectedByCircuitBreaker(stakeTime)) {
            return (false, "circuit breaker: old order cannot unstake");
        }

        return (true, "");
    }

    function _recordUnstake(address user, uint256 amount) private {
        if (isWorkshop[user]) {
            uint256 today = _today();
            dailyWorkshopUnstaked[today] += amount;
        }
    }

    // ============ View Functions ============
    function isFirstMonth() public view returns (bool) {
        return
            launchTime > 0 &&
            block.timestamp < launchTime + FIRST_MONTH_DAYS * 1 days;
    }

    function isCircuitBreakerFirstMonth() public view returns (bool) {
        return
            circuitBreakerStartTime > 0 &&
            block.timestamp <
                circuitBreakerStartTime + FIRST_MONTH_DAYS * 1 days;
    }

    function isLimitPeriod() public view returns (bool) {
        return
            launchTime > 0 &&
            block.timestamp < launchTime + LIMIT_PERIOD_DAYS * 1 days;
    }

    function getQueueLength() external view returns (uint256) {
        return queueList.length > queueHead ? queueList.length - queueHead : 0;
    }

    function remainingOneDayStakeAmount() public view returns (uint256) {
        uint256 used = dailyOneDayStaked[_today()];
        return used >= oneDayStakeDailyLimit ? 0 : oneDayStakeDailyLimit - used;
    }

    function getQueueInfo(
        uint256 index
    ) external view returns (QueueInfo memory) {
        return queueList[index];
    }

    function getFomoEligibleCount() external view returns (uint256) {
        return fomoEligibleQueues.length;
    }

    // ============ Internal Functions ============

    function _enterQueue(
        address user,
        uint160 amount,
        uint8 stakeIndex,
        uint256 restakeIndex
    ) private {
        USDT.transferFrom(user, address(this), amount);

        uint160 actualAmount;
        if (fomoEnabled) {
            fomoPool += QUEUE_ENTRY_FEE;
            actualAmount = amount - uint160(QUEUE_ENTRY_FEE);
        } else {
            actualAmount = amount;
        }

        queueList.push(
            QueueInfo({
                user: user,
                amount: actualAmount,
                queueTime: uint40(block.timestamp),
                stakeIndex: stakeIndex,
                processed: false,
                cancelled: false,
                restakeIndex: restakeIndex
            })
        );

        queuedUsdtAmount += actualAmount;
        uint256 queueIndex = queueList.length - 1;

        userStakeCount[user] += 1;

        if (fomoEnabled && amount >= maxStakeAmountValue && stakeIndex == 2) {
            fomoEligibleQueues.push(queueIndex);
        }

        emit Queued(
            user,
            queueIndex,
            actualAmount,
            uint40(block.timestamp),
            stakeIndex
        );
    }

    function _checkStakeRules(address user, uint8 stakeIndex) private view {
        require(REFERRAL.isBindReferral(user), "!!bind");

        if (stakeIndex < 2) {
            require(shortTermStakeEnabled, "short term stake not enabled");
        }
    }

    function _today() private view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _updateDailyStaked(uint256 amount) private {
        dailyTotalStaked[_today()] += amount;
    }

    function _addPendingOutAmount(uint256 amount) private {
        uint256 futureDay = _today() + 30;
        pendingOutAmount[futureDay] += amount;
    }

    function remainingStakeAmount() public view returns (uint256) {
        uint256 today = _today();
        uint256 dailyLimit = getDailyStakeLimit();

        if (dailyLimit == type(uint256).max) {
            return dailyLimit;
        }

        uint256 hour = (block.timestamp % 1 days) / 1 hours;
        uint256 usedToday = dailyTotalStaked[today];

        uint256 availableQuota;
        if (hour < AFTERNOON_HOUR_UTC) {
            availableQuota = (dailyLimit * MORNING_QUOTA_RATE) / 100;
        } else {
            availableQuota = dailyLimit; // 100%
        }

        return usedToday >= availableQuota ? 0 : availableQuota - usedToday;
    }

    // ============ Emergency Functions ============

    function withdrawableUsdtAmount() public view returns (uint256) {
        uint256 balance = USDT.balanceOf(address(this));
        return balance > queuedUsdtAmount ? balance - queuedUsdtAmount : 0;
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "to zero addr");
        if (token == _USDT) {
            require(amount <= withdrawableUsdtAmount(), "exceeds withdrawable");
        }
        IERC20(token).transfer(to, amount);
    }
}