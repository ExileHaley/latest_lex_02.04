// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script,console} from "forge-std/Script.sol";
import {Recharge} from "../src/Recharge.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeScript is Script{
    Recharge public recharge;

    function setUp() public {
        recharge = Recharge(payable(0x194635920CDC435c560836dF5D9727bDb43242cb));
    }

    function run() public {
        vm.startBroadcast();
        vm.txGasPrice(90_000_0000); // 0.09 gwei

        Recharge rechargeV2Impl = new Recharge();
        bytes memory data= "";
        recharge.upgradeToAndCall(address(rechargeV2Impl), data);
        vm.stopBroadcast();
    }
}