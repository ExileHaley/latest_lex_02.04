// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Lex} from "../src/token/Lex.sol";
import {Leo} from "../src/token/Leo.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NodeDividends} from "../src/NodeDividends.sol";
import {Payback} from "../src/Payback.sol";
import {Exchange} from "../src/Exchange.sol";

contract ExchangeTest is Test{
    Lex public lex;
    Leo public leo;
    NodeDividends public nodeDividends;
    Payback public payback;
    Exchange public exchange;

    address public nodeDividendsV1;
    address public uniswapV2Router;
    address public USDT;

    address public recipient;
    address public wallet;
    address public admin;
    address public treasuryLiquidity;
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
        deployExchange();

        lex.setAddrConfig(address(treasuryLiquidity), address(payback), address(nodeDividends), address(leo));
        // lex.switchBuy(true);
        // lex.switchSell(true);
        address[] memory addrsForLeo = new address[](3);
        addrsForLeo[0] = address(lex);
        addrsForLeo[1] = address(treasuryLiquidity);
        addrsForLeo[2] = address(exchange);
        leo.setAllowlist(addrsForLeo, true);

        address[] memory addrsForLex = new address[](1);
        addrsForLex[0] = address(exchange);
        lex.setAllowlist(addrsForLex, true);


        leo.setAddrConfig(address(nodeDividends), address(payback));
        // leo.setRate(5);


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

    function deployExchange() internal{
        // address _lex,
        // address _leo,
        // address _USDT,
        // address _wallet,
        // address _admin
        Exchange impl = new Exchange();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(address(lex), address(leo), address(USDT), wallet, admin))
        );
        exchange = Exchange(payable(address(proxy)));
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


    function _addAvailableLimit_utils(address addr, address token, uint256 amount) public {
        vm.startPrank(admin);
        address[] memory users = new address[](1);
        users[0] = addr;
        exchange.addAvailableLimit(address(token), users, amount);
        vm.stopPrank();
    }

    function test_buy_lex() public {
        address user = address(10);
        uint256 amount = 99e18;
        deal(USDT, user, amount);
        _addAvailableLimit_utils(user, address(lex), 100e18);
        vm.startPrank(user);
        IERC20(USDT).approve(address(exchange), amount);
        exchange.buy(address(lex), amount);
        vm.stopPrank();
        assertEq(exchange.availableLimit(user, address(lex)), 1e18);
    }


}
