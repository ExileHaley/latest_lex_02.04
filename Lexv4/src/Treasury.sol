// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Models } from "./libraries/Models.sol";
import { TreasuryRules } from "./libraries/TreasuryRules.sol";
import { ITreasury } from "./interfaces/ITreasury.sol";
import { ITreasuryLiquidity } from "./interfaces/ITreasuryLiquidity.sol";

contract Treasury is Initializable, OwnableUpgradeable, UUPSUpgradeable, ITreasury{
    mapping(uint8 => Models.StakePlan) public stakePlans;
    mapping(address => Models.Order[]) userOrders;

    address wallet;
    address queue;
    ITreasuryLiquidity treasuryLiquidity;

    bool    public paused;
    uint32  public pauseTime;
    uint32  pauseRound;
    uint64  public releaseRatePerDay; // 1e15 = 0.1%

    function _authorizeUpgrade(address newImplementation)internal view override onlyOwner{}

    function initialize(address _wallet) public initializer {
        __Ownable_init(_msgSender());
        wallet = _wallet;
        releaseRatePerDay = 1e15; // 冻结释放 0.1%
        uint256 day = 1 days;

        stakePlans[0] = Models.StakePlan({
            duration: 1 days,
            claimInterval: 1 days,
            rate: uint64(3e15 / day)
        });
        stakePlans[1] = Models.StakePlan({
            duration: 15 days,
            claimInterval: 15 days,
            rate: uint64(6e15 / day)
        });
        stakePlans[2] = Models.StakePlan({
            duration: 30 days,
            claimInterval: 15 days,
            rate: uint64(12e15 / day)
        });
        stakePlans[3] = Models.StakePlan({
            duration: 90 days,
            claimInterval: 10 days,
            rate: uint64(13e15 / day)
        });
    }

    modifier onlyQueue() {
        require(queue == msg.sender, "Not permit.");
        _;
    }

    function setAddrConfig(
        address _queue,
        ITreasuryLiquidity _treasuryLiquidity
    ) external onlyOwner{
        queue = _queue;
        treasuryLiquidity = _treasuryLiquidity;
    }

    function pause() external onlyQueue{
        require(!paused, "Already paused");
        paused = true;
        pauseTime = uint32(block.timestamp);
        pauseRound += 1;
    }

    function resume() external  onlyQueue{
        require(paused, "Not paused");
        paused = false;
    }

    function stake(address user, uint256 amount, uint8 stakeIndex) external onlyQueue{
        ITreasuryLiquidity(treasuryLiquidity).addLiquidity(amount);
        userOrders[user].push(_newOrder(amount, stakeIndex));
    }

    /// @notice 领取收益
    function claim(address user, uint256 orderIndex) external onlyQueue {
        Models.Order storage order = userOrders[user][orderIndex];
        Models.StakePlan memory plan = stakePlans[order.stakeIndex];
        // 冻结处理
        TreasuryRules.applyPause(order, plan, pauseTime, pauseRound, paused, block.timestamp);
        bool frozen = TreasuryRules.isFrozenOldOrder(order, pauseTime, paused);
        // 校验是否可以领取
        TreasuryRules.validateClaim(order, plan, frozen, block.timestamp);
        // 计算奖励
        uint256 reward = TreasuryRules.pendingReward(order, plan, block.timestamp, frozen ? pauseTime : 0, releaseRatePerDay);
        require(reward > 0, "No reward.");
        // 标记已领取
        if (frozen) {
            order.frozenClaimed += uint128(reward);
        } else {
            order.claimed += uint128(reward);
        }
        // 分发奖励
        treasuryLiquidity.issueAward(user, reward);
    }

    
    function unstake(address user, uint256 orderIndex) external onlyQueue {
        Models.Order storage order = userOrders[user][orderIndex];
        Models.StakePlan memory plan = stakePlans[order.stakeIndex];

        TreasuryRules.isActive(order);
        // ===== 1️⃣ 处理冻结逻辑 =====
        TreasuryRules.applyPause(order, plan, pauseTime, pauseRound, paused, block.timestamp);
        // 冻结前订单
        bool isFrozenOld = TreasuryRules.isFrozenOldOrder(order, pauseTime, paused);
        // ===== 2️⃣ 赎回前置检查 =====
        TreasuryRules.validateUnstakePre(order, plan, block.timestamp, isFrozenOld);
        // ===== 3️⃣ 计算本金、固定手续费、逾期罚金 =====
        (uint256 payout, uint256 fixedFee, ) =
            TreasuryRules.calculateUnstakePrincipal(order, plan, block.timestamp);
        // ===== 4️⃣ 分发 =====
        if(payout > 0){
            treasuryLiquidity.swapTokenToUsdt(user, payout); // 本金发给用户
        }
        if(fixedFee > 0){
            treasuryLiquidity.swapTokenToUsdt(wallet, fixedFee); // 固定手续费发给 wallet
        }
        // 逾期罚金 overdueFee 不发放，直接扣掉
        // ===== 5️⃣ 更新订单状态 =====
        order.status = 1; // 已赎回
    }

    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external onlyQueue {
        Models.Order storage order = userOrders[user][orderIndex];
        Models.StakePlan memory plan = stakePlans[order.stakeIndex];

        // ===== 1️⃣ 检查订单是否活跃 =====
        TreasuryRules.isActive(order);
        // ===== 2️⃣ 处理冻结逻辑 =====
        TreasuryRules.applyPause(order, plan, pauseTime, pauseRound, paused, block.timestamp);
        // ===== 3️⃣ 校验前置条件 =====
        TreasuryRules.validateRestakePre(order, plan, block.timestamp, paused, pauseTime, newStakeIndex);
        // ===== 4️⃣ 计算可领取收益 =====
        uint256 reward = TreasuryRules.calculateRestakeReward(order, plan, block.timestamp, releaseRatePerDay, paused, pauseTime, newStakeIndex);

        // ===== 5️⃣ 分发收益 =====
        if(reward > 0){
            treasuryLiquidity.issueAward(user, reward); // 直接发给用户
        }

        // ===== 6️⃣ 标记旧订单为已结束 =====
        order.status = 1;

        // ===== 7️⃣ 创建新订单 =====
        userOrders[user].push(_newOrder(order.amount, newStakeIndex));
    }

    //*********************************utils func**************************************//
    /// @notice 检查和更新冻结状态
    // function _applyPause(address user, uint256 orderIndex) internal {
    //     if(!paused) return;

    //     Models.Order storage order = userOrders[user][orderIndex];
    //     Models.StakePlan memory plan = stakePlans[order.stakeIndex];
    //     // 只处理冻结前创建的订单
    //     if(order.createdAt >= pauseTime) return;

    //     // 如果已经冻结过，不重复冻结
    //     if(order.freezeStart != 0) return;

    //     // ===== 记录冻结时的未领取收益 =====
    //     // uint256 total = calculateNormal(user, orderIndex);
    //     uint256 total = TreasuryRules.calculateNormal(order, plan, block.timestamp);
    //     uint256 unclaimed = total > order.claimed
    //         ? total - order.claimed
    //         : 0;

    //     order.frozenReward = uint128(unclaimed);
    //     order.freezeStart = uint32(block.timestamp);
    //     order.freezeRound = pauseRound;
    // }

    /// @notice 组装新订单
    function _newOrder(uint256 amount, uint8 stakeIndex)
        internal
        view
        returns (Models.Order memory)
    {
        return Models.Order({
            amount: uint128(amount),
            claimed: 0,
            claimedPeriods: 0,
            startTime: uint32(block.timestamp),
            stakeIndex: stakeIndex,
            status: 0,
            createdAt: uint32(block.timestamp),
            frozenReward: 0,
            frozenClaimed: 0,
            freezeStart: 0,
            freezeRound: 0
        });
    }

    function getUserOrders(address user)external view returns (Models.Order[] memory){
        return userOrders[user];
    }

    function getOrderInfo(address user, uint256 orderIndex) external view returns(uint256 amount, uint8 stakeIndex){
        Models.Order memory order = userOrders[user][orderIndex];
        amount = order.amount;
        stakeIndex = order.stakeIndex;
    }

}