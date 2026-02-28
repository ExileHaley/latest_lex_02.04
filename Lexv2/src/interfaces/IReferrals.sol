// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IReferrals {

    function referral(address parent, address user) external;
    function rootAddr() external view returns(address);
    
}