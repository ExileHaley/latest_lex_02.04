// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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