// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILex {
    function specialWithdraw(uint256 amount) external;
    function getHighestReserve() external view returns(uint256);
}