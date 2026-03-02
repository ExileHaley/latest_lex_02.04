// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {TreasuryRules} from "../src/libraries/TreasuryRules.sol";

import {Treasury} from "../src/Treasury.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Queue} from "../src/Queue.sol";
import {Referrals} from "../src/Referrals.sol";
import {Router} from "../src/Router.sol";

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

    Lex public lex;
    Leo public leo;
    Tether public USDT;

    Treasury public treasury;
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

        vm.startPrank(owner);
        USDT = new Tether(initialRecipient);
        lex = new Lex(initialRecipient, wallet, address(USDT));
        
        leo = new Leo(initialRecipient, wallet, address(USDT));

        deployTreasury();
        deployNodeDividends();
        deployReferrals();
        deployQueue();
        deployRouter();

        treasury.setAddrConfig(address(referrals), address(nodeDividends), address(queue));
        nodeDividends.setTreasuryAddr(address(treasury));

        referrals.setAddrConfig(address(queue), address(router));
        queue.setAddrConfig(address(treasury), address(referrals), address(router));

        lex.setNodeDividends(address(nodeDividends));
        lex.setTreasuryAddr(address(treasury));

        leo.setNodeDividends(address(nodeDividends));
        vm.stopPrank();

        addLiquidity();
    }


    function deployTreasury() internal{
        // (address _admin, address _token, address _wallet, address _USDT)
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(treasuryImpl.initialize,(admin, address(lex), wallet, address(USDT)))
        );
        treasury = Treasury(payable(address(treasuryProxy)));
    }

    function deployNodeDividends() internal {
        // (
        // address _lex,
        // address _nodeDividendsV1,
        // address _admin,
        // address _USDT) 
        NodeDividends nodeDividendsImpl = new NodeDividends();
        ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
            address(nodeDividendsImpl),
            abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeV1, admin, address(USDT)))
        );
        nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
    }

    function deployQueue() internal{
        // (address _admin,
        // address _lex,
        // address _pair,
        // address _USDT)
        Queue queueImpl = new Queue();
        ERC1967Proxy queueProxy = new ERC1967Proxy(
            address(queueImpl),
            abi.encodeCall(queueImpl.initialize,(admin, address(lex), lex.pancakePair(), address(USDT)))
        );
        queue = Queue(payable(address(queueProxy)));
    }

    function deployReferrals() internal{
        // (
        //     address _rootAddr,
        //     address _lexv1
        // ) 
        Referrals referralsImpl = new Referrals();
        ERC1967Proxy referralsProxy = new ERC1967Proxy(
            address(referralsImpl),
            abi.encodeCall(referralsImpl.initialize,(rootAddr, nodeV1))
        );
        referrals = Referrals(payable(address(referralsProxy)));
    }

    

    function deployRouter() internal{
        // (
        //     address _treasury, 
        //     address _queue, 
        //     address _referrals,
        //     address _USDT
        // )
        router = new Router(address(treasury), address(queue), address(referrals), address(USDT));
    }

    function addLiquidity() internal {
        vm.startPrank(initialRecipient);
        USDT.approve(uniswapV2Router, 10000e18);
        lex.approve(uniswapV2Router, 10000e18);

        IUniswapV2Router02(uniswapV2Router).addLiquidity(
            address(USDT), 
            address(lex), 
            10000e18, 
            10000e18, 
            0, 
            0, 
            initialRecipient, 
            block.timestamp + 30
        );

        vm.stopPrank();
    }

    function test_referral() public {
        address user = address(5);
        vm.expectRevert(bytes("Error parent address."));
        referral_utils(user, user);

        vm.expectRevert(bytes("Zero address."));
        referral_utils(address(0), user);

        vm.expectRevert(bytes("Not eligible to be invited."));
        referral_utils(owner, user);

        referral_utils(rootAddr, user);

    }

    function test_stake() public {
        uint256 amount = 1000e18;
        address user = address(5);
        transfer_utils(address(USDT), initialRecipient, user, amount);
        referral_utils(rootAddr, user);
        stake_utils(address(USDT), user, amount - 900e18, 0);
    }

    function test_treasury_order() public {
        uint256 amount = 1000e18;
        address user = address(5);
        transfer_utils(address(USDT), initialRecipient, user, amount);
        referral_utils(rootAddr, user);

        stake_utils(address(USDT), user, amount, 2);

        vm.warp(block.timestamp + 10 days);
        (
            uint256 truthAward,
            uint256 claimCountdown,
            uint256 unstakeCountdown,
            bool    canClaim,
            bool    canUnstake,
            bool    canRestake
        ) = router.getOrderStatus(user, 0);

        console.log("truthAward:", truthAward);
        console.log("claimCountdown:", claimCountdown);
        console.log("unstakeCountdown:", unstakeCountdown);
        assertEq(canClaim, false);
        assertEq(canUnstake, false);
        assertEq(canRestake, false);
    }


    /////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////UTILS///////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////
    function referral_utils(address parent, address user) internal{
        vm.startPrank(user);
        router.referral(parent);
        vm.stopPrank();
    }

    function stake_utils(address token, address user, uint256 amount, uint8 stakeIndex) internal{
        vm.startPrank(user);
        IERC20(token).approve(address(router), amount);
        router.stake(amount, stakeIndex);
        vm.stopPrank();
    }

    function transfer_utils(address token, address from, address to, uint256 amount) internal{
        vm.startPrank(from);
        IERC20(token).transfer(to, amount);
        vm.stopPrank();
    }
}