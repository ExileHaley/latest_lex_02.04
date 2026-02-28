// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import "./const.sol";

interface IReferrals {
    function referral(address parent, address user) external;
    function rootAddr() external view returns(address);
    
}

contract Router is Ownable, ReentrancyGuard{

    uint256 public constant MIN_STAKE_AMOUNT = 2 ether;
    address public treasury;
    address public queue;
    address public referrals;
    mapping(uint256 => uint256) public maxValueOfStakeIndex;

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
        
    }

    function restake(uint256 orderIndex, uint8 newStakeIndex) external nonReentrant{}

    function claim(uint256 orderIndex) external nonReentrant{}

    function getStatus(uint256 orderIndex) external view returns(bool){}
}