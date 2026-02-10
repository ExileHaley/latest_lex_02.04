// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Types } from "./libraries/Types.sol";

contract FarmReferral is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    using EnumerableSet for EnumerableSet.AddressSet;
    mapping(address => EnumerableSet.AddressSet) private directReferralAddrSets;
    EnumerableSet.AddressSet private levelAddrSets;
    uint16[8] public percentsForAward;
    address public rootAddr;
    address public queue;
    address public farmCore;
    address public lexv1;

    struct Referral {
        address inviter;        // 20 bytes
        Types.Level level;      // 1 byte (uint8 enum)
        bool valid;             // 1 byte
        uint16 referralNum;     // 2 bytes
        uint256 performance;    // 32 bytes
    }


    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _rootAddr,
        address _lexv1
    ) public initializer {
        __Ownable_init(_msgSender());
        rootAddr = _rootAddr;
        lexv1 = _lexv1;
        percentsForAward = [5, 5, 10, 15, 20, 25, 28, 30];
    }

    function setAddrConfig(address _queue, address _farmCore) external onlyOwner{}

    function referral(address inviter) external {}

    function batchMigrateReferral(address[] memory users) external {}

    function processStakeInfo(address user, uint256 amount) external {}
    
    function processUnstakeInfo(address user, uint256 amount) external {}

    function processClaimInfo(address user, uint256 amount) external {}


}