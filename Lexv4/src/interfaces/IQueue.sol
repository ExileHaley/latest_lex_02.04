// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Models} from "../libraries/Models.sol";

interface IQueue {
    function getUserQueueIds(address user) external view returns (uint256[] memory);
    function getPendingOrder(uint256 queueId)
        external
        view
        returns (
            address user,
            uint256 amount,
            uint256 orderIndex,
            uint8 stakeIndex,
            uint256 createdAt,
            uint8 status
        );

    function getQueueRange()
        external
        view
        returns (uint256 head, uint256 tail);

    function getTodayQuota()
        external
        view
        returns (
            uint256 stakeUsed,
            uint256 stakeRemaining,
            uint256 unstakeUsed,
            uint256 unstakeRemaining
        );

    function getCurrentRound()
        external
        view
        returns (
            uint256 roundId,
            address[21] memory lastQualified,
            uint256 count,
            uint256 poolBalance
        );
    function circuitBreaker() external view returns(bool);
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function unstake(address user, uint256 orderIndex) external;
    function cancelQueue(address user, uint256 queueId) external;
    function claim(address user, uint256 orderIndex) external;
    function restake(
        address user,
        uint256 orderIndex,
        uint256 newStakeIndex
    ) external;
    function drawFomoRewards() external;

    function getFomoAwardsInfo(address user) external view returns(Models.FomoAwards[] memory);
    function userQueueAmount(address user) external view returns(uint256);
}