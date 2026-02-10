// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract FarmCore is Initializable, OwnableUpgradeable, UUPSUpgradeable{

    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    struct User{
        uint256 stakingUsdt;

    }
    mapping(address => User) public userInfo;
    address lex;

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
    ) public initializer {
        __Ownable_init(_msgSender());
    }
}