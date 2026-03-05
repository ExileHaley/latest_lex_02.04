// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Models} from "../libraries/Models.sol";

interface ITreasury {
    function pause() external;
    function resume() external;
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function claim(address user, uint256 orderIndex) external;
    function unstake(address user, uint256 index) external;
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external;

    function getUserOrders(address user)external view returns (Models.Order[] memory);
    function getOrderInfo(address user, uint256 orderIndex) external view returns(uint256 amount, uint8 stakeIndex);
    
    function paused() external view returns(bool);
    function pauseTime() external view returns(uint32);
    function releaseRatePerDay() external view returns(uint64);
    function stakePlans(uint8 stakeIndex) 
        external 
        view 
        returns(
            uint32 duration,
            uint32 claimInterval,
            uint64 rate
        );
}