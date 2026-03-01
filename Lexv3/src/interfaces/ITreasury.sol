/// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {TreasuryRules} from "../libraries/TreasuryRules.sol";

interface ITreasury {
    function pause() external;
    function resume() external;
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function claim(address user, uint256 orderIndex) external;
    function unstake(address user, uint256 index) external;
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external;
    function calculateReward(address user, uint256 orderIndex)external view returns (uint256);
    function getCountdown(address user, uint256 orderIndex) external view returns(uint256 claimCountdown, uint256 unstakeCountdown);
    function getStatus(address user, uint256 orderIndex) external view returns(bool canClaim, bool canUnstake, bool canRestake);
    function getUserOrders(address user)external view returns (TreasuryRules.Order[] memory);
    function getOrderInfo(address user, uint256 orderIndex) external view returns(uint256 amount, uint8 stakeIndex);
}