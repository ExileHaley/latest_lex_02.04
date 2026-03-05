// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
//导入要使用的接口
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
//导入要使用的数据结构
import {Models} from "../src/libraries/Models.sol";
//导入要部署的合约
import {Treasury} from "../src/Treasury.sol";
import {TreasuryLiquidity} from "../src/TreasuryLiquidity.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Queue} from "../src/Queue.sol";
import {Referrals} from "../src/Referrals.sol";
import {Router} from "../src/Router.sol";
//导入要部署的代币
import {Lex} from "../src/token/Lex.sol";
import {Leo} from "../src/token/Leo.sol";
import {Tether} from "../src/mock/Tether.sol";


contract RouterTest is Test{
    address initialRecipient;
    address wallet;
    address nodeV1;
    address admin;
    address rootAddr;

    address owner;

    Tether public USDT;
    Lex public lex;
    Leo public leo;
    
    Treasury public treasury;
    TreasuryLiquidity public treasuryLiquidity;
    NodeDividends public nodeDividends;
    Queue public queue;
    Referrals public referrals;
    Router public router;

    address uniswapV2Router;
    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);

        uniswapV2Router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        nodeV1 = address(0x285Ca769Ab57CBB623513921C9a9B3a8fd8F936A);
        rootAddr = address(0x19Cf31C1DA6b2c8cD9fD0b8AA4466433196BDBe6);

        owner = address(1);
        initialRecipient = address(2);
        wallet = address(3);
        admin = address(4);

        
    }
}