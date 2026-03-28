// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
//导入要部署的代币
import {Lex} from "../src/token/Lex.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Leo} from "../src/token/Leo.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Payback} from "../src/Payback.sol";

contract LexTest is Test{
    Lex public lex;
    address public USDT;
    address public owner;
    address public user;
    address public router;
    NodeDividends public nodeDividends;
    Payback public payback;

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);
        lex = Lex(0x961BDb47b3E368e5B873f99a374d8DeB88b50Ed2);

        USDT = address(0x2443dd5aBb73965b5d7C39990bAcc164C11C6229);

        owner = address(0xc263D128DdbA54405edDD34C059aD6F342a42a05);

        router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        nodeDividends = NodeDividends(payable(0xd71241Bc207CC79330690e663D0c23ED143ba2Ed));
        payback = Payback(payable(0xC17EE2f57C03CD495beb2b8972f573Fb5B2235dD));
        user = address(0xd23bE199Ba3560F36c1311C0115AA48A5dd57CC8);
    }

    function _exchange_utils(address addr, address fromToken, address toToken, uint256 amountIn) internal{
        vm.startPrank(addr);
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        IERC20(fromToken).approve(router, amountIn);

        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 
            0, 
            path, 
            addr, 
            block.timestamp
        );
        vm.stopPrank();
    }

    function test_sell() public {
        console.log("Before sell usdt balance of user", IERC20(USDT).balanceOf(user));
        _exchange_utils(user, address(lex), USDT, 100e18);
        console.log("After sell usdt balance of user", IERC20(USDT).balanceOf(user));
    }

    // function test_profit_fee() public {
    //     address user1 = address(10);
    //     uint256 amount1 = 100e18;
    //     deal(USDT, user1, amount1);
    //     _exchange_utils(user1, USDT, address(lex), amount1);


    //     address user2 = address(11);
    //     uint256 amount2 = 10000e18;
    //     deal(USDT, user2, amount2);
    //     _exchange_utils(user2, USDT, address(lex), amount2);


    //     uint256 balanceLex = lex.balanceOf(user1);
    //     _exchange_utils(user1, address(lex), USDT, balanceLex);
    // }
}
