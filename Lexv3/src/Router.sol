// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import { Models } from "./libraries/Models.sol";

import { TreasuryRules } from "./libraries/TreasuryRules.sol";

import {IReferrals} from "./interfaces/IReferrals.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IQueue} from "./interfaces/IQueue.sol";

contract Router is Ownable, ReentrancyGuard{
    address public constant USDT =
        0x55d398326f99059fF775485246999027B3197955;
    uint256 public constant MIN_STAKE_AMOUNT = 2 ether;
    address public treasury;
    address public queue;
    address public referrals;
    mapping(uint256 => uint256) public maxValueOfStakeIndex;
    mapping(address => bool) public alreadyExistsUser;

    constructor(
        address _treasury, 
        address _queue, 
        address _referrals
    )Ownable(msg.sender){
        treasury = _treasury;
        queue = _queue;
        referrals = _referrals;
        maxValueOfStakeIndex[0] = 100e18;
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

    function referral(address parent) external nonReentrant{
        require(parent != address(0), "Zero address.");
        require(parent != msg.sender, "Error parent address.");
        IReferrals(referrals).referral(parent, msg.sender);
    }

    //验证邀请码是否有效
    function stake(uint256 amount, uint8 stakeIndex) external nonReentrant{
        require(stakeIndex < 4, "ERROR_STAKE_INDEX.");
        uint256 maxLimit = maxValueOfStakeIndex[stakeIndex];
        if(maxLimit > 0) require(maxLimit >= amount, "ERROR_AMOUNT.");
        if(stakeIndex == 0) require(!alreadyExistsUser[msg.sender], "DISALLOWED_ORDER_TYPE.");
        TransferHelper.safeTransferFrom(USDT, msg.sender, queue, amount);
        IQueue(queue).stake(msg.sender, amount, stakeIndex);
        alreadyExistsUser[msg.sender] = true;
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


    function getOrderStatus(address user, uint256 orderIndex) 
        external 
        view 
        returns(
            uint256 truthAward,
            uint256 claimCountdown,
            uint256 unstakeCountdown,
            bool    canClaim,
            bool    canUnstake,
            bool    canRestake
        )
    {
        truthAward = ITreasury(treasury).calculateReward(user, orderIndex);
        (claimCountdown, unstakeCountdown) = ITreasury(treasury).getCountdown(user, orderIndex);
        (canClaim, canUnstake, canRestake) = ITreasury(treasury).getStatus(user, orderIndex);
    }

    function getUserOrders(address user) external view returns(TreasuryRules.Order[] memory) {
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
}