// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

contract Payback is Initializable, OwnableUpgradeable, UUPSUpgradeable{

    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
        onlyOwner
    {}

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    
}
