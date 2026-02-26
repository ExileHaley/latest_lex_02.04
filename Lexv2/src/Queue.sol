// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
contract Queue is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard{
    
    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }
    
    
}