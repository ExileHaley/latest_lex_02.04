// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script,console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TreasuryScript is Script {
    Treasury public treasury;
    address  public wallet;

    function setUp() public {
        wallet = 0x10b6d39D35fbEE7BB6d0088B0CdFAe8519052FA1;
    }

    function run() public {
        
        vm.startBroadcast();
        vm.txGasPrice(90_000_0000); // 0.05 gwei

        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(treasuryImpl.initialize,(wallet))
        );
        treasury = Treasury(payable(address(treasuryProxy)));

        vm.stopBroadcast();
        console.log("treasury deployed at:",address(treasury));
    }
}