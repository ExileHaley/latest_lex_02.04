### install foundry-rs/forge-std
```shell
$ forge install foundry-rs/forge-std --no-commit --no-git
```
### install openzeppelin-contracts
```shell
$ forge install openzeppelin/openzeppelin-contracts  --no-git
```

### install openzeppelin-contracts-upgradeable
```shell
$ forge install openzeppelin/openzeppelin-contracts-upgradeable  --no-git
```

### deploy 
```shell
$ forge script script/Deploy.s.sol -vvv --rpc-url=https://bsc.blockrazor.xyz --broadcast --private-key=[privateKey]
```

Queue 合约功能梳理
1. 合约继承与依赖

继承合约

Owned：合约所有权管理

Pausable：系统暂停与恢复

ReentrancyGuard：防重入保护

依赖接口

IStaking：质押合约接口

ILAXToken：LAX 代币接口

IReferral：推荐系统接口

IProject：项目地址配置接口

2. 常量参数
参数	说明
MIN_BIND_AMOUNT	推荐绑定最小 USDT 支付，1U
MIN_STAKE_AMOUNT	最小质押金额，2U
QUEUE_ENTRY_FEE	排队手续费，1U
CANCEL_FEE	取消排队手续费，1U
FOMO_WINNERS_COUNT	FOMO 每日赢家数量，31
STAGE1/2/3_THRESHOLD	不同额度阶段阈值，10M / 30M / 100M
CIRCUIT_BREAKER_THRESHOLD	硬熔断跌幅，5%
CIRCUIT_BREAKER_RECOVERY_MULTIPLE	硬熔断恢复倍数，3
SOFT_CIRCUIT_BREAKER_THRESHOLD	软熔断跌幅，10%
WORKSHOP_UNSTAKE_RATE	工作室每日提现限制，0.3%
EARLY_DAYS	初期天数，3 天
FIRST_MONTH_DAYS	首月天数，30 天
EARLY_MAX_ORDERS_PER_DAY	初期每日最大订单数，1
MORNING_QUOTA_RATE	上午可用额度百分比，60%
AFTERNOON_HOUR_UTC	下午开放时间，UTC 6 点
3. 核心状态变量

接口实例

STAKING：质押合约

LAX：LAX 代币

REFERRAL：推荐系统

PROJECT：项目配置

额度限制

maxStakeAmountValue：单笔最大质押

oneDayStakeDailyLimit：每日 1day 质押总额上限

userDailyStakeCount：用户每日操作次数

dailyOneDayStaked：每日 1day 累计质押

dailyTotalStaked / dailyTotalUnstaked：每日总质押/提现

熔断机制

circuitBreakerTime：硬熔断触发时间

historicalHighU：历史最高储备

recoveryRecordU：硬熔断恢复记录

softCircuitBreakerTriggered：软熔断状态

队列管理

queueList：排队信息数组

queueHead：队列头指针

queuedUsdtAmount：当前排队总量

FOMO 奖励

fomoPool：FOMO 奖池

fomoEligibleQueues：FOMO 候选队列

queueFomoReward：队列 FOMO 奖励

lastDistributeDay / lastFomoIdx：FOMO 分配记录

用户状态

isNewUser：新用户标记

hasPendingOneDayStake：用户 1day 排队状态

hasPendingRestake：用户复投排队状态

isWorkshop：工作室地址标记

4. 核心功能模块
4.1 推荐绑定

bindReferral(address parent)：

绑定用户推荐关系

支付 MIN_BIND_AMOUNT 到 FOMO 奖池（开启 FOMO 时）

标记新用户 isNewUser

4.2 质押相关

stake(_amount, _stakeIndex) / stakeWithInviter(_amount, _stakeIndex, parent)：

参数：

_stakeIndex：0=1day, 1=7day, 2=30day

内部调用 _stakeInternal：

校验最小质押、单笔最大质押

1day 产品：

用户每天最多一单

受每日 1day 总额限制 oneDayStakeDailyLimit

标记 hasPendingOneDayStake

自动绑定推荐关系（满足条件）

记录用户每日操作次数

生成排队订单 _enterQueue

尝试处理队列 _processQueueInternal

restake(_index, _amount, _stakeIndex)：

复投旧订单

不允许 1day 产品

标记复投排队状态 hasPendingRestake

更新每日操作次数

进入队列 _enterQueue

_processQueueInternal(count)：

FIFO 处理队列订单

检查每日额度、熔断状态

执行 stakeFor 或 restakeFor

更新队列状态、FOMO 奖励

4.3 取消排队

cancelQueue(queueIndex)：

用户或 owner 可以取消排队

回滚 1day 排队标记和每日已用额度

扣手续费进入 FOMO 奖池

FOMO 奖励归市场地址

4.4 提现 / 解质押

unstake(index)：

检查是否受熔断影响 isOrderAffectedByCircuitBreaker

检查每日总量 remainingUnstakeAmount

工作室提现受限 remainingWorkshopUnstakeAmount

调用 STAKING.unstakeFor

记录每日提现 _recordUnstake

checkUnstakeLimit(user, amount, stakeTime)：

返回是否允许提现 + 原因

4.5 熔断机制

硬熔断

当 LAX 储备跌幅超过 CIRCUIT_BREAKER_THRESHOLD，触发

解除条件：储备恢复 CIRCUIT_BREAKER_RECOVERY_MULTIPLE 倍

软熔断

当 LAX 储备跌幅超过 SOFT_CIRCUIT_BREAKER_THRESHOLD，触发

限制工作室提现额度

更新方法：updateCircuitBreaker()

状态检查：isCircuitBreakerActive() / isOrderAffectedByCircuitBreaker(stakeTime)

4.6 FOMO 奖励机制

奖励触发：

用户操作触发 _distributeFomoInternal

每日仅分配一次

奖励规则：

平均分配奖池到 FOMO_WINNERS_COUNT 个赢家

_claimFomoReward(queueIndex, toUser) 发放奖励

4.7 每日额度计算

getDailyStakeLimit()：

基于昨日 USDT 储备 getYesterdayCloseReserveU + 阶段比例

阶段阈值：STAGE1/2/3_THRESHOLD

早期无限制

getDailyUnstakeLimit()：

基于昨日储备 + 阶段比例

remainingUnstakeAmount() / remainingWorkshopUnstakeAmount()：

计算当前可用额度

4.8 风控规则

早期阶段限制：

isEarlyPeriod() / isFirstMonth()

限制每日最大订单数

新用户限制可质押产品周期

排队标记：

hasPendingOneDayStake / hasPendingRestake

5. 核心节点流程

用户操作：

stake / restake / bindReferral

内部：

校验风控 _stakeInternal

标记用户状态

生成队列 _enterQueue

尝试处理队列 _processQueueInternal

FOMO 分发 _distributeFomoInternal

处理队列：

FIFO 执行质押

更新每日额度、用户状态

发放 FOMO 奖励

取消队列：

回滚每日额度和 pending 状态

扣除手续费

提现：

检查熔断、每日额度、工作室限制

调用 STAKING 合约执行提现