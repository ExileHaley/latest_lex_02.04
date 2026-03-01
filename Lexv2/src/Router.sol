// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import { Types } from "./libraries/Types.sol";
import "./const.sol";

interface IReferrals {
    function referral(address parent, address user) external;
    function rootAddr() external view returns(address); 
}

interface IQueue {
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function unstake(address user, uint256 orderIndex) external;
    function restake(
        address user,
        uint256 orderIndex,
        uint256 newStakeIndex
    ) external;
    function cancelQueue(address user, uint256 queueId) external;
    function claim(address user, uint256 orderIndex) external;
}

contract Router is Ownable, ReentrancyGuard{

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

}

// 应该还要实现数据或者状态查询函数
// Treasury:
// 1.查询用户的订单信息;
// 2.查询订单收益
// 3.查询订单收益提现时间窗口以及倒计时
// 4.查询赎回时间窗口以及倒计时
// 5.查询重新质押的时间窗口
// Queue:
// 1.当前可用的质押额度
// 2.当前用户排队的订单
// 3.当前可用的赎回额度
// 4.当前系统是否熔断
// Referrals:
// 1.查询用户的邀请信息，当前用户的邀请人地址、当前用户的级别、当前用户伞下的邀请人数，当前用户伞下总业绩
// 2.查询首码
// 3.查询直推地址的信息

