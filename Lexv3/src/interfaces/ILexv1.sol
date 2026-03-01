// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


interface ILexv1{
    function getParent(address user) external view returns(address);
}