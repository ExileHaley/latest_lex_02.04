// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Models } from "./Models.sol";

library TreasuryRules {

    /// @notice 计算正常状态下的订单理论累计收益
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

    /// @notice 冻结释放
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

    /// @notice 计算订单可领取收益（考虑冻结或已领取）
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

        // 收益只计算到 pauseTime
        uint256 total = calculateNormal(order, plan, currentTime, pauseTime);

        uint256 unclaimed =
            total > order.claimed
            ? total - order.claimed
            : 0;

        order.frozenReward = uint128(unclaimed);

        // 推荐使用 pauseTime
        order.freezeStart = pauseTime;

        order.freezeRound = pauseRound;
    }


    /// @notice 检查订单是否在可提取收益窗口
    /// @param frozen 是否冻结状态
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

        // 超过到期+24h不可领取
        if (currentTime > endTime + 1 days) {
            return false;
        }

        // 当前时间至少超过第一次可领取间隔
        if (currentTime < start + plan.claimInterval) {
            return false;
        }

        // 计算当前周期
        uint256 elapsed = currentTime - start;
        uint256 periods = elapsed / plan.claimInterval;
        uint256 maxPeriods = plan.duration / plan.claimInterval;
        if (periods > maxPeriods) periods = maxPeriods;

        // 当前周期是否已领取
        if (periods <= order.claimedPeriods) {
            return false;
        }

        // 当前时间是否在窗口（每周期允许领取24h）
        uint256 claimWindowStart = start + periods * plan.claimInterval;
        uint256 claimWindowEnd   = claimWindowStart + 1 days;
        return currentTime >= claimWindowStart && currentTime <= claimWindowEnd;
    }


    /// @notice 检查订单是否仍然活跃
    function isActive(Models.Order memory order) internal pure {
        require(order.status == 0, "Order inactive");
    }

    /// @notice 检查订单是否被冻结前的旧订单
    function isFrozenOldOrder(
        Models.Order memory order,
        uint32 pauseTime,
        bool paused
    ) internal pure returns(bool) {
        return paused && order.createdAt < pauseTime;
    }

    /// @notice 校验收益提取规则
    /// @notice 验证收益提取规则，完全复用 isInClaimWindow
    function validateClaim(
        Models.Order memory order,
        Models.StakePlan memory plan,
        bool frozen,
        uint256 currentTime
    ) internal pure {
        require(order.status == 0, "Order inactive");
        require(currentTime <= order.startTime + 365 days, "Order expired");

        // 冻结状态随时可领取
        if (frozen) return;

        // 普通订单调用统一 claim window
        require(isInClaimWindow(order, plan, currentTime, frozen), "Not in claim window");
    }

    //内部函数用于返回相关状态
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

    /// @notice 验证订单是否可赎回
    /// @param order 订单信息
    /// @param plan 对应质押计划
    /// @param currentTime 当前时间戳
    /// @param paused 是否为冻结前订单
    /// @param pauseTime 冻结时间
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


    //本金赎回手续费，假设当前订单总质押本金1000usdt
    //1.(claimed+frozenClaimed) * 90 /100，这个作为已经提取的本金，假设此时用户已提取总收益 = 100，那么此时本金逻辑上已经剩余100 - 90 = 910
    //2.固定手续费10%，1000*10/100 = 100，此时本金逻辑上剩余910 - 100 = 810
    //3.每超出24小时的罚金10%，假设目前已经是到期后25小时，到期后截止到期后24小时内只有固定手续费，多出来一个小时算罚金 1000 * 10 / 100 * 1 = 100
    //4.用户赎回本金到账：1000 - 90(已提取收益的90%) - 100(固定手续费) - 100(超过到期后24小时的罚金) = 710
    /// @notice 计算赎回本金和手续费（考虑已提取收益、固定手续费、逾期罚金）
    /// @param order 订单信息
    /// @param plan 对应质押计划
    /// @param currentTime 当前时间戳
    /// @return payout 用户实际到账本金
    /// @return fixedFee 固定手续费（打给 wallet）
    /// @return overdueFee 逾期罚金
    function calculateUnstakePrincipal(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime
    ) internal pure returns(uint256 payout, uint256 fixedFee, uint256 overdueFee) {

        uint256 principal = order.amount;

        // ===== 1️⃣ 已提取收益占用本金 =====
        uint256 claimedPrincipal = (order.claimed + order.frozenClaimed) * 90 / 100;
        require(claimedPrincipal <= principal, "Claimed exceeds principal");

        uint256 remaining = principal - claimedPrincipal;

        // ===== 2️⃣ 固定手续费 10% =====
        fixedFee = principal * 10 / 100;
        if(fixedFee > remaining){
            fixedFee = remaining;
        }
        remaining -= fixedFee;

        // ===== 3️⃣ 逾期罚金 =====
        uint256 maturityTime = order.startTime + plan.duration;
        uint256 gracePeriodEnd = maturityTime + 1 days; // 到期后24小时内只有固定手续费

        overdueFee = 0;
        if(currentTime > gracePeriodEnd){
            uint256 overdueDays = (currentTime - gracePeriodEnd) / 1 days;
            overdueFee = principal * 10 / 100 * overdueDays;
            if(overdueFee > remaining){
                overdueFee = remaining;
            }
            remaining -= overdueFee;
        }

        // ===== 4️⃣ 剩余本金 =====
        payout = remaining;
    }


    /// @notice 验证再质押前置条件
    function _restakeRule(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) internal pure returns (bool canRestake) {
        // 先判断赎回规则
        Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);

        // 冻结订单或未到期无法再质押
        if(!unstakeRule.canUnstake) {
            return false;
        }

        // 新的 stakeIndex 必须大于旧的 stakeIndex（首次 stakeIndex=0 特殊处理）
        if(newStakeIndex < order.stakeIndex + (order.stakeIndex == 0 ? 1 : 0)){
            return false;
        }

        return true;
    }

    // validateRestakePre 调用 view 函数
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

        // 再质押必须订单可赎回
        Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);
        require(unstakeRule.canUnstake, "Order not matured or expired");
    }

    /// @notice 计算再质押可领取收益
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

        // 赎回奖励 = 可领取的收益（考虑冻结释放）
        reward = pendingReward(order, plan, currentTime, 0, releaseRatePerDay);
    }   

    /// @notice 返回订单当前状态信息（完全复用核心规则函数）
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

        // ===== 1️⃣ 冻结状态 =====
        result.isFrozen = paused && order.createdAt < pauseTime;

        // ===== 2️⃣ claim =====
        bool inWindow = isInClaimWindow(order, plan, currentTime, result.isFrozen);
        uint256 reward = pendingReward(
            order,
            plan,
            currentTime,
            result.isFrozen ? pauseTime : 0,
            releaseRatePerDay
        );
        result.canClaim = order.status == 0 && inWindow && reward > 0;
        result.claimCountdown = result.canClaim ? 0 : type(uint256).max;

        // ===== 3️⃣ unstake =====
        Models.UnstakeRule memory unstakeRule = _unstakeRule(order, plan, currentTime, paused, pauseTime);
        result.canUnstake = unstakeRule.canUnstake;
        result.unstakeCountdown = unstakeRule.unstakeCountdown;

        // ===== 4️⃣ restake =====
        result.canRestake = _restakeRule(order, plan, currentTime, paused, pauseTime, newStakeIndex);

        // ===== 5️⃣ 状态 =====
        result.isExpired = currentTime > expiryTime;
        result.isMatured = currentTime >= maturityTime;
    }

}
