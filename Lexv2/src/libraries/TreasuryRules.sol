// TreasuryRules.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library TreasuryRules {

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
        uint64 rate;      // 1e18 精度
        uint32 fee;
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