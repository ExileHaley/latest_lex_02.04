// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ITreasury {
    function pause() external;
    function resume() external;
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function unstake(address user, uint256 index) external;
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external;
    function claim(address user, uint256 orderIndex) external;
    function getOrderAmount(address user, uint256 orderIndex) external view returns(uint256);
}
