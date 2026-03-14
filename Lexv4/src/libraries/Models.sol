/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

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

library Models{
    enum LevelType{INVALID, L1, L2, L3, L4, L5, L6, L7}
    enum NodeType{INVALID, ENVOY, DIRECTOR, PARTNER}
    enum Source{INVALID, TAX_FEE, PROFIT_FEE, STAKE_FEE}

    struct Order {
        uint128 amount;
        uint128 claimed;
        uint32  claimedPeriods;
        uint32  startTime;
        uint8   stakeIndex;
        uint8   status;

        uint32  createdAt;

        uint128 frozenReward;
        uint128 frozenClaimed;
        uint32  freezeStart;
        uint32  freezeRound; 
    }

    struct StakePlan {
        uint32 duration;
        uint32 claimInterval;
        uint32 window;
        uint64 rate;      // 1e18
    }

    struct Referral {
        address parent;        // 20 bytes
        LevelType level;      // 1 byte (uint8 enum)
        uint16 referralNum;     // 2 bytes
        uint256 totalStaked;    // 32 bytes
        uint256 performance;    // 32 bytes
    }

    struct RuleResult {
        uint256 claimCountdown;
        uint256 unstakeCountdown;
        bool canClaim;
        bool canUnstake;
        bool canRestake;
        bool isFrozen;
        bool isExpired;
        bool isMatured;
    }

    struct Revenue{
        address user;
        uint256 amount;
    }

    struct DirectReferral{
        address user;
        uint256 staked;
        uint256 performance;
    }
    
    struct Effective{
        LevelType level;
        address user;
        uint256 amount;
    }

    struct UnstakeRule {
        bool canUnstake;
        uint256 unstakeCountdown;
        bool isFrozenOld;
    }
}