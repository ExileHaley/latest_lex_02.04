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
    address user;

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
        user = address(5);

        vm.startPrank(owner);
        USDT = new Tether(initialRecipient);
        lex = new Lex(initialRecipient, wallet, address(USDT));
        leo = new Leo(initialRecipient, wallet, address(USDT));

        deployTreasury();
        deployNodeDividends();
        deployReferrals();
        deployTreasuryLiquidity();
        deployQueue();
        deployRouetr();

        treasury.setAddrConfig(address(queue), address(treasuryLiquidity));
        referrals.setAddrConfig(address(queue), address(router));
        queue.setAddrConfig(address(router));
        nodeDividends.setAddrConfig(address(treasuryLiquidity));

        lex.setNodeDividends(address(nodeDividends));
        lex.setTreasuryLiquidityAddr(address(treasuryLiquidity));
        leo.setNodeDividends(address(nodeDividends));

        vm.stopPrank();
        _addLiquidity();
        _transfer_utils(address(lex), initialRecipient, address(treasuryLiquidity), 500000e18);
    }

    function deployTreasury() internal{
        // initialize(address _wallet) 
        // setAddrConfig(
        //     address _queue,
        //     address _treasuryLiquidity
        // ) 
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(treasuryImpl.initialize,(wallet))
        );
        treasury = Treasury(payable(address(treasuryProxy)));
    } 

    function deployNodeDividends() internal{
        // initialize(
        //     address _lex,
        //     address _nodeDividendsV1,
        //     address _admin,
        //     address _USDT,
        // ) 

        NodeDividends nodeDividendsImpl = new NodeDividends();
        ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
            address(nodeDividendsImpl),
            abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeV1, admin, address(USDT)))
        );
        nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
    }

    function deployReferrals() internal{
        // initialize(
        //     address _rootAddr,
        //     address _lexv1
        // )
        // setAddrConfig(address _queue, address _router)
        Referrals referralsImpl = new Referrals();
        ERC1967Proxy referralsProxy = new ERC1967Proxy(
            address(referralsImpl),
            abi.encodeCall(referralsImpl.initialize,(rootAddr, nodeV1))
        );
        referrals = Referrals(payable(address(referralsProxy)));
    }

    function deployTreasuryLiquidity() internal{
        // initialize(
        //     address _admin,
        //     address _treasury,
        //     address _token,
        //     address _usdt,
        //     address _wallet,
        //     address _referrals,
        //     address _nodeDividends
        // ) 
        TreasuryLiquidity impl = new TreasuryLiquidity();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(
                admin,
                address(treasury),
                address(lex),
                address(USDT),
                wallet,
                address(referrals),
                address(nodeDividends)
            ))
        );
        treasuryLiquidity = TreasuryLiquidity(payable(address(proxy)));
    }

    function deployQueue() internal{
        // initialize(
        //     address _admin,
        //     address _lex,
        //     address _pair,
        //     address _USDT,
        //     address _treasury, 
        //     address _treasuryLiquidity,
        //     address _referrals, 
        // )
        // setAddrConfig(
        //     address _router
        // ) 
        Queue queueImpl = new Queue();
        ERC1967Proxy queueProxy = new ERC1967Proxy(
            address(queueImpl),
            abi.encodeCall(queueImpl.initialize,(
                admin, 
                address(lex), 
                lex.pancakePair(), 
                address(USDT),
                address(treasury),
                address(treasuryLiquidity),
                address(referrals)
            ))
        );
        queue = Queue(payable(address(queueProxy)));
    }

    function deployRouetr() internal{
        // (
        //     address _treasury, 
        //     address _queue, 
        //     address _referrals,
        //     address _USDT
        // )
        router = new Router(address(treasury), address(queue), address(referrals), address(USDT));
    }
    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    function _addLiquidity() internal {
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

    function _freez_utils() internal{
        uint256 percent61 = USDT.balanceOf(lex.pancakePair()) * 61 / 100;
        USDT.reduce(lex.pancakePair(), percent61);
        IUniswapV2Pair(lex.pancakePair()).sync();
    }

    function _unfreeze_utils() internal{
        uint256 reminingUsdt = USDT.balanceOf(lex.pancakePair());
        uint256 toAmount = reminingUsdt * 2;
        _transfer_utils(address(USDT), initialRecipient, lex.pancakePair(), toAmount);
        IUniswapV2Pair(lex.pancakePair()).sync();
    }


    function _transfer_utils(address _token, address _from, address _to, uint256 _amount) internal{
        vm.startPrank(_from);
        IERC20(_token).transfer(_to, _amount);
        vm.stopPrank();
    }

    function _referral_utils(address _parent, address _user) internal{
        vm.startPrank(_user);
        router.referral(_parent);
        vm.stopPrank();
    }

    function _stake_utils(address _token, address _user, uint256 _amount, uint8 _stakeIndex) internal{
        vm.startPrank(_user);
        IERC20(_token).approve(address(router), _amount);
        router.stake(_amount, _stakeIndex);
        vm.stopPrank();
    }

    function _unstake_utils(address _user, uint256 _orderIndex) internal{
        vm.startPrank(_user);
        router.unstake(_orderIndex);
        vm.stopPrank();
    }

    function _claim_utils(address _user, uint256 _orderIndex) internal{
        vm.startPrank(_user);
        router.claim(_orderIndex);
        vm.stopPrank();
    }

    function _restake_utils(address _user, uint256 _orderIndex, uint8 _newStakeIndex) internal{
        vm.startPrank(_user);
        router.restake(_orderIndex, _newStakeIndex);
        vm.stopPrank();
    }

    function _referral_and_stake_utils(address _user, uint256 _amount, uint8 _stakeIndex) internal{
        _referral_utils(rootAddr, _user);
        _transfer_utils(address(USDT), initialRecipient, _user, _amount);
        _stake_utils(address(USDT), _user, _amount, _stakeIndex);
    }



    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////

    function test_referral() public {
        vm.expectRevert(bytes("Error parent address."));
        _referral_utils(user, user);

        vm.expectRevert(bytes("Zero address."));
        _referral_utils(address(0), user);

        vm.expectRevert(bytes("Not eligible to be invited."));
        _referral_utils(owner, user);

        _referral_utils(rootAddr, user);

    }

    function test_stake_normalcy() public {
        uint256 amount = 1000e18;
        _referral_and_stake_utils(user, amount, 1);
        
        vm.warp(block.timestamp + 10 days);
        (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
        assertEq(result.canClaim, false);
        vm.warp(block.timestamp + 5 days);
        _claim_utils(user, 0);
        console.log("After claim balance of user:", USDT.balanceOf(user) / 1e18);
        (uint256 truthAward0, Models.RuleResult memory result0) = router.getOrderStatus(user, 0);

        Models.Order[] memory orders = router.getUserOrders(user);
        console.log("claimed:", orders[0].claimed);
        console.log("frozenClaimed:", orders[0].frozenClaimed);


        assertEq(truthAward0, 0);
        assertEq(result0.canClaim, false);
        assertEq(result0.canRestake, true);
        assertEq(result0.canUnstake, true);

        _unstake_utils(user, 0);
        console.log("After unstake balance of user:", USDT.balanceOf(user) / 1e18);
    }

    function test_stake_freez() public {
        //user质押
        uint256 amount = 1000e18;
        _referral_and_stake_utils(user, amount, 1);
        vm.warp(block.timestamp + 1 days);
        //冻结
        _freez_utils();
        //user1质押
        address user1 = address(6);
        uint256 amount1 = 1000e18;
        _referral_and_stake_utils(user1, amount1, 1);

        //让时间流逝
        vm.warp(block.timestamp + 15 days);
        //获取收益数据
        (uint256 truthAward, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
        (uint256 truthAward1, Models.RuleResult memory result1) = router.getOrderStatus(user1, 0);
        console.log("Truth award for user:", truthAward);
        console.log("Truth award for user1:", truthAward1);

        assertEq(result.canRestake, false);
        assertEq(result.canUnstake, false);

        assertEq(result1.canUnstake, true);
        assertEq(result1.canRestake, true);
    }

    function test_claim_normalcy() public {
        uint256 amount = 1000e18;
        _referral_and_stake_utils(user, amount, 2);
        //时间流逝
        vm.warp(block.timestamp + 15 days);
        (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
        assertEq(result.canClaim, true);

        vm.warp(block.timestamp + 15 days);
        (, Models.RuleResult memory result0) = router.getOrderStatus(user, 0);
        assertEq(result0.canClaim, true);

        vm.warp(block.timestamp + 2 days);
        (, Models.RuleResult memory result1) = router.getOrderStatus(user, 0);
        assertEq(result1.canClaim, false);
        //测试提现窗口
        //测试冻结后订单的收益
        //测试到期后24小时后不允许提取收益
        _freez_utils();
        // _referral_and_stake_utils(user, amount, 2);
        _transfer_utils(address(USDT), initialRecipient, user, amount);
        _stake_utils(address(USDT), user, amount, 2);
        (, Models.RuleResult memory result2) = router.getOrderStatus(user, 0);
        assertEq(result2.canUnstake, false);
        assertEq(result2.canRestake, false);

        vm.warp(block.timestamp + 14 days);
        (, Models.RuleResult memory result3) = router.getOrderStatus(user, 1);
        assertEq(result3.canClaim, false);
        vm.warp(block.timestamp + 1 days);
        (, Models.RuleResult memory result4) = router.getOrderStatus(user, 1);
        assertEq(result4.canClaim, true);
    }


    function test_restake_normalcy() public {
        uint256 amount = 1000e18;
        _referral_and_stake_utils(user, amount, 2);
        Models.Order[] memory orders = router.getUserOrders(user);
        assertEq(orders.length, 1);
        vm.warp(block.timestamp + 30 days);
        (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
        assertEq(result.canRestake, true);
        vm.expectRevert(bytes("Cannot restake"));
        _restake_utils(user, 0, 1);

        _restake_utils(user, 0, 2);
        console.log("After restake usdt balance of root:", USDT.balanceOf(rootAddr));
        console.log("After restake usdt balance of user:", USDT.balanceOf(user));
    }
    
}