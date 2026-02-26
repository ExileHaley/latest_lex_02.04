// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./const.sol";

contract NodeDividends is Initializable, OwnableUpgradeable, UUPSUpgradeable{

    struct User{
        uint256 multiple;
    }

    address lex;
    address treasury;

    mapping(uint8 => uint256) public perStakingAward; //每1u可以获得多少奖励
    uint256 totalStaking; //全网节点总额u

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    //三种方式，手续费分红、盈利税分红、充值分红
    // function updateFarm(uint8 mark, uint256 amount) external{}

    
}