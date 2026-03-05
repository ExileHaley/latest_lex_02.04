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
    ) internal pure returns(bool) {
        if(frozen){
            // 冻结释放的收益随时可领取
            return true;
        }

        // 非冻结订单仍然受原窗口限制
        if(currentTime < order.startTime + plan.claimInterval) return false;
        if(currentTime > order.startTime + plan.claimInterval + 1 days) return false;

        return true;
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
    function validateClaim(
        Models.Order memory order,
        Models.StakePlan memory plan,
        bool frozen,
        uint256 currentTime
    ) internal pure {

        require(order.status == 0, "Order inactive");

        // 12个月上限
        require(
            currentTime <= order.startTime + 365 days,
            "Order expired"
        );

        // 冻结订单：随时可领取释放收益
        if (frozen) {
            return;
        }

        require(
                isInClaimWindow(order, plan, currentTime, false),
                "Not in claim window"
        );

}

    /// @notice 验证订单是否可赎回（统一前提规则）
    /// @param order 订单信息
    /// @param plan 对应质押计划
    /// @param currentTime 当前时间戳
    /// @param isFrozenOld 是否为冻结前订单
    function validateUnstakePre(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool isFrozenOld
    ) internal pure {

        require(order.status == 0, "Order inactive");

        // 冻结前订单禁止赎回
        require(!isFrozenOld, "Frozen pre-order cannot unstake");

        uint256 maturityTime = order.startTime + plan.duration;
        uint256 expiryTime = order.startTime + 365 days;

        // 必须到期
        require(currentTime >= maturityTime, "Order not matured");

        // 超过一年订单作废
        require(currentTime <= expiryTime, "Order expired");
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


    /// @notice 返回订单当前状态信息
    function getStatus(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) 
        internal 
        pure 
        returns (Models.RuleResult memory result) 
    {
        // 冻结前订单
        result.isFrozen = isFrozenOldOrder(order, pauseTime, paused);

        // 1️⃣ 可领取收益倒计时
        if(result.isFrozen){
            result.claimCountdown = type(uint256).max;
        } else if(order.freezeStart != 0){
            result.claimCountdown = 0;
        } else {
            uint256 claimWindowStart = order.startTime + plan.claimInterval;
            uint256 claimWindowEnd   = claimWindowStart + 1 days;

            if(currentTime < claimWindowStart){
                result.claimCountdown = claimWindowStart - currentTime;
            } else if(currentTime <= claimWindowEnd){
                result.claimCountdown = 0;
            } else {
                result.claimCountdown = type(uint256).max;
            }
        }

        // 2️⃣ 赎回倒计时
        uint256 maturityTime = order.startTime + plan.duration;
        uint256 expiryTime   = order.startTime + 365 days;

        if(result.isFrozen){
            result.unstakeCountdown = type(uint256).max;
        } else if(currentTime < maturityTime){
            result.unstakeCountdown = maturityTime - currentTime;
        } else if(currentTime <= expiryTime){
            result.unstakeCountdown = 0;
        } else {
            result.unstakeCountdown = type(uint256).max;
        }

        // 3️⃣ 操作权限
        result.canClaim    = (result.claimCountdown == 0 && order.status == 0);
        result.canUnstake  = (result.unstakeCountdown == 0 && order.status == 0);
        result.canRestake  = result.canUnstake && newStakeIndex >= order.stakeIndex + (order.stakeIndex == 0 ? 1 : 0);

        // 4️⃣ 订单状态
        result.isExpired   = currentTime > order.startTime + 365 days;
        result.isMatured   = currentTime >= maturityTime;
    }

    /// @notice 验证再质押前置条件
    function validateRestakePre(
        Models.Order memory order,
        Models.StakePlan memory plan,
        uint256 currentTime,
        bool paused,
        uint32 pauseTime,
        uint8 newStakeIndex
    ) internal pure {
        Models.RuleResult memory result = getStatus(order, plan, currentTime, paused, pauseTime, newStakeIndex);

        require(result.canRestake, "Cannot restake");
        require(result.canUnstake, "Order not matured or expired");
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
        Models.RuleResult memory result = getStatus(order, plan, currentTime, paused, pauseTime, newStakeIndex);

        if(!result.canClaim || !result.canRestake || result.claimCountdown == type(uint256).max){
            return 0;
        }

        // 赎回奖励 = 可领取的收益（考虑冻结释放）
        reward = pendingReward(order, plan, currentTime, 0, releaseRatePerDay);
    }

}
