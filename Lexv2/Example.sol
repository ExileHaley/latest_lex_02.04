// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

abstract contract Pausable is Context {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

abstract contract Owned {
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    address public owner;

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");

        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}

interface IStaking {
    // ============ Structs ============
    struct Record {
        uint40 stakeTime;
        uint160 amount;
        uint8 stakeIndex;
        uint40 unstakeTime;
        uint160 reward;
        uint40 restakeTime;
    }

    struct Config {
        uint256 rate;
        uint40 day;
        uint40 ttl;
    }

     // ============ Events ============
    event Staked(
        address indexed user,
        uint160 amount,
        uint40 timestamp,
        uint256 index,
        uint40 stakeTime
    );

    event RewardPaid(
        address indexed user,
        uint160 reward,
        uint40 timestamp,
        uint256 index
    );

    event Unstaked(
        address indexed user,
        uint160 amount,
        uint40 timestamp,
        uint256 index,
        uint160 reward,
        uint40 ttl
    );

    event Restaked(address indexed user, uint40 timestamp, uint256 index);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    // ============ View Functions ============
    function userOneDayStaked(address user) external view returns (bool);
    function getStakeRecord(address user, uint256 index) external view returns (Record memory);

    // ============ Core Functions (Called by Queue) ============
    function stakeFor(address user, uint160 amount, uint8 stakeIndex) external;
    function unstakeFor(address user, uint256 index) external returns (uint256 actualAmount);
    function restakeFor(address user, uint256 _index, uint160 _amount, uint8 _stakeIndex) external;
    function claimFor(address user, uint256 _index) external;
}


// =======================
// LAX 代币接口
// =======================
interface ILAXToken is IERC20 {
    // 获取昨日收盘时 USDT 储备量（用于计算每日额度）
    function getYesterdayCloseReserveU() external view returns (uint112);
    // 获取当前池子 USDT 储备量（用于熔断判断）
    function getCurrentReserveU() external view returns (uint112);
    // 获取交易对地址
    function uniswapV2Pair() external view returns (address);
    // 代币回收函数（销毁或回收）
    function recycle(uint256 amount) external;
}


// =======================
// 推荐系统接口
// =======================
interface IReferral{

    // 绑定推荐关系事件
    event BindReferral(address indexed user,address parent);
    // 获取用户推荐人
    function getReferral(address _address)external view returns(address);
    // 判断用户是否已绑定推荐关系
    function isBindReferral(address _address) external view returns(bool);
    // 获取推荐人数
    function getReferralCount(address _address) external view returns(uint256);
    // 绑定推荐关系
    function bindReferral(address _referral,address _user) external;
    // 获取推荐列表
    function getReferrals(address _address,uint256 _num) external view returns(address[] memory);
    // 获取根地址
    function getRootAddress()external view returns(address);
    // 批量导入推荐关系
    function batchImportReferrals(address[] calldata users,address[] calldata referrals) external;
}


// =======================
// 项目地址接口
// =======================
interface IProject {
    // 分红钱包
    function dividendWallet() external view returns (address);
    // 市场钱包
    function marketingAddress() external view returns (address);
    // 生态钱包
    function ecosystemAddress() external view returns (address);
}

// =======================
// 常量地址定义
// =======================
// BSC USDT 地址
address constant _USDT = 0x55d398326f99059fF775485246999027B3197955;
// Pancake Router 地址
address constant _ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;


contract Queue is Owned, Pausable, ReentrancyGuard {
    // ============ Events ============
    // ================= 事件定义 =================

    // 用户进入排队
    event Queued(
        address indexed user,   // 用户地址
        uint256 queueIndex,     // 队列索引
        uint160 amount,         // 金额
        uint40 timestamp,       // 时间
        uint8 stakeIndex        // 质押类型
    );

    // 用户取消排队
    event QueueCancelled(
        address indexed user,
        uint256 queueIndex,
        uint160 refundAmount,
        uint40 timestamp
    );

    // 排队处理成功
    event QueueProcessed(
        address indexed user,
        uint256 queueIndex,
        uint160 amount,
        uint40 timestamp
    );

    // FOMO奖励领取
    event FomoRewardClaimed(
        address indexed user,
        uint256 queueIndex,
        uint256 amount,
        uint40 timestamp
    );



    // ================= 常量参数 =================

    uint256 public constant MIN_BIND_AMOUNT = 1 ether;     // 绑定推荐最低金额
    uint256 public constant MIN_STAKE_AMOUNT = 2 ether;    // 最小质押金额
    uint256 public constant QUEUE_ENTRY_FEE = 1 ether;     // 入队手续费
    uint256 public constant CANCEL_FEE = 1 ether;          // 取消手续费
    uint256 public constant FOMO_WINNERS_COUNT = 31;       // 每日FOMO赢家数量

    // 额度阶段阈值
    uint256 public constant STAGE1_THRESHOLD = 10000000 ether;
    uint256 public constant STAGE2_THRESHOLD = 30000000 ether;
    uint256 public constant STAGE3_THRESHOLD = 100000000 ether;

    // 硬熔断参数
    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 5;     // 跌幅5%
    uint256 public constant CIRCUIT_BREAKER_RECOVERY_MULTIPLE = 3; // 恢复倍数

    // 软熔断参数
    uint256 public constant SOFT_CIRCUIT_BREAKER_THRESHOLD = 10; // 10%
    uint256 public constant WORKSHOP_UNSTAKE_RATE = 3;           // 工作室提现限制0.3%

    // USDT接口
    IERC20 constant USDT = IERC20(_USDT);



    // ================= 状态变量 =================

    IStaking public STAKING;      // 质押合约
    ILAXToken public LAX;         // LAX代币
    IReferral public immutable REFERRAL; // 推荐系统
    IProject public PROJECT;      // 项目地址

    // 最大质押金额
    uint256 public maxStakeAmountValue = 200 ether;

    // 单次最大处理队列数量
    uint256 public maxProcessCount = 5;

    // FOMO扫描最大次数
    uint256 public maxFomoScanCount = 200;

    // 一天质押限额
    uint256 public oneDayStakeDailyLimit = 100000 ether;



    // ================= 启动时间相关 =================

    uint40 public launchTime;                 // 启动时间
    uint256 public constant EARLY_DAYS = 3;   // 早期3天
    uint256 public constant FIRST_MONTH_DAYS = 30; // 首月30天
    uint8 public constant EARLY_MAX_ORDERS_PER_DAY = 1; // 早期每天最多1单



    // ================= 时间分段额度 =================

    uint256 public constant MORNING_QUOTA_RATE = 60; // 上午可用60%
    uint256 public constant AFTERNOON_HOUR_UTC = 6;  // UTC 6点之后开放全部



    // ================= 每日统计 =================

    mapping(uint256 => uint256) public dailyTotalStaked;     // 每日总质押
    mapping(uint256 => uint256) public dailyTotalUnstaked;   // 每日总提现
    mapping(address => mapping(uint256 => uint256)) public userDailyStakeCount; // 用户每日质押次数
    mapping(uint256 => uint256) public dailyWorkshopUnstaked; // 工作室提现统计
    mapping(uint256 => uint256) public dailyOneDayStaked;     // 一日质押统计



    // 是否新用户
    mapping(address => bool) public isNewUser;



    // ================= 熔断记录 =================

    uint40 public circuitBreakerTime;   // 熔断触发时间
    uint112 public historicalHighU;     // 历史最高储备
    uint112 public recoveryRecordU;     // 恢复记录储备
    bool public softCircuitBreakerTriggered; // 软熔断是否触发



    // ================= 队列结构 =================

    struct QueueInfo {
        address user;       // 用户
        uint160 amount;     // 金额
        uint40 queueTime;   // 入队时间
        uint8 stakeIndex;   // 质押类型
        bool processed;     // 是否处理
        bool cancelled;     // 是否取消
        uint256 restakeIndex; // 复投索引
    }

    // 队列数组
    QueueInfo[] public queueList;

    // 当前处理头指针
    uint256 public queueHead;



    // ================= FOMO =================

    bool public fomoEnabled = true;   // 是否开启FOMO
    uint256 public fomoPool;          // FOMO资金池
    uint256 public lastDistributeDay; // 上次分发日期

    // 参与FOMO的队列索引列表
    uint256[] public fomoEligibleQueues;

    uint256 public lastFomoIdx; // 上次扫描位置

    // 队列FOMO奖励
    mapping(uint256 => uint256) public queueFomoReward;



    // 当前排队USDT总量
    uint256 public queuedUsdtAmount;



    // 风控上传地址
    address public riskUploader;

    // 工作室地址
    mapping(address => bool) public isWorkshop;



    // 一天质押排队状态
    mapping(address => bool) public hasPendingOneDayStake;

    // 复投排队状态
    mapping(address => mapping(uint256 => bool)) public hasPendingRestake;



    // ================= 构造函数 =================

    constructor(
        address _staking,     // 质押合约地址
        address _referral,    // 推荐系统地址
        address _project      // 项目配置地址
    ) Owned(msg.sender) {

        // 校验地址
        require(_staking != address(0), "zero staking");
        require(_referral != address(0), "zero referral");
        require(_project != address(0), "zero project");

        // 初始化接口
        STAKING = IStaking(_staking);
        REFERRAL = IReferral(_referral);
        PROJECT = IProject(_project);

        // 授权USDT给质押合约
        USDT.approve(address(STAKING), type(uint256).max);
    }



    // ================= 获取营销地址 =================

    function marketingAddress() public view returns (address) {
        return PROJECT.marketingAddress();
    }



    // ================= 管理员函数 =================

    // 设置质押合约
    function setStaking(address _staking) external onlyOwner {
        STAKING = IStaking(_staking);

        // 重新授权USDT
        USDT.approve(address(STAKING), type(uint256).max);
    }

    // 设置LAX代币地址
    function setLAX(address _lax) external onlyOwner {
        LAX = ILAXToken(_lax);
    }

    // 设置项目配置
    function setProject(address _project) external onlyOwner {
        require(_project != address(0), "zero address");
        PROJECT = IProject(_project);
    }

    // 设置最大质押金额
    function setMaxStakeAmountValue(uint256 _value) external onlyOwner {
        maxStakeAmountValue = _value;
    }

    // 设置单次处理队列数量
    function setMaxProcessCount(uint256 _value) external onlyOwner {
        maxProcessCount = _value;
    }

    // 设置FOMO扫描数量
    function setMaxFomoScanCount(uint256 _value) external onlyOwner {
        maxFomoScanCount = _value;
    }

    // 设置一日质押限额
    function setOneDayStakeDailyLimit(uint256 _value) external onlyOwner {
        oneDayStakeDailyLimit = _value;
    }

    // 设置启动时间
    function setLaunchTime(uint40 _launchTime) external onlyOwner {

        launchTime = _launchTime;

        // 初始化分发日期
        if (lastDistributeDay == 0) {
            lastDistributeDay = uint256(_launchTime) / 1 days;
        }
    }

    // 设置风控上传地址
    function setRiskUploader(address _uploader) external onlyOwner {
        riskUploader = _uploader;
    }

    // 暂停系统
    function pause() external onlyOwner {
        _pause();
    }

    // 恢复系统
    function unpause() external onlyOwner {
        _unpause();
    }

    // 开关FOMO
    function setFomoEnabled(bool _enabled) external onlyOwner {
        fomoEnabled = _enabled;
    }

    // ============ Workshop Management ============
    function setWorkshop(address[] calldata _addrs, bool _isWorkshop) external {
        require(
            msg.sender == riskUploader || msg.sender == owner,
            "not authorized"
        );
        for (uint256 i = 0; i < _addrs.length; i++) {
            isWorkshop[_addrs[i]] = _isWorkshop;
        }
    }

    // ============ Core Functions ============
    function bindReferral(address parent) external nonReentrant whenNotPaused {
        require(!REFERRAL.isBindReferral(msg.sender), "already bound");
        require(REFERRAL.isBindReferral(parent), "parent not bound");

        // === 补充说明 ===
        // 当 fomoEnabled 时，绑定推荐关系需要支付 MIN_BIND_AMOUNT
        // 该金额直接进入 fomoPool，而不是返还给 parent
        //
        // 设计目的：
        // 1. 防止批量小号无成本绑定
        // 2. 将“社交行为”转化为系统收入
        // 3. 避免推荐体系被滥用为空转关系网
        if (fomoEnabled) {
            USDT.transferFrom(msg.sender, address(this), MIN_BIND_AMOUNT);
            fomoPool += MIN_BIND_AMOUNT;
        }

        // === 补充说明 ===
        // 推荐关系一旦绑定不可修改
        // 推荐系统的完整合法性校验由 REFERRAL 合约负责
        REFERRAL.bindReferral(parent, msg.sender);

        // === 补充说明 ===
        // 标记为新用户：
        // - 用于首日 / 首月 / 早期阶段的风控限制
        // - 该标记只在绑定时设置，不会自动清除
        isNewUser[msg.sender] = true;
    }


    function stake(
        uint160 _amount,
        uint8 _stakeIndex
    ) external nonReentrant whenNotPaused {

        // === 补充说明 ===
        // 不在此函数中做任何风控或状态修改
        // 所有 stake 相关逻辑统一下沉到 _stakeInternal
        // 防止未来新增入口时遗漏关键校验
        _stakeInternal(_amount, _stakeIndex, address(0));
    }


    function stakeWithInviter(
        uint160 _amount,
        uint8 _stakeIndex,
        address parent
    ) external nonReentrant whenNotPaused {

        // === 补充说明 ===
        // 该入口仅提供“尝试绑定推荐”的能力
        // 是否真的绑定，仍由 _stakeInternal 内部条件决定
        _stakeInternal(_amount, _stakeIndex, parent);
    }


    function _stakeInternal(
        uint160 _amount,
        uint8 _stakeIndex,
        address parent
    ) private {
        // ================= 基础参数校验 =================

        // 防止极小金额刷单，占用队列与 gas
        require(_amount >= MIN_STAKE_AMOUNT, ">=2U");

        // 单笔最大限制，防止鲸鱼一次性吃光当日额度
        require(_amount <= maxStakeAmountValue, "exceed max");

        // stakeIndex 固定为 0/1/2（1day / 7day / 30day）
        // 不用 enum 是为了节省 gas 与 ABI 复杂度
        require(_stakeIndex < 3, "invalid index");

        // ================= 1day 产品的特殊风控 =================
        // 1day 到期快、流动性风险最高，所以限制最多
        if (_stakeIndex == 0) {

            // 用户不能已经有一个正在运行的 1day 订单
            // 防止滚动 1day，形成类活期提款
            require(
                !STAKING.userOneDayStaked(msg.sender),
                "1day already staked"
            );

            // 用户不能已经有一个“排队中的”1day
            // 否则可以在额度释放时一次性成交多单
            require(
                !hasPendingOneDayStake[msg.sender],
                "pending 1day order exists"
            );

            // 实际进入 staking 的金额
            // 如果开启 FOMO，需要扣除 QUEUE_ENTRY_FEE
            // 这样 staking 合约内部不感知手续费，APR 计算更干净
            uint160 actualAmount = fomoEnabled
                ? _amount - uint160(QUEUE_ENTRY_FEE)
                : _amount;

            uint256 today = _today();

            // 1day 每日总量限制
            // 防止短期产品在同一天集中到期，导致系统挤兑
            require(
                dailyOneDayStaked[today] + actualAmount <=
                    oneDayStakeDailyLimit,
                "1day daily limit exceeded"
            );

            // 记录当天已使用的 1day 额度
            dailyOneDayStaked[today] += actualAmount;

            // 标记用户存在一个排队中的 1day
            // 只有在 queue 被 process 或 cancel 时才会解除
            hasPendingOneDayStake[msg.sender] = true;
        }

        // ================= 推荐绑定逻辑 =================
        // 仅在以下条件同时满足时自动绑定：
        // 1. parent 不为 0
        // 2. 当前用户尚未绑定推荐
        // 3. parent 本身是合法推荐节点
        if (
            parent != address(0) &&
            !REFERRAL.isBindReferral(msg.sender) &&
            REFERRAL.isBindReferral(parent)
        ) {
            // 绑定推荐关系
            REFERRAL.bindReferral(parent, msg.sender);

            // 标记为新用户
            // 后续首日 / 首月限制会依赖这个标记
            isNewUser[msg.sender] = true;
        }

        // ================= 核心风控规则 =================
        // 包含：
        // - 是否已绑定推荐
        // - 首日是否允许新用户
        // - 首月是否只能买 30day
        // - 早期是否每天只能 1 单
        _checkStakeRules(msg.sender, _stakeIndex);

        // ================= 用户行为计数 =================
        // 只记录“次数”，不记录金额
        // 用于早期阶段防刷，而不是限仓
        userDailyStakeCount[msg.sender][_today()] += 1;

        // ================= FOMO 分发触发点 =================
        // 不是定时任务，而是用户行为触发
        // 任意一次 stake / restake / process 都可能触发分发
        _distributeFomoInternal();

        // ================= 正式进入队列 =================
        // ⚠️ 注意：这里并不会立刻 stake
        // 只是生成一个排队订单，真正 stake 在 processQueue 中完成
        _enterQueue(msg.sender, _amount, _stakeIndex, 0);

        // ================= 尝试处理队列 =================
        // 每次用户操作顺便推进队列，避免依赖机器人
        _processQueueInternal(maxProcessCount);
    }

    function restake(
        uint256 _index,
        uint160 _amount,
        uint8 _stakeIndex
    ) external nonReentrant whenNotPaused {

        // === 补充说明 ===
        // restake 继承原 stake 的风险属性
        // 因此不允许 restake 为 1day（最短周期）
        // 防止用户通过 unstake + restake 模拟活期
        require(_stakeIndex > 0, "restake cannot be 1day");

        _validateRestake(msg.sender, _index, _amount, _stakeIndex);

        // === 补充说明 ===
        // 标记该 staking record 存在一个排队中的复投请求
        // 在 queue 被处理或取消前，禁止再次 restake
        hasPendingRestake[msg.sender][_index] = true;

        _checkStakeRules(msg.sender, _stakeIndex);

        // === 补充说明 ===
        // 复投行为同样计入“每日操作次数”
        // 防止用户通过复投绕过早期阶段限制
        userDailyStakeCount[msg.sender][_today()] += 1;

        _distributeFomoInternal();

        // === 补充说明 ===
        // restakeIndex 使用 index + 1
        // 以便与普通 stake（restakeIndex = 0）明确区分
        _enterQueue(msg.sender, _amount, _stakeIndex, _index + 1);

        _processQueueInternal(maxProcessCount);
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

        // === 补充说明 ===
        // unstake 并非无条件允许：
        // - 可能受到熔断影响
        // - 可能受到每日总量限制
        // - workshop 地址还有额外限制
        (bool allowed, string memory reason) = this.checkUnstakeLimit(
            msg.sender,
            record.amount,
            record.stakeTime
        );
        require(allowed, reason);

        // === 补充说明 ===
        // 实际资金转移发生在 STAKING 合约
        // 当前合约仅负责风控与统计
        actualAmount = STAKING.unstakeFor(msg.sender, index);

        _recordUnstake(msg.sender, actualAmount);
    }


    function claim(uint256 index) external nonReentrant whenNotPaused {
        STAKING.claimFor(msg.sender, index);
    }

    function cancelQueue(
        uint256 queueIndex
    ) external nonReentrant whenNotPaused {

        // ================= 基础校验 =================
        require(queueIndex < queueList.length, "invalid index");

        QueueInfo storage info = queueList[queueIndex];

        // 只有：
        // - 订单所属用户
        // - 或 owner
        // 才能取消
        require(
            info.user == msg.sender || msg.sender == owner,
            "not authorized"
        );

        // 已处理或已取消的订单不能再操作
        require(!info.processed && !info.cancelled, "invalid state");

        // ================= 标记为取消 =================
        info.cancelled = true;

        // 从排队资金中移除
        queuedUsdtAmount -= info.amount;

        // ================= 解除 pending 状态 =================
        if (info.restakeIndex == 0) {

            // 普通 stake
            if (info.stakeIndex == 0) {

                // 解除 1day pending
                hasPendingOneDayStake[info.user] = false;

                // 回滚当日 1day 已用额度
                uint256 queueDay = uint256(info.queueTime) / 1 days;
                if (dailyOneDayStaked[queueDay] >= info.amount) {
                    dailyOneDayStaked[queueDay] -= info.amount;
                } else {
                    dailyOneDayStaked[queueDay] = 0;
                }
            }

        } else {
            // 复投 pending 回滚
            hasPendingRestake[info.user][info.restakeIndex - 1] = false;
        }

        uint256 refund;

        // ================= 退款逻辑 =================
        if (fomoEnabled) {

            // 开启 FOMO：
            // - 用户承担 CANCEL_FEE
            // - 手续费进入 fomoPool
            refund = info.amount - CANCEL_FEE;
            fomoPool += CANCEL_FEE;

            // 如果该订单有 FOMO 奖励，取消后奖励归 marketing
            _claimFomoReward(queueIndex, false);

        } else {
            // 未开启 FOMO，全额退款
            refund = info.amount;
        }

        // ================= 执行退款 =================
        if (refund > 0) {
            USDT.transfer(info.user, refund);
        }

        // ================= 触发取消事件 =================
        emit QueueCancelled(
            info.user,
            queueIndex,
            uint160(refund),
            uint40(block.timestamp)
        );
    }


   function processQueue(uint256 count) external nonReentrant whenNotPaused {

        // === 补充说明 ===
        // 允许任意用户触发 queue 处理：
        // - 避免系统依赖机器人或 owner
        // - 防止队列因无人维护而停滞
        //
        // processQueue 不会影响调用者自身状态
        // 只要 remainingStakeAmount > 0 就可能推进系统
        _distributeFomoInternal();
        _processQueueInternal(count);
    }


    function _processQueueInternal(uint256 count) private {

        // ================= 计算当前还能处理多少额度 =================
        // 这里会综合：
        // - 每日质押总额度
        // - 上午 / 下午配额
        // - 熔断状态
        uint256 available = remainingStakeAmount();

        uint256 processed = 0;

        // ================= 顺序处理队列 =================
        // 关键点：
        // 1. 严格 FIFO（queueHead）
        // 2. 永远不会跳过一个“金额过大但合法”的订单
        // 3. 不足额度就直接 break，等待下一次
        while (
            processed < count &&
            queueHead < queueList.length &&
            available > 0
        ) {

            QueueInfo storage info = queueList[queueHead];

            // ================= 跳过无效订单 =================
            // 被取消 or 已处理的订单，直接略过
            if (info.processed || info.cancelled) {
                queueHead++;
                continue;
            }

            // ================= 额度不足直接停止 =================
            // 这里不“部分成交”，也不跳过
            //
            // 设计目的：
            // - 保证绝对公平（先来先处理）
            // - 防止大单被拆单套利
            if (info.amount > available) {
                break;
            }

            // ================= 正式执行 stake / restake =================
            if (info.restakeIndex == 0) {

                // 普通 stake
                STAKING.stakeFor(
                    info.user,
                    info.amount,
                    info.stakeIndex
                );

                // 如果是 1day，解除 pending 标记
                if (info.stakeIndex == 0) {
                    hasPendingOneDayStake[info.user] = false;
                }

            } else {

                // 复投逻辑
                // restakeIndex - 1 对应 staking record index
                STAKING.restakeFor(
                    info.user,
                    info.restakeIndex - 1,
                    info.amount,
                    info.stakeIndex
                );

                // 解除复投 pending 状态
                hasPendingRestake[info.user][info.restakeIndex - 1] = false;
            }

            // ================= 更新订单状态 =================
            info.processed = true;

            // ================= 更新排队资金统计 =================
            queuedUsdtAmount -= info.amount;

            // ================= 更新每日质押统计 =================
            // 影响后续 remainingStakeAmount
            _updateDailyStaked(info.amount);

            // ================= 发放 FOMO 奖励（如果有） =================
            // ⚠️ 注意：
            // - 只有在“成功处理订单”时才给用户
            // - 如果订单被 cancel，则奖励给 marketing
            _claimFomoReward(queueHead, true);

            // ================= 扣减剩余额度 =================
            available -= info.amount;

            // ================= 触发处理事件 =================
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

    function distributeFomo() external nonReentrant whenNotPaused {

        // ================= 外部触发 FOMO 分配 =================
        // 该函数只是一个安全包装入口：
        // - 实际分配逻辑在 _distributeFomoInternal
        // - 失败时直接 revert，避免“静默失败”
        bool success = _distributeFomoInternal();
        require(success, "cannot distribute");
    }


    function _findFomoWinnersView()
        private
        view
        returns (uint256[] memory indices)
    {
        uint256 eligibleLen = fomoEligibleQueues.length;

        // ================= 边界保护 =================
        // 若尚无任何新增 eligible queue
        // 或 lastFomoIdx 已追上数组尾部，则无需扫描
        if (eligibleLen <= lastFomoIdx) {
            return new uint256;
        }

        // ================= 临时存储 =================
        // tempIndices: 记录候选 queueIndex
        // seenUsers:   用于避免同一 user 重复中奖
        uint256[] memory tempIndices = new uint256[](FOMO_WINNERS_COUNT);
        address[] memory seenUsers = new address[](FOMO_WINNERS_COUNT);
        uint256 added = 0;
        uint256 scanned = 0;

        // ================= 反向扫描 eligible queue =================
        // 从最新加入的 queue 开始向前扫描：
        // - 优先考虑近期参与的用户
        // - 避免早期地址长期占据优势
        //
        // 扫描终止条件：
        // 1. 已选满 FOMO_WINNERS_COUNT
        // 2. 扫描次数达到 maxFomoScanCount
        // 3. 已扫描到 lastFomoIdx
        for (
            uint256 i = eligibleLen - 1;
            i >= lastFomoIdx &&
                added < FOMO_WINNERS_COUNT &&
                scanned < maxFomoScanCount;
        ) {
            scanned++;

            uint256 queueIndex = fomoEligibleQueues[i];
            QueueInfo storage info = queueList[queueIndex];

            // ================= 合法性过滤 =================
            // 仅考虑：
            // - 未被取消
            // - 未被处理的 queue
            if (!info.cancelled && !info.processed) {

                // ================= 去重检查 =================
                // 同一 user 在一次 FOMO 分配中只能中奖一次
                bool duplicate = false;
                for (uint256 j = 0; j < added; j++) {
                    if (seenUsers[j] == info.user) {
                        duplicate = true;
                        break;
                    }
                }

                // ================= 记录有效候选 =================
                if (!duplicate) {
                    tempIndices[added] = queueIndex;
                    seenUsers[added] = info.user;
                    added++;
                }
            }

            // ================= uint 下溢保护 =================
            if (i == 0) break;
            i--;
        }

        // ================= 精确裁剪结果数组 =================
        indices = new uint256[](added);
        for (uint256 i = 0; i < added; i++) {
            indices[i] = tempIndices[i];
        }
    }


    function _claimFomoReward(uint256 queueIndex, bool toUser) private {

        // ================= 读取并校验奖励 =================
        // queueFomoReward 在发放后会被清零
        uint256 reward = queueFomoReward[queueIndex];
        if (reward > 0) {

            // ================= 防重入 & 防重复领取 =================
            queueFomoReward[queueIndex] = 0;

            // ================= 确定接收地址 =================
            // toUser = true  → queue 创建者
            // toUser = false → 市场 / 营销地址
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
        // ================= 查询当前可视 FOMO 赢家 =================
        // 该函数不会修改任何状态
        indices = _findFomoWinnersView();

        // ================= 返回对应的 queue 信息 =================
        infos = new QueueInfo[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            infos[i] = queueList[indices[i]];
        }
    }


    function _distributeFomoInternal() private returns (bool success) {

        // ================= 基础开关校验 =================
        if (!fomoEnabled) return false;

        uint256 today = _today();

        // ================= 每日只允许分配一次 =================
        // 或在奖池为空时直接跳过
        if (today <= lastDistributeDay || fomoPool == 0) {
            return false;
        }

        uint256 eligibleLen = fomoEligibleQueues.length;

        // ================= 无新增 eligible queue =================
        if (eligibleLen <= lastFomoIdx) {
            return false;
        }

        // ================= 获取赢家列表 =================
        uint256[] memory winnerQueueIndices = _findFomoWinnersView();
        if (winnerQueueIndices.length == 0) {
            return false;
        }

        // ================= 平均分配奖池 =================
        uint256 rewardPerWinner = fomoPool / winnerQueueIndices.length;
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < winnerQueueIndices.length; i++) {
            uint256 queueIdx = winnerQueueIndices[i];
            queueFomoReward[queueIdx] = rewardPerWinner;
            totalDistributed += rewardPerWinner;
        }

        // ================= 状态更新 =================
        // - 扣减已分配金额
        // - 记录分配日期
        // - 将 lastFomoIdx 推进到当前 eligible 队列尾部
        fomoPool -= totalDistributed;
        lastDistributeDay = today;
        lastFomoIdx = fomoEligibleQueues.length;
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
            bool willTriggerSoft
        )
    {
        // ================= 获取当前池子储备 =================
        uint112 currentReserveU = LAX.getCurrentReserveU();

        // ================= 是否刷新历史最高值 =================
        bool needUpdateHigh = currentReserveU > historicalHighU;

        // ================= 硬熔断触发条件 =================
        // 尚未触发熔断，且历史高点存在
        if (circuitBreakerTime == 0 && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * CIRCUIT_BREAKER_THRESHOLD
            ) {
                willTriggerHard = true;
            }
        }

        // ================= 硬熔断恢复判断 =================
        if (circuitBreakerTime > 0) {
            if (recoveryRecordU == 0) {
                // 第一次恢复记录点
                if (currentReserveU >= historicalHighU) {
                    needUpdate = true;
                }
            } else {
                // 达到恢复倍数，解除熔断
                if (
                    currentReserveU >=
                    recoveryRecordU * CIRCUIT_BREAKER_RECOVERY_MULTIPLE
                ) {
                    willRecoverHard = true;
                }
            }
        }

        // ================= 软熔断触发条件 =================
        if (!softCircuitBreakerTriggered && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * (100 - SOFT_CIRCUIT_BREAKER_THRESHOLD)
            ) {
                willTriggerSoft = true;
            }
        }

        // ================= 是否需要调用 update =================
        needUpdate =
            needUpdateHigh ||
            willTriggerHard ||
            willRecoverHard ||
            willTriggerSoft;
    }


    function updateCircuitBreaker() external {
        uint112 currentReserveU = LAX.getCurrentReserveU();

        if (currentReserveU > historicalHighU) {
            historicalHighU = currentReserveU;
        }

        if (circuitBreakerTime == 0 && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * CIRCUIT_BREAKER_THRESHOLD
            ) {
                circuitBreakerTime = uint40(block.timestamp);
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

        if (!softCircuitBreakerTriggered && historicalHighU > 0) {
            if (
                currentReserveU * 100 <=
                historicalHighU * (100 - SOFT_CIRCUIT_BREAKER_THRESHOLD)
            ) {
                softCircuitBreakerTriggered = true;
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
        uint112 reserveU = LAX.getYesterdayCloseReserveU();

        if (isEarlyPeriod()) {
            return type(uint256).max;
        }

        uint256 rate;
        if (reserveU < STAGE1_THRESHOLD) {
            rate = 50; // 5%
        } else if (reserveU < STAGE2_THRESHOLD) {
            rate = 60; // 6%
        } else if (reserveU < STAGE3_THRESHOLD) {
            rate = 70; // 7%
        } else {
            rate = 80; // 8%
        }
        return (uint256(reserveU) * rate) / 1000;
    }

   
    function getDailyUnstakeLimit() public view returns (uint256) {
        uint112 reserveU = LAX.getYesterdayCloseReserveU();
        uint256 rate;
        if (reserveU < STAGE1_THRESHOLD) {
            rate = 60; // 6%  (0-1000万)
        } else if (reserveU < STAGE2_THRESHOLD) {
            rate = 70; // 7%  (1000万-3000万)
        } else {
            rate = 80; // 8%  (3000万以上，包括≥1亿)
        }
        return (uint256(reserveU) * rate) / 1000;
    }

    function remainingUnstakeAmount() public view returns (uint256) {
        uint256 unstaked = dailyTotalUnstaked[_today()];
        uint256 limit = getDailyUnstakeLimit();
        return unstaked >= limit ? 0 : limit - unstaked;
    }

    function getWorkshopUnstakeLimit() public view returns (uint256) {
        uint112 reserveU = LAX.getYesterdayCloseReserveU();
        return (uint256(reserveU) * WORKSHOP_UNSTAKE_RATE) / 1000;
    }

    function remainingWorkshopUnstakeAmount() public view returns (uint256) {
        if (!softCircuitBreakerTriggered) return type(uint256).max;
        uint256 limit = getWorkshopUnstakeLimit();
        uint256 used = dailyWorkshopUnstaked[_today()];
        return used >= limit ? 0 : limit - used;
    }

    function checkUnstakeLimit(
        address user,
        uint256 amount,
        uint40 stakeTime
    ) external view returns (bool allowed, string memory reason) {
        if (isOrderAffectedByCircuitBreaker(stakeTime)) {
            return (false, "circuit breaker: old order cannot unstake");
        }

        if (isWorkshop[user] && amount > remainingWorkshopUnstakeAmount()) {
            return (false, "workshop daily limit: 0.3%");
        }

        if (amount > remainingUnstakeAmount()) {
            return (false, "daily unstake limit");
        }

        return (true, "");
    }

    function _recordUnstake(address user, uint256 amount) private {
        uint256 today = _today();
        dailyTotalUnstaked[today] += amount;

        if (softCircuitBreakerTriggered && isWorkshop[user]) {
            dailyWorkshopUnstaked[today] += amount;
        }
    }

    // ============ View Functions ============
    function isFirstDay() public view returns (bool) {
        return launchTime > 0 && block.timestamp < launchTime + 1 days;
    }

    function isEarlyPeriod() public view returns (bool) {
        return
            launchTime > 0 &&
            block.timestamp < launchTime + EARLY_DAYS * 1 days;
    }

    function isFirstMonth() public view returns (bool) {
        return
            launchTime > 0 &&
            block.timestamp < launchTime + FIRST_MONTH_DAYS * 1 days;
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

        // ================= 拉取用户 USDT =================
        // 这里一次性把用户的全部金额拉进 Queue 合约
        // 而不是在 processQueue 时再 transfer
        //
        // 目的：
        // 1. 锁定用户资金，避免用户在排队期间反悔或挪用
        // 2. 防止额度到了但用户余额不足导致处理失败
        // 3. 保证 queueList 中的订单一定是“已付款订单”
        USDT.transferFrom(user, address(this), amount);

        uint160 actualAmount;

        // ================= FOMO 手续费处理 =================
        // 如果开启 FOMO：
        // - QUEUE_ENTRY_FEE 进入 fomoPool
        // - 剩余部分才是真正进入 staking 的金额
        //
        // 这样设计的好处：
        // - staking 合约完全不用关心手续费
        // - APR / 收益计算不被污染
        if (fomoEnabled) {
            fomoPool += QUEUE_ENTRY_FEE;
            actualAmount = amount - uint160(QUEUE_ENTRY_FEE);
        } else {
            actualAmount = amount;
        }

        // ================= 生成队列订单 =================
        // ⚠️ 注意：
        // - processed / cancelled 初始都为 false
        // - restakeIndex = 0 表示普通 stake
        // - restakeIndex > 0 表示复投，对应 staking record index + 1
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

        // ================= 统计排队中的 USDT =================
        // queuedUsdtAmount 用于：
        // - emergencyWithdraw 的安全校验
        // - 防止 owner 把“尚未处理的用户资金”提走
        queuedUsdtAmount += actualAmount;

        uint256 queueIndex = queueList.length - 1;

        // ================= FOMO 参与资格 =================
        // 只有满足以下条件的订单才有资格参与 FOMO：
        // 1. 开启 FOMO
        // 2. 金额等于最大单笔（鼓励大单）
        // 3. stakeIndex == 2（30 天，长期用户）
        //
        // 这样可以：
        // - 引导长期 + 大额用户
        // - 避免小额刷 FOMO
        if (fomoEnabled && amount >= maxStakeAmountValue && stakeIndex == 2) {
            fomoEligibleQueues.push(queueIndex);
        }

        // ================= 触发入队事件 =================
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

        if (isFirstMonth()) {
            require(stakeIndex == 2, "first month: 30 days only");
        }

        if (isFirstDay()) {
            require(!isNewUser[user], "first day: original users only");
        }

        if (isEarlyPeriod()) {
            require(
                userDailyStakeCount[user][_today()] < EARLY_MAX_ORDERS_PER_DAY,
                "early period: 1 order per day"
            );
        }
    }

    function _today() private view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _updateDailyStaked(uint256 amount) private {

        // ================= 更新当日已成功质押总量 =================
        // 这里记录的是「已经真正执行 stake 的金额」
        //
        // 调用时机：
        // - 仅在 queue 中的订单被成功处理
        // - 且 stake / restake 已经实际发生之后
        //
        // ⚠️ 不会在以下情况下调用：
        // - 用户进入 queue
        // - 用户取消 queue
        // - 仅校验额度但未执行 stake
        //
        // 因此 dailyTotalStaked 代表的是：
        // “当日已生效的质押总量”，而不是排队中的金额
        dailyTotalStaked[_today()] += amount;
    }


    function remainingStakeAmount() public view returns (uint256) {

        // ================= 熔断总开关 =================
        // 一旦熔断触发：
        // - 所有 queue 处理立即暂停
        // - 已排队用户资金仍然安全锁定
        // - 不会影响 cancelQueue / emergencyWithdraw
        //
        // 这是一个“软熔断”：
        // - 不冻结合约
        // - 不影响已存在 stake 的收益
        if (circuitBreakerActive) {
            return 0;
        }

        // ================= 计算当前所在日期 =================
        // 使用 block.timestamp / 1 days
        // 而不是区块号，避免链上时间不确定性
        uint256 today = block.timestamp / 1 days;

        // ================= 每日总额度限制 =================
        // dailyStakeLimitValue 是系统的“硬天花板”
        // 无论什么 stake 类型，都不能突破
        uint256 remainingDaily =
            dailyStakeLimitValue - dailyStakedAmount[today];

        // ================= 1 Day 单独限额 =================
        // 1 Day stake 是最容易被刷的短期行为
        // 因此额外设置 dailyOneDayStakeLimitValue
        uint256 remainingOneDay =
            dailyOneDayStakeLimitValue - dailyOneDayStaked[today];

        // ================= 上午 / 下午时间窗 =================
        // 上午、下午各自有独立额度
        // 防止某个时间段被机器人打爆
        bool isMorning = (block.timestamp % 1 days) < 12 hours;

        uint256 remainingWindow =
            isMorning
                ? morningStakeLimitValue - morningStakedAmount[today]
                : afternoonStakeLimitValue - afternoonStakedAmount[today];

        // ================= 取最小可用额度 =================
        // 任何一个维度触底，系统立即停止接单
        //
        // 这是一种“多维限流”设计：
        // - 日总量
        // - 时间窗
        // - 行为类型（1 Day）
        uint256 remaining = remainingDaily;

        if (remaining > remainingWindow) {
            remaining = remainingWindow;
        }

        if (remaining > remainingOneDay) {
            remaining = remainingOneDay;
        }

        return remaining;
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


// 一、熔断逻辑（Circuit Breaker）
// 核心目的

// 防止系统在 LAX 代币储备大幅下跌时继续开放新订单，保护流动性和稳定性。

// 包含硬熔断 (hard) 和软熔断 (soft) 两种机制。

// 影响：

// 排队订单处理 (_processQueueInternal) 会暂停。

// 已排队资金仍然安全。

// 用户可以取消订单或紧急提现 (cancelQueue / emergencyWithdraw)。

// 主要变量
// uint40 public circuitBreakerTime;      // 硬熔断触发时间
// uint112 public historicalHighU;        // 历史最高储备
// uint112 public recoveryRecordU;        // 恢复记录储备
// bool public softCircuitBreakerTriggered; // 软熔断触发状态

// 1️⃣ 判断是否需要更新熔断状态

// 函数：shouldUpdateCircuitBreaker()

// 步骤：

// 获取当前池子储备 currentReserveU = LAX.getCurrentReserveU()

// 判断是否刷新历史高点：

// if (currentReserveU > historicalHighU) needUpdateHigh = true;


// 判断硬熔断触发条件：

// 历史高点存在，熔断未触发。

// 如果 currentReserveU * 100 <= historicalHighU * CIRCUIT_BREAKER_THRESHOLD，则硬熔断触发。

// 判断硬熔断恢复条件：

// 熔断已触发且记录 recoveryRecordU 为 0：首次恢复记录点为 currentReserveU >= historicalHighU。

// 已有恢复记录时，达到 currentReserveU >= recoveryRecordU * CIRCUIT_BREAKER_RECOVERY_MULTIPLE 则解除熔断。

// 判断软熔断触发条件：

// softCircuitBreakerTriggered 为 false。

// currentReserveU * 100 <= historicalHighU * (100 - SOFT_CIRCUIT_BREAKER_THRESHOLD)，触发软熔断。

// 返回四个 bool 值：needUpdate, willTriggerHard, willRecoverHard, willTriggerSoft。

// 2️⃣ 更新熔断状态

// 函数：updateCircuitBreaker()

// 步骤：

// 更新历史高点：

// if (currentReserveU > historicalHighU) historicalHighU = currentReserveU;


// 硬熔断触发：

// if (circuitBreakerTime == 0 && currentReserveU * 100 <= historicalHighU * CIRCUIT_BREAKER_THRESHOLD)
//     circuitBreakerTime = block.timestamp;
//     recoveryRecordU = 0;


// 硬熔断恢复：

// 第一次恢复记录点：recoveryRecordU = currentReserveU >= historicalHighU ? currentReserveU : 0

// 达到恢复倍数：解除熔断

// 软熔断触发：

// softCircuitBreakerTriggered = true 当 currentReserveU * 100 <= historicalHighU * (100 - SOFT_CIRCUIT_BREAKER_THRESHOLD)

// 3️⃣ 判断订单是否受熔断影响

// 函数：isOrderAffectedByCircuitBreaker(stakeTime)

// 条件：

// 硬熔断激活 (circuitBreakerTime > 0)

// 订单 stakeTime < circuitBreakerTime

// 返回 true → 订单不能 unstake。

// 4️⃣ 影响范围

// remainingStakeAmount()：

// 如果熔断激活，返回 0 → 队列处理暂停。

// checkUnstakeLimit()：

// 已经生效的订单，硬熔断期间，旧订单不能解押。

// dailyWorkshopUnstaked：

// 软熔断触发时限制工作室提现。

// 二、排队逻辑（Queue / FIFO）
// 核心目的

// 用户 stake / restake 时不会立即进入质押，而是生成一个队列订单。

// FIFO 顺序处理，保证公平。

// 支持取消、复投、FOMO 奖励分发。

// 主要数据结构
// struct QueueInfo {
//     address user;
//     uint160 amount;
//     uint40 queueTime;
//     uint8 stakeIndex;
//     bool processed;
//     bool cancelled;
//     uint256 restakeIndex; // 0 = 普通 stake, >0 = restake
// }

// QueueInfo[] public queueList;  // 队列数组
// uint256 public queueHead;       // 当前处理头指针
// uint256 public queuedUsdtAmount; // 当前排队资金总量

// 1️⃣ 用户进入队列

// 函数：_enterQueue(user, amount, stakeIndex, restakeIndex)

// 步骤：

// 拉取用户 USDT：

// USDT.transferFrom(user, address(this), amount);


// FOMO 手续费处理：

// 扣除 QUEUE_ENTRY_FEE → fomoPool

// 实际 stake 金额 = amount - QUEUE_ENTRY_FEE

// 创建 QueueInfo 并 push 到 queueList

// 更新 queuedUsdtAmount += actualAmount

// 如果金额 >= 最大单笔且 stakeIndex == 2 → 加入 fomoEligibleQueues

// 触发事件 Queued(...)

// 2️⃣ 处理队列（FIFO）

// 函数：_processQueueInternal(count)

// 步骤：

// 获取可用额度 available = remainingStakeAmount()（受熔断和每日额度限制）

// 循环处理队列：

// while(processed < count && queueHead < queueList.length && available > 0)


// 跳过无效订单：

// 已处理或已取消 → queueHead++

// 如果订单金额 > 可用额度 → break（不拆单）

// 执行 stake / restake：

// 普通 stake → STAKING.stakeFor(...)

// restake → STAKING.restakeFor(...)

// 更新订单状态：

// info.processed = true

// queuedUsdtAmount -= info.amount

// _updateDailyStaked(info.amount)

// 发放 FOMO 奖励 _claimFomoReward(queueHead, true)

// 扣减剩余额度 available -= info.amount

// 触发事件 QueueProcessed(...)

// queueHead++

// 3️⃣ 用户取消队列

// 函数：cancelQueue(queueIndex)

// 条件：

// 只有订单所属用户或 owner 可以取消

// 订单未处理、未取消

// 步骤：

// 标记订单 info.cancelled = true

// 回滚排队资金统计 queuedUsdtAmount -= info.amount

// 解除 pending 状态：

// 普通 1day → hasPendingOneDayStake[user] = false

// restake → hasPendingRestake[user][restakeIndex - 1] = false

// 退款：

// FOMO 开启 → 扣除 CANCEL_FEE 进入 fomoPool，剩余退用户

// FOMO 关闭 → 全额退用户

// 触发事件 QueueCancelled(...)

// 4️⃣ FOMO 奖励分发

// 触发点：

// 用户 stake / restake / process 队列时 _distributeFomoInternal()

// 步骤：

// 每日只分配一次 (lastDistributeDay)

// 遍历 fomoEligibleQueues，反向扫描最近的订单

// 去重同一用户，最多 FOMO_WINNERS_COUNT

// 平均分配奖池 rewardPerWinner = fomoPool / winnerCount

// 更新 queueFomoReward[queueIndex]

// 发放奖励时调用 _claimFomoReward(queueIndex, true) → 给用户或 marketing

// 5️⃣ 队列状态查询

// getQueueLength()

// getQueueInfo(index)

// getFomoEligibleCount()

// getFomoWinners()

// 三、关键特点总结
// 特性	描述
// 排队	所有 stake / restake 生成订单 → FIFO 顺序处理
// 额度限制	每日额度、1day 产品限制、时间窗限制
// FOMO	特定订单参与奖励池 → 用户行为触发分发
// 熔断	硬熔断 → 队列暂停；软熔断 → 限制 workshop 提现
// 安全	nonReentrant、资金锁定、取消可退款、紧急提现