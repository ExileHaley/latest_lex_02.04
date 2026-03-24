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
        lex = Lex(0x26a76CcA2f992F5F467184B437dCBb27591675B1);
        USDT = address(0x7816C568448A25B75197D106E2e4DBC0FD9fa3C8);
        owner = address(0xc263D128DdbA54405edDD34C059aD6F342a42a05);
        router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        nodeDividends = NodeDividends(payable(0xA747cE2773193a951Dc8A773d4960BBf2cFA99cB));
        payback = Payback(payable(0xD6EdA3A1472a03137Cb6C4DEd3Cd84e62AdFFa27));
        user = address(1);
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

    

    function _switch_sell(bool _openSell) internal{
        vm.startPrank(owner);
        lex.switchSell(_openSell);
        vm.stopPrank();
    }

    function _switch_buy(bool _openBuy) internal{
        vm.startPrank(owner);
        lex.switchBuy(_openBuy);
        vm.stopPrank();
    }

    function test_sell() public {
        uint256 amountIn = 100e18;
        deal(address(lex), user, amountIn);

        // console.log("NodeDividends addr`s liquidity:", nodeDividends.treasuryLiquidity());
        // console.log("NodeDividends addr`s lex:", nodeDividends.lex());
        // console.log("Payback addr`s liquidity:", payback.treasuryLiquidity());
        // console.log("Payback addr`s lex:", payback.lex());
        // if(lex.openSell()) _switch_sell(false);
        // vm.expectRevert(bytes("SELL_DISABLED"));
        // _exchange_utils(user, address(lex), USDT, amountIn);

        if(!lex.openSell()) _switch_sell(true);
        _exchange_utils(user, address(lex), USDT, amountIn);
    }

    function test_buy() public {
        uint256 amountIn = 100e18;
        deal(USDT, user, amountIn);
        if(!lex.openBuy()) _switch_buy(true);
        _exchange_utils(user, USDT, address(lex), amountIn);
    }

    function test_addLiquidity() public {
        uint256 amountIn = 100e18;
        deal(USDT, user, amountIn);
        if(!lex.openBuy()) _switch_buy(true);
        if(!lex.openSell()) _switch_sell(true);
        _exchange_utils(user, USDT, address(lex), amountIn / 2);

        _addLiquidity(user);
    }

    function test_removeLiquidity() public {

    }

    function _addLiquidity(address addr) internal {
        vm.startPrank(addr);

        uint amountToken = lex.balanceOf(addr);
        uint amountUsdt = IERC20(USDT).balanceOf(addr);

        lex.approve(router, type(uint256).max);
        IERC20(USDT).approve(router, type(uint256).max);

        // address pair = lex.pancakePair();

        (uint112 r0, uint112 r1,) = IUniswapV2Pair(lex.pancakePair()).getReserves();

        (uint reserveLex, uint reserveUsdt) =
            address(lex) < USDT ? (r0, r1) : (r1, r0);

        // 🔥 核心：算最优 token 数量
        uint optimalToken = amountUsdt * reserveLex / reserveUsdt;

        if (optimalToken > amountToken) {
            // token 不够 → 用 token 反推 usdt
            uint optimalUsdt = amountToken * reserveUsdt / reserveLex;

            IUniswapV2Router02(router).addLiquidity(
                address(lex),
                USDT,
                amountToken,
                optimalUsdt,
                0,
                0,
                addr,
                block.timestamp
            );
        } else {
            IUniswapV2Router02(router).addLiquidity(
                address(lex),
                USDT,
                optimalToken,
                amountUsdt,
                0,
                0,
                addr,
                block.timestamp
            );
        }

        vm.stopPrank();
    }

    // function test_removeLiquidity() public {}
}
