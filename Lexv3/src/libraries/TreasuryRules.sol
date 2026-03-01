// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// | 字段             | 类型      | 分类    | 作用        |
// | -------------- | ------- | ----- | --------- |
// | amount         | uint128 | 本金    | 计算收益      |
// | claimed        | uint128 | 正常收益  | 防重复领取     |
// | claimedPeriods | uint32  | 周期控制  | claim窗口控制 |
// | startTime      | uint32  | 时间    | 计息起点      |
// | stakeIndex     | uint8   | 方案编号  | 决定利率/周期   |
// | status         | uint8   | 状态    | 是否活跃      |
// | createdAt      | uint32  | 创建时间  | 判断是否冻结    |
// | frozenReward   | uint128 | 冻结收益池 | 冻结释放总额    |
// | frozenClaimed  | uint128 | 已释放   | 防重复释放     |
// | freezeStart    | uint32  | 冻结时间  | 计算释放比例    |
// | freezeRound    | uint32  | 冻结轮次  | 防止重复冻结    |

library TreasuryRules {

    struct Order {
        uint128 amount; //质押数量
        uint128 claimed; //正常收益已提取部分
        uint32  claimedPeriods; //已经领取了多少个周期，用于计算下一次领取窗口
        uint32  startTime;  //订单开始时间
        uint8   stakeIndex; //订单类型，0、1、2、3分别是1天，15天，30天，90天
        uint8   status; // 0代表质押中、1代表已赎回

        uint32  createdAt; //订单创建时间，用于区分冻结前还是冻结后创建的订单

        uint128 frozenReward; //冻结发生时，订单已经产生但尚未领取的收益总额
        uint128 frozenClaimed; //冻结后已经释放并领取的金额
        uint32  freezeStart; //冻结释放开始时间
        uint32  freezeRound; //该订单属于哪一次冻结轮次，每次 pause，pauseRound += 1;
    }

    struct StakePlan {
        uint32 duration;
        uint32 claimInterval;
        uint64 rate;      // 1e18 精度
    }

    struct RuleResult {
        bool canClaim;
        bool canUnstake;
        bool canRestake;
        bool isFrozen;
        bool isExpired;
        bool isMatured;
    }

    function checkRules(
        Order memory order,
        StakePlan memory plan,
        bool paused,
        uint32 pauseRound,
        uint256 currentTime
    ) internal pure returns (RuleResult memory r) {
        r.isMatured = currentTime >= order.startTime + plan.duration;
        r.isExpired = currentTime > order.startTime + 365 days;
        r.isFrozen = paused && order.freezeRound == pauseRound;

        if (order.stakeIndex == 0) {
            bool matured = currentTime >= order.startTime + 1 days;
            r.canClaim = matured;
            r.canUnstake = matured;
            r.canRestake = matured;
            return r;
        }

        if (r.isFrozen) {
            r.canClaim = true;
            return r;
        }

        if (r.isMatured && !r.isExpired) r.canUnstake = true;
        if (r.isMatured && currentTime <= order.startTime + plan.duration + 1 days) r.canRestake = true;

        uint256 nextClaimTime = order.startTime + plan.claimInterval * (order.claimedPeriods + 1);
        if (currentTime >= nextClaimTime && currentTime <= nextClaimTime + 1 days) r.canClaim = true;
    }

    function isInClaimWindow(Order memory order, StakePlan memory plan, uint256 currentTime) internal pure returns (bool) {
        uint256 nextClaimTime = order.startTime + plan.claimInterval * (order.claimedPeriods + 1);
        return currentTime >= nextClaimTime && currentTime <= nextClaimTime + 1 days;
    }

    function isFrozenOldOrder(Order memory order, bool paused, uint32 pauseRound) internal pure returns (bool) {
        return paused && order.freezeRound == pauseRound;
    }

    function isExpired(Order memory order, uint256 currentTime) internal pure returns (bool) {
        return currentTime > order.startTime + 365 days;
    }

    function isMatured(Order memory order, StakePlan memory plan, uint256 currentTime) internal pure returns (bool) {
        return currentTime >= order.startTime + plan.duration;
    }

    function isActive(Order memory order) internal pure {
        require(order.status == 0, "Order inactive");
    }

    
}