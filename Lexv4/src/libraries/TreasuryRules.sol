// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Models } from "./Models.sol";

library TreasuryRules {

    /// @notice Calculate the profit under normal conditions.
    function calculateNormal(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        uint256 pauseTime
    ) internal pure returns (uint256) {

        if(order.status != 0) return 0;

        uint256 end = currentTime;

        uint256 durationEnd = order.startTime + plan.duration;

        if(end > durationEnd){
            end = durationEnd;
        }

        if(pauseTime > 0 && end > pauseTime){
            end = pauseTime;
        }

        if(end <= order.startTime){
            return 0;
        }

        uint256 elapsed = end - order.startTime;

        return uint256(order.amount) * elapsed * plan.rate / 1e18;
    }

    /// @notice Calculation of frozen release quantity.
    function calculateFrozenReleased(
        Models.Order memory order,
        uint256 currentTime,
        uint256 releaseRatePerDay
    ) internal pure returns(uint256){

        if(order.freezeStart == 0) return 0;

        uint256 daysPassed = (currentTime - order.freezeStart) / 1 days;

        uint256 ratio = daysPassed * releaseRatePerDay;

        if(ratio > 1e18){
            ratio = 1e18;
        }

        return uint256(order.frozenReward) * ratio / 1e18;
    }

    /// @notice Calculate the earnings available for each order (considering whether they are frozen or already claimed).
    function pendingReward(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        uint256 pauseTime,
        uint256 releaseRatePerDay
    ) internal pure returns(uint256){

        uint256 normal = calculateNormal(
            order,
            plan,
            currentTime,
            pauseTime
        );

        uint256 frozenReleased = calculateFrozenReleased(
            order,
            currentTime,
            releaseRatePerDay
        );

        uint256 totalEarned = normal + frozenReleased;

        uint256 totalClaimed =
            uint256(order.claimed) +
            uint256(order.frozenClaimed);

        if(totalEarned <= totalClaimed){
            return 0;
        }

        return totalEarned - totalClaimed;
    }


    function applyPause(
        Models.Order storage order,
        Models.StakePlan memory plan,
        uint32 pauseTime,
        uint32 pauseRound,
        bool paused,
        uint256 currentTime
    ) internal {

        if(!paused) return;
        if(order.createdAt >= pauseTime) return;
        if(order.freezeStart != 0) return;

        // Revenue is calculated up to the pauseTime.
        uint256 total = calculateNormal(order, plan, currentTime, pauseTime);

        uint256 unclaimed =
            total > order.claimed
            ? total - order.claimed
            : 0;

        order.frozenReward = uint128(unclaimed);

        order.freezeStart = pauseTime;

        order.freezeRound = pauseRound;
    }


    /// @notice Check if the order is in the withdrawable earnings window
    /// @param frozen (Is the device frozen?)
    function isInClaimWindow(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool frozen
    ) internal pure returns (bool) {
        if (frozen) {
            return true;
        }

        uint256 start = order.startTime;
        uint256 endTime = start + plan.duration;

        // Expired + Cannot be collected at the window
        if (currentTime > endTime + plan.window) {
            return false;
        }

        // The current time is at least longer than the interval between the first claim.
        if (currentTime < start + plan.claimInterval) {
            return false;
        }

        // Calculate the current period
        uint256 elapsed = currentTime - start;
        uint256 periods = elapsed / plan.claimInterval;
        uint256 maxPeriods = plan.duration / plan.claimInterval;
        if (periods > maxPeriods) periods = maxPeriods;

        // Has the current period been claimed
        if (periods <= order.claimedPeriods) {
            return false;
        }

        // Is the current time in the window
        uint256 claimWindowStart = start + periods * plan.claimInterval;
        uint256 claimWindowEnd   = claimWindowStart + plan.window;
        return currentTime >= claimWindowStart && currentTime <= claimWindowEnd;
    }


    /// @notice Check if the order is still active.
    function isActive(Models.Order memory order) internal pure {
        require(order.status == 0, "Order inactive");
    }

    /// @notice Check if the orders are old orders from before they were frozen.
    function isFrozenOldOrder(
        Models.Order memory order,
        uint32 pauseTime,
        bool paused
    ) internal pure returns(bool) {
        return paused && order.createdAt < pauseTime;
    }

    /// @notice Verify revenue extraction rules
    /// @notice Verify the revenue extraction rules and fully reuse isInClaimWindow.
    function validateClaim(
        Models.Order memory order,
        Models.StakePlan memory plan,
        bool frozen,
        uint256 currentTime
    ) internal pure {
        require(order.status == 0, "Order inactive");
        require(currentTime <= order.startTime + 365 days, "Order expired");

        // Frozen status, available for collection at any time
        if (frozen) return;

        // Regular orders call a unified claim window
        require(isInClaimWindow(order, plan, currentTime, frozen), "Not in claim window");
    }

    /// @notice The inner function is used to return the relevant status.
    function _unstakeRule(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime
    ) internal pure returns (Models.UnstakeRule memory rule) {
        rule.isFrozenOld = paused && order.createdAt < pauseTime;

        if(order.status != 0){
            rule.canUnstake = false;
            rule.unstakeCountdown = type(uint256).max;
            rule.isFrozenOld = false;
            return rule;
        }

        if(rule.isFrozenOld){
            rule.canUnstake = false;
            rule.unstakeCountdown = type(uint256).max;
            return rule;
        }

        uint256 maturityTime = order.startTime + plan.duration;
        uint256 expiryTime   = order.startTime + 365 days;

        if(currentTime < maturityTime){
            rule.canUnstake = false;
            rule.unstakeCountdown = maturityTime - currentTime;
        } else if(currentTime <= expiryTime){
            rule.canUnstake = true;
            rule.unstakeCountdown = 0;
        } else {
            rule.canUnstake = false;
            rule.unstakeCountdown = type(uint256).max;
        }
    }

    /// @notice Verify if the order is redeemable
    /// @param order order infos
    /// @param plan Corresponding Pledge Plan
    /// @param currentTime current time
    /// @param paused Was this an order placed before the freeze
    /// @param pauseTime paused time
    function validateUnstakePre(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime
    ) internal pure {
        // require(order.status == 0, "Order inactive");
        Models.UnstakeRule memory rule = _unstakeRule(order, plan, currentTime, paused, pauseTime);
        require(!rule.isFrozenOld, "Frozen pre-order cannot unstake");
        require(rule.canUnstake, "Order not matured or expired");
    }


    /// @notice Calculate the redemption principal and fees (considering withdrawn profits, fixed fees, and late payment penalties).
    /// @param order order memory
    /// @param plan  plan memory
    /// @param currentTime current time
    /// @return payout The actual principal received by the user
    /// @return fixedFee fixed fee
    /// @return overdueFee Overdue penalty
    function calculateUnstakePrincipal(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime
    ) internal pure returns(uint256 payout, uint256 fixedFee, uint256 overdueFee) {

        uint256 principal = order.amount;

        // ===== 1️⃣ Withdrawn profits have tied up principal =====
        uint256 claimedPrincipal = (order.claimed + order.frozenClaimed) * 90 / 100;
        require(claimedPrincipal <= principal, "Claimed exceeds principal");

        uint256 remaining = principal - claimedPrincipal;

        // ===== 2️⃣ Fixed Transaction Fee 10% =====
        fixedFee = principal * 10 / 100;
        if(fixedFee > remaining){
            fixedFee = remaining;
        }
        remaining -= fixedFee;

        // ===== 3️⃣ Overdue Penalties =====
        uint256 maturityTime = order.startTime + plan.duration;
        uint256 gracePeriodEnd = maturityTime + plan.window; 

        overdueFee = 0;
        if(currentTime > gracePeriodEnd){
            uint256 overdueDays = (currentTime - gracePeriodEnd) / plan.window;
            overdueFee = principal * 10 / 100 * overdueDays;
            if(overdueFee > remaining){
                overdueFee = remaining;
            }
            remaining -= overdueFee;
        }

        // ===== 4️⃣ Remaining Principal =====
        payout = remaining;
    }


    /// @notice Verify the preconditions for re-pledge
    function _restakeRule(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) internal pure returns (bool canRestake) {
        // First determine the redemption rules
        Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);

        // Frozen orders or orders that have not yet expired and cannot be pledged again
        if(!unstakeRule.canUnstake) {
            return false;
        }

        // The new stakeIndex must be greater than the old stakeIndex (special handling is required if stakeIndex is 0 for the first time).
        if(newStakeIndex < order.stakeIndex + (order.stakeIndex == 0 ? 1 : 0)){
            return false;
        }

        return true;
    }


    function validateRestakePre(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) internal pure {
        bool canRestake = _restakeRule(order, plan, currentTime, paused, pauseTime, newStakeIndex);
        require(canRestake, "Cannot restake");

        // Re-pledged shares must be redeemable.
        Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);
        require(unstakeRule.canUnstake, "Order not matured or expired");
    }

    /// @notice Calculate the repurchase yield
    function calculateRestakeReward(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        uint256 releaseRatePerDay,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) internal pure returns(uint256 reward){
        Models.RuleResult memory result = getStatus(order, plan, currentTime, paused, pauseTime, newStakeIndex, releaseRatePerDay);

        if(!result.canClaim || !result.canRestake || result.claimCountdown == type(uint256).max){
            return 0;
        }

        // Redemption reward = available earnings (considering frozen release)
        reward = pendingReward(order, plan, currentTime, 0, releaseRatePerDay);
    }   

    // /// @notice Return order current status information
    // function getStatus(
    //     Models.Order memory order,
    //     Models.StakePlan memory plan,
    //     uint256 currentTime,
    //     bool paused,
    //     uint32 pauseTime,
    //     uint8 newStakeIndex,
    //     uint256 releaseRatePerDay
    // ) internal pure returns (Models.RuleResult memory result) {
    //     uint256 start = order.startTime;
    //     uint256 maturityTime = start + plan.duration;
    //     uint256 expiryTime = start + 365 days;

        
    //     // ===== 1️⃣ Frozen Status =====
    //     result.isFrozen = paused && order.createdAt < pauseTime;

    //     // ===== 2️⃣ claim =====
    //     bool inWindow = isInClaimWindow(order, plan, currentTime, result.isFrozen);
    //     uint256 reward = pendingReward(
    //         order,
    //         plan,
    //         currentTime,
    //         result.isFrozen ? pauseTime : 0,
    //         releaseRatePerDay
    //     );

    //     result.canClaim = order.status == 0 && inWindow && reward > 0;
        
    //     if (result.canClaim) {
    //         result.claimCountdown = 0;
    //     } else {
    //         // 已过期
    //         if(currentTime > start + 365 days){
    //             result.claimCountdown = type(uint256).max;
    //         } 
    //         else {

    //             uint256 elapsed = currentTime > start ? currentTime - start : 0;

    //             uint256 periods = elapsed / plan.claimInterval;
    //             uint256 maxPeriods = plan.duration / plan.claimInterval;

    //             // 已超过最后周期
    //             if(periods >= maxPeriods){
    //                 result.claimCountdown = type(uint256).max;
    //             } 
    //             else {

    //                 uint256 nextWindowStart = start + (periods + 1) * plan.claimInterval;

    //                 result.claimCountdown =
    //                     nextWindowStart > currentTime
    //                     ? nextWindowStart - currentTime
    //                     : 0;
    //             }
    //         }
    //     }

    //     // ===== 3️⃣ unstake =====
    //     Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);
    //     result.canUnstake = unstakeRule.canUnstake;
    //     result.unstakeCountdown = unstakeRule.unstakeCountdown;

    //     // ===== 4️⃣ restake =====
    //     result.canRestake = _restakeRule(order, plan, currentTime, paused, pauseTime, newStakeIndex);

    //     // ===== 5️⃣ 状态 =====
    //     result.isExpired = currentTime > expiryTime;
    //     result.isMatured = currentTime >= maturityTime;
    // }

    /// @notice Return order current status information
    function getStatus(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex,
        uint256 releaseRatePerDay
    ) internal pure returns (Models.RuleResult memory result) {

        uint256 start = order.startTime;
        uint256 maturityTime = start + plan.duration;
        uint256 expiryTime = start + 365 days;

        // ===== 1️⃣ Frozen Status =====
        result.isFrozen = paused && order.createdAt < pauseTime;

        // ===== 2️⃣ claim =====

        uint256 reward = pendingReward(
            order,
            plan,
            currentTime,
            result.isFrozen ? pauseTime : 0,
            releaseRatePerDay
        );

        // 🔴 修复点：冻结订单不再走claim window
        if (result.isFrozen) {

            result.canClaim = order.status == 0 && reward > 0;

            // 冻结订单随时可以领取
            result.claimCountdown = 0;

        } else {

            bool inWindow = isInClaimWindow(
                order,
                plan,
                currentTime,
                false
            );

            result.canClaim = order.status == 0 && inWindow && reward > 0;

            if (result.canClaim) {

                result.claimCountdown = 0;

            } else {

                if(currentTime > expiryTime){

                    result.claimCountdown = type(uint256).max;

                } else {

                    uint256 elapsed =
                        currentTime > start
                        ? currentTime - start
                        : 0;

                    uint256 periods = elapsed / plan.claimInterval;

                    uint256 maxPeriods =
                        plan.duration / plan.claimInterval;

                    if(periods >= maxPeriods){

                        result.claimCountdown = type(uint256).max;

                    } else {

                        uint256 nextWindowStart =
                            start + (periods + 1) * plan.claimInterval;

                        result.claimCountdown =
                            nextWindowStart > currentTime
                            ? nextWindowStart - currentTime
                            : 0;
                    }
                }
            }
        }

        // ===== 3️⃣ unstake =====

        Models.UnstakeRule memory unstakeRule =
            _unstakeRule(order, plan, currentTime, paused, pauseTime);

        result.canUnstake = unstakeRule.canUnstake;
        result.unstakeCountdown = unstakeRule.unstakeCountdown;

        // ===== 4️⃣ restake =====

        result.canRestake =
            _restakeRule(order, plan, currentTime, paused, pauseTime, newStakeIndex);

        // ===== 5️⃣ 状态 =====

        result.isExpired = currentTime > expiryTime;
        result.isMatured = currentTime >= maturityTime;
    }

}
