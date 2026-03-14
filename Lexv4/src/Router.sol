// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import { Models } from "./libraries/Models.sol";

import {IReferrals} from "./interfaces/IReferrals.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IQueue} from "./interfaces/IQueue.sol";
import {TreasuryRules} from "./libraries/TreasuryRules.sol";


contract Router is Ownable, ReentrancyGuard{
    address public USDT;
    uint256 public constant MIN_STAKE_AMOUNT = 2 ether;
    address public treasury;
    address public queue;
    address public referrals;
    mapping(uint256 => uint256) public maxValueOfStakeIndex;
    mapping(address => bool) public alreadyExistsUser;

    uint256 public stakingAmountLimit;

    constructor(
        address _treasury, 
        address _queue, 
        address _referrals,
        address _USDT
    )Ownable(msg.sender){
        treasury = _treasury;
        queue = _queue;
        referrals = _referrals;
        USDT = _USDT;
        maxValueOfStakeIndex[0] = 100e18;
        stakingAmountLimit = 10000e18;
    }

    function setConfig(
        address _treasury, 
        address _queue, 
        address _referrals
    )external onlyOwner{
        treasury = _treasury;
        queue = _queue;
        referrals = _referrals;
    }

    function setAmountLimit(uint256 amount) external onlyOwner{
        require(amount * 1e18 >= 100e18, "ERROR_AMOUNT_LIMIT.");
        stakingAmountLimit = amount * 1e18;
    }

    function referral(address parent) external nonReentrant{
        require(parent != address(0), "Zero address.");
        require(parent != msg.sender, "Error parent address.");
        IReferrals(referrals).referral(parent, msg.sender);
    }


    function stake(uint256 amount, uint8 stakeIndex) external nonReentrant{
        require(stakingAmountLimit >= amount, "ERROR_STAKING_AMOUNT.");
        require(stakeIndex < 4, "ERROR_STAKE_INDEX.");
        uint256 maxLimit = maxValueOfStakeIndex[stakeIndex];
        if(maxLimit > 0) require(maxLimit >= amount, "ERROR_AMOUNT.");

        if(stakeIndex == 0) {
            require(!alreadyExistsUser[msg.sender], "DISALLOWED_ORDER_TYPE.");
            alreadyExistsUser[msg.sender] = true;
        }
        TransferHelper.safeTransferFrom(USDT, msg.sender, queue, amount);
        IQueue(queue).stake(msg.sender, amount, stakeIndex);
    }

    function unstake(uint256 orderIndex) external nonReentrant{
        IQueue(queue).unstake(msg.sender, orderIndex);
    }

    function restake(uint256 orderIndex, uint8 newStakeIndex) external nonReentrant{
        IQueue(queue).restake(msg.sender, orderIndex, newStakeIndex);
    }

    function cancelQueue(uint256 queueOrderId) external nonReentrant{
        IQueue(queue).cancelQueue(msg.sender, queueOrderId);
    }

    function claim(uint256 orderIndex) external nonReentrant{
        IQueue(queue).claim(msg.sender, orderIndex);
    }


    function getUserOrders(address user) external view returns(Models.Order[] memory) {
        return ITreasury(treasury).getUserOrders(user);
    }

    function getUserQueueIds(address user) external view returns(uint256[] memory){
        return IQueue(queue).getUserQueueIds(user);
    }

    function getQueueInfo(uint256 queueId) 
        external 
        view 
        returns(
            address user,
            uint256 amount,
            uint256 orderIndex,
            uint8 stakeIndex,
            uint256 createdAt,
            bool isRestake,
            uint8 status
        )
    {
        (user, amount, orderIndex, stakeIndex, createdAt, isRestake, status) = 
            IQueue(queue).getPendingOrder(queueId);
    }

    function getCurrentQuota() 
        external 
        view 
        returns(
            uint256 stakeUsed,
            uint256 stakeRemaining,
            uint256 unstakeUsed,
            uint256 unstakeRemaining
        )
    {
        (stakeUsed, stakeRemaining, unstakeUsed, unstakeRemaining) = IQueue(queue).getTodayQuota();
    }

    function getFomoInfo() 
        external 
        view 
        returns(
            uint256 roundId,
            address[21] memory lastQualified,
            uint256 count,
            uint256 poolBalance
        )
    {
        (roundId, lastQualified, count, poolBalance) = IQueue(queue).getCurrentRound();
    }

    function getDirectReferralInfo(address user) 
        external 
        view 
    returns(Models.DirectReferral[] memory){
        return IReferrals(referrals).getDirectReferralInfo(user);
    }
    
    function rootAddr() external view returns(address){
        return IReferrals(referrals).rootAddr();
    }

    function getReferralInfo(address user) 
        external 
        view 
        returns(
            address parent,
            Models.LevelType level,
            uint16 referralNum,
            uint256 totalStaked,
            uint256 performance
        )
    {
        (parent, level, referralNum, totalStaked, performance) = IReferrals(referrals).referralInfo(user);
    }

    function verifyReferralCode(address user) external view returns(bool){
        (,,,uint256 totalStaked,) = IReferrals(referrals).referralInfo(user);
        return totalStaked > 0;
    }

    function getOrderStatus(address user, uint256 orderIndex) 
        external 
        view 
        returns(
            uint256 truthAward,
            Models.RuleResult memory result
        )
    {

        Models.Order memory order = ITreasury(treasury).getUserOrders(user)[orderIndex];


        (uint32 duration, uint32 claimInterval, uint32 window, uint64 rate) = ITreasury(treasury).stakePlans(order.stakeIndex);
        Models.StakePlan memory plan = Models.StakePlan({
            duration: duration,
            claimInterval: claimInterval,
            window: window,
            rate: rate
        });


        bool paused = ITreasury(treasury).paused();
        uint32 pauseTime = ITreasury(treasury).pauseTime();
        uint64 releaseRatePerDay = ITreasury(treasury).releaseRatePerDay();

        truthAward = TreasuryRules.pendingReward(order, plan, block.timestamp, pauseTime, releaseRatePerDay);

        uint8 newStakeIndex = uint8(order.stakeIndex + 1);
        result = TreasuryRules.getStatus(order, plan, block.timestamp, paused, pauseTime, newStakeIndex, releaseRatePerDay);
    }

    function getQueueRange() external view returns(uint256 head, uint256 tail){
        (head, tail) = IQueue(queue).getQueueRange();
    }
}