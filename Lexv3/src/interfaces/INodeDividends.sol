// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Models} from "../libraries/Models.sol";

interface INodeDividends{
    function updateFarm(Models.Source source, uint256 amount) external;
}