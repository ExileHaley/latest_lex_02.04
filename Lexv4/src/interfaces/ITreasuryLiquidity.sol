// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ITreasuryLiquidity{
    function issueAward(address user, uint256 reward) external;
    function swapTokenToUsdt(address to, uint256 usdtAmount) external;
    function addLiquidity(uint256 amountUSDT) external;
}