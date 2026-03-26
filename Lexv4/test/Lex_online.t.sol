// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// //导入要部署的代币
// import {Lex} from "../src/token/Lex.sol";
// import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
// import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// // import {Leo} from "../src/token/Leo.sol";
// import {NodeDividends} from "../src/NodeDividends.sol";
// import {Payback} from "../src/Payback.sol";

// contract LexTest is Test{
//     Lex public lex;
//     address public USDT;
//     address public owner;
//     address public user;
//     address public router;
//     NodeDividends public nodeDividends;
//     Payback public payback;

//     uint256 mainnetFork;

//     function setUp() public {
//         mainnetFork = vm.createFork(vm.envString("rpc_url"));
//         vm.selectFork(mainnetFork);
//         lex = Lex(0x26a76CcA2f992F5F467184B437dCBb27591675B1);
//         USDT = address(0x7816C568448A25B75197D106E2e4DBC0FD9fa3C8);
//         owner = address(0xc263D128DdbA54405edDD34C059aD6F342a42a05);
//         router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
//         nodeDividends = NodeDividends(payable(0xA747cE2773193a951Dc8A773d4960BBf2cFA99cB));
//         payback = Payback(payable(0xD6EdA3A1472a03137Cb6C4DEd3Cd84e62AdFFa27));
//         user = address(1);
//     }

//     function _exchange_utils(address addr, address fromToken, address toToken, uint256 amountIn) internal{
//         vm.startPrank(addr);
//         address[] memory path = new address[](2);
//         path[0] = fromToken;
//         path[1] = toToken;
//         IERC20(fromToken).approve(router, amountIn);

//         IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
//             amountIn, 
//             0, 
//             path, 
//             addr, 
//             block.timestamp
//         );
//         vm.stopPrank();
//     }


//     function test_profit_fee() public {
//         address user1 = address(10);
//         uint256 amount1 = 100e18;
//         deal(USDT, user1, amount1);
//         _exchange_utils(user1, USDT, address(lex), amount1);


//         address user2 = address(11);
//         uint256 amount2 = 10000e18;
//         deal(USDT, user2, amount2);
//         _exchange_utils(user2, USDT, address(lex), amount2);


//         uint256 balanceLex = lex.balanceOf(user1);
//         _exchange_utils(user1, address(lex), USDT, balanceLex);
//     }
// }
