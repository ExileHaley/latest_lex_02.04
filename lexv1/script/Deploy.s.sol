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
        recipient = 0xC29f694A76B5Ef37709DB65c6A205B2105132021;
        initialCode = 0x07aEEec50D35C88e3BD9d9666a563ac799d5036a;
        admin = 0x7786F26d88dfC4fa17e7722d8D9cbdA4be54aC55;
    }

    function run() public {
        
        vm.startBroadcast();
        vm.txGasPrice(50_000_0000); // 0.05 gwei
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