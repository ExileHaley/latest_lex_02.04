// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IReferrals {
    function referral(address parent, address user) external;
    function rootAddr() external view returns(address);
    function processStakeInfo(address user, uint256 amount) external;
    function processUnstakeInfo(address user, uint256 amount) external;
}