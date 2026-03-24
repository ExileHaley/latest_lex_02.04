// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// //导入要使用的接口
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
// import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
// //导入要使用的数据结构
// import {Models} from "../src/libraries/Models.sol";
// //导入要部署的合约
// import {Treasury} from "../src/Treasury.sol";
// import {TreasuryLiquidity} from "../src/TreasuryLiquidity.sol";
// import {NodeDividends} from "../src/NodeDividends.sol";
// import {Payback} from "../src/Payback.sol";
import {Queue} from "../src/Queue.sol";
// import {Referrals} from "../src/Referrals.sol";
// import {Router} from "../src/Router.sol";
// //导入要部署的代币
// import {Lex} from "../src/token/Lex.sol";
// import {Leo} from "../src/token/Leo.sol";
// import {Tether} from "../src/mock/Tether.sol";

contract QueueTest is Test{
    Queue public queue;

    address public admin;
    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);
        queue = Queue(payable(0x4DFdF40117039A5caeeD9A9a13eF1453e2697314));
        admin = queue.admin();
    }

    function test_fomo() public {
        vm.startPrank(admin);
        queue.drawFomoRewards();
        vm.stopPrank();
    }
}