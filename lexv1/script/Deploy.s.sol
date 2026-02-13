// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script,console} from "forge-std/Script.sol";
import {Recharge} from "../src/Recharge.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    Recharge public recharge;
    address  public recipient;
    address  public initialCode;
    address  public admin;

    function setUp() public {
        recipient = 0x9CafBd03E64341789231E430c99aaa902a390f60;
        initialCode = 0x07aEEec50D35C88e3BD9d9666a563ac799d5036a;
        admin = 0x10b6d39D35fbEE7BB6d0088B0CdFAe8519052FA1;
    }

    function run() public {
        
        vm.startBroadcast();
        vm.txGasPrice(90_000_0000); // 0.05 gwei
        Recharge rechargeImpl = new Recharge();
        ERC1967Proxy rechargeProxy = new ERC1967Proxy(
            address(rechargeImpl),
            abi.encodeCall(rechargeImpl.initialize,(admin, recipient, initialCode))
        );
        recharge = Recharge(payable(address(rechargeProxy)));

        assert(recharge.admin() == admin);
        assert(recharge.initialCode() == initialCode);
        assert(recharge.recipient() == recipient);
        vm.stopBroadcast();
        console.log("recharge deployed at:",address(recharge));
    }
}