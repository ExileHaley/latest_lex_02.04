// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NodeDividends} from "../src/NodeDividends.sol";
import {Payback} from "../src/Payback.sol";

import {Lex} from "../src/token/Lex.sol";
import {Leo} from "../src/token/Leo.sol";
// import {Tether} from "../src/mock/Tether.sol";

contract LexTest is Test{
    Lex public lex;
    Leo public leo;
    NodeDividends public nodeDividends;
    Payback public payback;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public nodeDividendsV1;
    address public uniswapV2Router;
    address public USDT;

    address public recipient;
    address public wallet;
    address public admin;
    address public treasuryLiquidity;
    address public exchange;
    uint256 mainnetFork;
    
    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);

        USDT = address(0x55d398326f99059fF775485246999027B3197955);
        nodeDividendsV1 = address(0x285Ca769Ab57CBB623513921C9a9B3a8fd8F936A);
        uniswapV2Router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        recipient = address(1);
        wallet = address(2);
        admin = address(3);
        treasuryLiquidity = address(4);

        // 所有 owner 调用在同一个 prank 下
        vm.startPrank(recipient);

        lex = new Lex(recipient, wallet, address(USDT));
        leo = new Leo(recipient, wallet, address(USDT));

        deployNodeDividends();
        deployPayback();

        lex.setAddrConfig(address(treasuryLiquidity), address(payback), address(nodeDividends), address(leo));
        lex.switchBuy(true);
        lex.switchSell(true);

        leo.setAddrConfig(address(nodeDividends), address(payback), address(exchange));
        leo.setRate(5);

        address[] memory addrs = new address[](2);
        addrs[0] = address(lex);
        addrs[1] = address(treasuryLiquidity);
        leo.setAllowlist(addrs, true);

        _addLiquidity(recipient, address(lex));
        _addLiquidity(recipient, address(leo));

        vm.stopPrank();
    }
    function deployNodeDividends() internal{
        // initialize(
        //     address _lex,
        //     address _nodeDividendsV1,
        //     address _admin,
        //     address _USDT,
        // ) 
        // setAddrConfig(address _treasuryLiquidity)
        NodeDividends nodeDividendsImpl = new NodeDividends();
        ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
            address(nodeDividendsImpl),
            abi.encodeCall(nodeDividendsImpl.initialize,(address(leo), address(lex), nodeDividendsV1, admin, address(USDT)))
        );
        nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
    }

    function deployPayback() internal{
        // initialize(
        //     address _USDT,
        //     address _treasuryLiquidity,
        //     address _lex,
        //     address _leo,
        //     address _admin
        // ) 
        Payback impl = new Payback();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(address(USDT), address(treasuryLiquidity), address(lex), address(leo), admin))
        );
        payback = Payback(payable(address(proxy)));
    }

    function _addLiquidity(address addr, address token) internal {
        vm.startPrank(addr);
        IERC20(USDT).approve(uniswapV2Router, 10000e18);
        IERC20(token).approve(uniswapV2Router, 10000e18);

        IUniswapV2Router02(uniswapV2Router).addLiquidity(
            address(USDT), 
            token, 
            10000e18, 
            10000e18, 
            0, 
            0, 
            addr, 
            block.timestamp + 30
        );

        vm.stopPrank();
    }

    function _exchange_utils(address addr, address fromToken, address toToken, uint256 amountIn) internal{
        vm.startPrank(addr);
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        IERC20(fromToken).approve(uniswapV2Router, amountIn);

        IUniswapV2Router02(uniswapV2Router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 
            0, 
            path, 
            addr, 
            block.timestamp
        );
        vm.stopPrank();
    }

    function _transfer_utils(address token, address from, address to, uint256 amount) internal{
        vm.startPrank(from);
        IERC20(token).transfer(to, amount);
        vm.stopPrank();
    }

    function test_buy() public {
        address user = address(10);
        uint256 amountIn = 100e18;
        deal(USDT, user, amountIn);
        _exchange_utils(user, USDT, address(lex), amountIn);


        address user1 = address(11);
        uint256 amountIn1 = 5000e18;
        deal(USDT, user1, amountIn1);
        _exchange_utils(user1, USDT, address(lex), amountIn1);

        uint256 balanceLex = lex.balanceOf(user);
        address user2 = address(12);
        _transfer_utils(address(lex), user, user2, balanceLex);
    
       
        _exchange_utils(user2, address(lex), USDT, balanceLex);
        console.log("Usdt balance of wallet:", IERC20(USDT).balanceOf(wallet));
        console.log("Usdt balance of node:", IERC20(USDT).balanceOf(address(nodeDividends)));
        console.log("Leo balance of payback:", leo.balanceOf(address(payback)));
        assertEq(lex.balanceOf(address(lex)), 0);
    }


    function test_leo_buy() public{
        address user = address(10);
        uint256 amountIn = 100e18;
        deal(USDT, user, amountIn);
        _exchange_utils(user, USDT, address(leo), amountIn);

        console.log("TreasuryLiquidity", payback.treasuryLiquidity());
        console.log("Lex", payback.lex());
        console.log("Leo", payback.leo());
        address user1 = address(11);
        uint256 balanceLeo = leo.balanceOf(user);
        _transfer_utils(address(leo), user, user1, balanceLeo);
    }


    function test_lex_buy_fee() public {
        address user = address(10);
        uint256 amountIn = 100e18;
        deal(USDT, user, amountIn);
        _exchange_utils(user, USDT, address(lex), amountIn);

        // uint256 beforeBal = IERC20(USDT).balanceOf(wallet);
        _transfer_utils(address(lex), recipient, user, 1e17);
        address user1 = address(11);
        _transfer_utils(address(lex), user, user1, 1e17);
        console.log("Usdt balance of wallet:", IERC20(USDT).balanceOf(wallet));
        console.log("Usdt balance of node:", IERC20(USDT).balanceOf(address(nodeDividends)));
        console.log("Leo balance of payback:", leo.balanceOf(address(payback)));
    }

    function test_burnFromPair() public {
        address user = address(10);
        uint256 amount = 100e18;

        console.log("Leo balance of recipient:", leo.balanceOf(recipient));

        _transfer_utils(address(leo), recipient, user, amount);

        vm.warp(block.timestamp + 1 days);
        address user1 = address(11);
        _transfer_utils(address(leo), user, user1, amount);
        console.log("Leo balance of dead:", leo.balanceOf(DEAD));
    }
   
}