/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// | field          | type    |         
// | -------------- | ------- | ---------------- 
// | amount         | uint128 | principal        
// | claimed        | uint128 | withdrawn earnings 
// | claimedPeriods | uint32  | claim window          
// | startTime      | uint32  | staking time - Interest start time
// | stakeIndex     | uint8   | plan number -  Determine the interest rate/cycle
// | status         | uint8   | status - 0/staking｜｜1/unstaked
// | createdAt      | uint32  | create time - Determine whether to freeze
// | frozenReward   | uint128 | freeze revenue pool
// | frozenClaimed  | uint128 | withdrawn frozen earnings 
// | freezeStart    | uint32  | freeze time
// | freezeRound    | uint32  | prevent repeated freezing

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

    struct FomoAwards{
        uint256 rounds;
        uint256 amount;
    }
}