// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
// import {Queue} from "../src/Queue.sol";
// import {Referrals} from "../src/Referrals.sol";
// import {Router} from "../src/Router.sol";
// //导入要部署的代币
// import {Lex} from "../src/token/Lex.sol";
// import {Leo} from "../src/token/Leo.sol";
// import {Tether} from "../src/mock/Tether.sol";


// contract RouterTest is Test{
//     //部署代币合约
//     Lex public lex;
//     Leo public leo;
//     Tether public USDT;
//     //部署质押合约
//     Treasury public treasury;
//     TreasuryLiquidity public treasuryLiquidity;
//     NodeDividends public nodeDividends;
//     Payback public payback;
//     Queue public queue;
//     Referrals public referrals;
//     Router public router;

//     //创建地址
//     address owner;
//     address admin;
//     address user;
//     address initialRecipient;
//     address unstakeWallet;
//     address remainingWallet;
//     address claimWallet;
//     address lexWallet;
//     address leoWallet;
    
//     //实际地址
//     address nodeDividendsV1;
//     address rootAddr;
//     address uniswapV2Router;
//     address node_test_user0;
//     address node_test_user1;

//     uint256 mainnetFork;
    
//     function setUp() public {
//         mainnetFork = vm.createFork(vm.envString("rpc_url"));
//         vm.selectFork(mainnetFork);

//         uniswapV2Router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
//         nodeDividendsV1 = address(0x285Ca769Ab57CBB623513921C9a9B3a8fd8F936A);
//         rootAddr = address(0x19Cf31C1DA6b2c8cD9fD0b8AA4466433196BDBe6);
//         node_test_user0 = address(0x3001Ebb8f90160d76ce570E4bE73ce31EC10F839);
//         node_test_user1 = address(0xB74EC8C4Daf19fa2Cd32c77b7aE1aC614B71E2Ee);

//         owner = address(1);
//         admin = address(2);
//         user = address(3);
//         initialRecipient = address(4);
//         unstakeWallet = address(5);
//         remainingWallet = address(6);
//         claimWallet = address(7);
//         lexWallet = address(8);
//         leoWallet = address(9);

//         vm.startPrank(owner);
//         USDT = new Tether(initialRecipient);
//         lex = new Lex(initialRecipient, lexWallet, address(USDT));
//         leo = new Leo(initialRecipient, leoWallet, address(USDT));

//         deployTreasury();
//         deployNodeDividends();
//         deployReferrals();
//         deployTreasuryLiquidity();
//         deployQueue();
//         deployPayback();
//         deployRouetr();

//         treasury.setAddrConfig(address(queue), address(treasuryLiquidity));
//         referrals.setAddrConfig(address(queue), address(router));
//         queue.setAddrConfig(address(router));
//         nodeDividends.setAddrConfig(address(treasuryLiquidity));
//         treasuryLiquidity.setPaybackAddr(address(payback));

//         lex.setAddrConfig(address(treasuryLiquidity), address(payback), address(nodeDividends), address(leo));
//         leo.setAddrConfig(address(nodeDividends), address(payback));


//         address[] memory addrs = new address[](2);
//         addrs[0] = address(lex);
//         addrs[1] = address(treasuryLiquidity);
//         leo.setAllowlist(addrs, true);

//         // payback.setIsDividends(true);
//         vm.stopPrank();
//         _addLiquidity(address(lex));
//         _addLiquidity(address(leo));
//         _transfer_utils(address(lex), initialRecipient, address(treasuryLiquidity), 500000e18);
//         _add_nodeDividends_test_data();
//         _add_payback_test_data();
//     }

//     function deployTreasury() internal{
//         // initialize(address unstakeWallet) 
//         // setAddrConfig(
//         //     address _queue,
//         //     address _treasuryLiquidity
//         // ) 
//         Treasury treasuryImpl = new Treasury();
//         ERC1967Proxy treasuryProxy = new ERC1967Proxy(
//             address(treasuryImpl),
//             abi.encodeCall(treasuryImpl.initialize,(unstakeWallet))
//         );
//         treasury = Treasury(payable(address(treasuryProxy)));
//     } 

//     function deployNodeDividends() internal{
//         // initialize(
//         //     address _lex,
//         //     address _nodeDividendsV1,
//         //     address _admin,
//         //     address _USDT,
//         // ) 
//         // setAddrConfig(address _treasuryLiquidity)
//         NodeDividends nodeDividendsImpl = new NodeDividends();
//         ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
//             address(nodeDividendsImpl),
//             abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeDividendsV1, admin, address(USDT)))
//         );
//         nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
//     }

//     function deployReferrals() internal{
//         // initialize(
//         //     address _rootAddr,
//         //     address _lexv1
//         // )
//         // setAddrConfig(address _queue, address _router)
//         Referrals referralsImpl = new Referrals();
//         ERC1967Proxy referralsProxy = new ERC1967Proxy(
//             address(referralsImpl),
//             abi.encodeCall(referralsImpl.initialize,(rootAddr, nodeDividendsV1))
//         );
//         referrals = Referrals(payable(address(referralsProxy)));
//     }

//     function deployTreasuryLiquidity() internal{
//         // initialize(
//             // address _admin,
//             // address _treasury,
//             // address _token,
//             // address _usdt,
//             // address _leo,
//             // address _referrals,
//             // address _nodeDividends,
//             // address _remainingWallet,
//             // address _claimWallet
//         // ) 
//         TreasuryLiquidity impl = new TreasuryLiquidity();
//         ERC1967Proxy proxy = new ERC1967Proxy(
//             address(impl),
//             abi.encodeCall(impl.initialize,(
//                 admin,
//                 address(treasury),
//                 address(lex),
//                 address(USDT),
//                 address(leo),
//                 address(referrals),
//                 address(nodeDividends),
//                 // address(payback),
//                 address(remainingWallet),
//                 address(claimWallet)
//             ))
//         );
//         treasuryLiquidity = TreasuryLiquidity(payable(address(proxy)));
//     }

//     function deployQueue() internal{
//         // initialize(
//         // address _admin,
//         // address _lex,
//         // address _pair,
//         // address _USDT,
//         // address _treasury, 
//         // address _treasuryLiquidity,
//         // address _referrals
//         // )
//         // setAddrConfig(
//         //     address _router
//         // ) 
//         Queue queueImpl = new Queue();
//         ERC1967Proxy queueProxy = new ERC1967Proxy(
//             address(queueImpl),
//             abi.encodeCall(queueImpl.initialize,(
//                 admin, 
//                 address(lex), 
//                 lex.pancakePair(), 
//                 address(USDT),
//                 address(treasury),
//                 address(treasuryLiquidity),
//                 address(referrals)
//             ))
//         );
//         queue = Queue(payable(address(queueProxy)));
//     }

//     function deployPayback() internal{
//         // initialize(
//         //     address _USDT,
//         //     address _treasuryLiquidity,
//         //     address _lex,
//         //     address _leo,
//         //     address _admin
//         // ) 
//         Payback impl = new Payback();
//         ERC1967Proxy proxy = new ERC1967Proxy(
//             address(impl),
//             abi.encodeCall(impl.initialize,(address(USDT), address(treasuryLiquidity), address(lex), address(leo), admin))
//         );
//         payback = Payback(payable(address(proxy)));
//     }

//     function deployRouetr() internal{
//         // (
//         //     address _treasury, 
//         //     address _queue, 
//         //     address _referrals,
//         //     address _USDT
//         // )
//         router = new Router(address(treasury), address(queue), address(referrals), address(USDT));
//     }

    
//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////
//     function _add_payback_test_data() internal{
//         vm.startPrank(admin);
//         payback.add(node_test_user0, 100e18);
//         payback.add(node_test_user1, 100e18);
//         vm.stopPrank();
//     }

//     function _add_nodeDividends_test_data() internal{
//         vm.startPrank(owner);
//         address[] memory addrs = new address[](2);
//         addrs[0] = node_test_user0;
//         addrs[1] = node_test_user1;
//         nodeDividends.batchAdd(addrs);
//         vm.stopPrank();
//     }

//     function _addLiquidity(address token) internal {
//         vm.startPrank(initialRecipient);
//         USDT.approve(uniswapV2Router, 10000e18);
//         IERC20(token).approve(uniswapV2Router, 10000e18);

//         IUniswapV2Router02(uniswapV2Router).addLiquidity(
//             address(USDT), 
//             token, 
//             10000e18, 
//             10000e18, 
//             0, 
//             0, 
//             initialRecipient, 
//             block.timestamp + 30
//         );

//         vm.stopPrank();
//     }


//     function _freez_utils() internal{
//         uint256 percent61 = USDT.balanceOf(lex.pancakePair()) * 61 / 100;
//         USDT.reduce(lex.pancakePair(), percent61);
//         IUniswapV2Pair(lex.pancakePair()).sync();
//     }

//     function _unfreeze_utils() internal{
//         uint256 reminingUsdt = USDT.balanceOf(lex.pancakePair());
//         uint256 toAmount = reminingUsdt * 2;
//         _transfer_utils(address(USDT), initialRecipient, lex.pancakePair(), toAmount);
//         IUniswapV2Pair(lex.pancakePair()).sync();
//     }


//     function _transfer_utils(address _token, address _from, address _to, uint256 _amount) internal{
//         vm.startPrank(_from);
//         IERC20(_token).transfer(_to, _amount);
//         vm.stopPrank();
//     }

//     function _referral_utils(address _parent, address _user) internal{
//         vm.startPrank(_user);
//         router.referral(_parent);
//         vm.stopPrank();
//     }

//     function _stake_utils(address _user, uint256 _amount, uint8 _stakeIndex) internal{
//         vm.startPrank(_user);
//         USDT.approve(address(router), _amount);
//         router.stake(_amount, _stakeIndex);
//         vm.stopPrank();
//     }

//     function _unstake_utils(address _user, uint256 _orderIndex) internal{
//         vm.startPrank(_user);
//         router.unstake(_orderIndex);
//         vm.stopPrank();
//     }

//     function _claim_utils(address _user, uint256 _orderIndex) internal{
//         vm.startPrank(_user);
//         router.claim(_orderIndex);
//         vm.stopPrank();
//     }

//     function _restake_utils(address _user, uint256 _orderIndex, uint8 _newStakeIndex) internal{
//         vm.startPrank(_user);
//         router.restake(_orderIndex, _newStakeIndex);
//         vm.stopPrank();
//     }

//     function _referral_and_stake_utils(address _user, uint256 _amount, uint8 _stakeIndex) internal{
//         _referral_utils(rootAddr, _user);
//         _transfer_utils(address(USDT), initialRecipient, _user, _amount);
//         _stake_utils(_user, _amount, _stakeIndex);
//     }

//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////
//     ////////////////////////////////////////////////////////////////////////////////

//     function test_referral() public {
//         vm.expectRevert(bytes("Error parent address."));
//         _referral_utils(user, user);

//         vm.expectRevert(bytes("Zero address."));
//         _referral_utils(address(0), user);

//         vm.expectRevert(bytes("Not eligible to be invited."));
//         _referral_utils(owner, user);

//         _referral_utils(rootAddr, user);

//     }

//     function test_stake_normalcy() public {
//         uint256 amount = 10000e18;
//         _referral_and_stake_utils(user, amount, 1);
        
//         vm.warp(block.timestamp + 1 hours);
//         (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
//         assertEq(result.claimCountdown, 2 hours);
//         assertEq(result.unstakeCountdown, 47 hours);
//         assertEq(result.canClaim, false);

//         vm.warp(block.timestamp + 2 hours);
        
//         (, Models.RuleResult memory result0) = router.getOrderStatus(user, 0);
//         assertEq(result0.claimCountdown, 0);
//         assertEq(result0.canClaim, true);
//         _claim_utils(user, 0);
        
//         assertEq(nodeDividends.getUserAward(node_test_user0), nodeDividends.getStakeFeeAward(node_test_user0));
//         assertEq(nodeDividends.getUserAward(node_test_user1), nodeDividends.getStakeFeeAward(node_test_user1));

//         vm.warp(block.timestamp + 1 hours);
//         (, Models.RuleResult memory result1) = router.getOrderStatus(user, 0);
//         assertEq(result1.claimCountdown, 2 hours);
//         assertEq(result1.canClaim, false);
//     }

//     function test_stake_freez() public {
//         //user质押
//         uint256 amount = 1000e18;
//         _referral_and_stake_utils(user, amount, 1);
//         _freez_utils();
//         vm.warp(block.timestamp + 3 hours);
//         _claim_utils(user, 0);

//         vm.warp(block.timestamp + 1 days);
//         (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
//         assertEq(result.isFrozen, true); //这里已经冻结了没问题
//         assertEq(result.canClaim, true); //那么这里随时可提取应该是true，实际是false
//         assertEq(result.claimCountdown, 0); //这里倒计时应该是0，实际是7200
//         assertEq(result.unstakeCountdown, type(uint256).max); 
//         assertEq(result.canRestake, false);
//         assertEq(result.canUnstake, false);

//         vm.warp(block.timestamp + 21 hours);
//         (, Models.RuleResult memory result1) = router.getOrderStatus(user, 0);
//         assertEq(result1.canClaim, true); //这里应该是true，实际是false
//         assertEq(result1.claimCountdown, 0); //这里应该还是0，实际上是3600

//         assertEq(result.canRestake, false);
//         assertEq(result.canUnstake, false);

//         _claim_utils(user, 0);

//         (
//             ,
//             ,
//             ,
//             uint256 unstakeRemaining
//         ) = router.getCurrentQuota();
//         console.log("unstake quota:",unstakeRemaining);
//         // _unstake_utils(user, 0);
//     }

//     function test_stake_quota() public {
//         vm.warp(block.timestamp + 1 days);

//         vm.startPrank(admin);
//         queue.setQuotaRatios(100, 100);
//         vm.stopPrank();

//         (
//             uint256 stakeUsed,
//             uint256 stakeRemaining,
//             uint256 unstakeUsed,
//             uint256 unstakeRemaining
//         ) = router.getCurrentQuota();
//         assertEq(stakeUsed, 0);
//         console.log("stake remaining quota:", stakeRemaining / 1e18);
//         assertEq(unstakeUsed, 0);
//         console.log("unstake remaining quota:", unstakeRemaining / 1e18);

//         uint256 amount = 1000e18;
//         _referral_and_stake_utils(user, amount, 1);

//         (
//             ,,,,,,uint8 status
//         ) = router.getQueueInfo(0);
//         assertEq(status, 0);

//         vm.startPrank(user);
//         router.cancelQueue(0);
//         vm.stopPrank();
//         assertEq(USDT.balanceOf(user), 998e18);
//         (
//             ,,,uint256 poolBalance
//         ) = router.getFomoInfo();
//         assertEq(poolBalance, 2e18);
//     }

//     function test_nodeDividends() public {
//         vm.startPrank(address(treasuryLiquidity));
//         nodeDividends.updateFarm(Models.Source.STAKE_FEE, 100000e18);
//         vm.stopPrank();

//         assertEq(nodeDividends.getUserAward(node_test_user0), nodeDividends.getStakeFeeAward(node_test_user0));
//         assertEq(nodeDividends.getUserAward(node_test_user0), 500e18);
//         assertEq(nodeDividends.getUserAward(node_test_user1), nodeDividends.getStakeFeeAward(node_test_user1));
//         assertEq(nodeDividends.getUserAward(node_test_user1), 10000e18);


//         vm.startPrank(address(lex));
//         nodeDividends.updateFarm(Models.Source.PROFIT_FEE, 100000e18);
//         vm.stopPrank();

//         assertEq(nodeDividends.getUserAward(node_test_user0), 1000e18);
//         // console.log("Profit fee issue:", nodeDividends.getUserAward(node_test_user1) / 1e18);
//         uint256 award_test_user1 = nodeDividends.getUserAward(node_test_user1);

//         vm.startPrank(address(lex));
//         nodeDividends.updateFarm(Models.Source.TAX_FEE, 100000e18);
//         vm.stopPrank();
//         assertEq(nodeDividends.getUserAward(node_test_user0), 1500e18);
//         assertEq(nodeDividends.getUserAward(node_test_user1), award_test_user1 + uint256(10000e18));

//         _transfer_utils(address(USDT), initialRecipient, address(nodeDividends), 2000e18);

//         vm.startPrank(node_test_user0);
//         nodeDividends.claim();
//         vm.stopPrank();

//         assertEq(nodeDividends.getUserAward(node_test_user0), 0);
//     }

//     function test_payback_capped() public {


//         // treasuryLiquidity 更新 farm
//         vm.startPrank(address(treasuryLiquidity));
//         payback.updateFarm(1000e18);
//         vm.stopPrank();
//         uint256 award0 = payback.getUserAward(node_test_user0);
//         uint256 award1 = payback.getUserAward(node_test_user1);

//         // lex 更新 farm
//         vm.startPrank(address(lex));
//         payback.updateFarm(1000e18);
//         vm.stopPrank();
//         uint256 award2 = payback.getUserAward(node_test_user0);
//         uint256 award3 = payback.getUserAward(node_test_user1);

//         assertEq(award0, award2);
//         assertEq(award1, award3);

//         _transfer_utils(address(leo), initialRecipient, address(payback), 2000e18);
//         vm.startPrank(node_test_user0);
//         payback.claim();
//         vm.stopPrank();

//         assertEq(payback.getUserAward(node_test_user0), 0);
//         // // 模拟多轮 farm 分红
//         // for(uint256 i = 0; i < 5; i++) {
            

//         //     // 检查用户封顶逻辑
            

//         //     uint256 simulatedUsdt0 = payback._getAmountsOut(award0);
//         //     uint256 simulatedUsdt1 = payback._getAmountsOut(award1);

//         //     (uint256 staking0,,,) = payback.userInfo(node_test_user0);
//         //     (uint256 staking1,,,) = payback.userInfo(node_test_user1);

//         //     (,,,uint256 usdtValue0) = payback.userInfo(node_test_user0);
//         //     (,,,uint256 usdtValue1) = payback.userInfo(node_test_user1);

//         //     console.log("Round", i);
//         //     // console.log("user0 award:", award0 / 1e18, "USDT equivalent:", simulatedUsdt0 / 1e18, "staking remaining:", staking0 - usdtValue0);
//         //     // console.log("user1 award:", award1 / 1e18, "USDT equivalent:", simulatedUsdt1 / 1e18, "staking remaining:", staking1 - usdtValue1);

//         //     // 验证封顶不突破 staking
//         //     assertTrue(simulatedUsdt0 + usdtValue0 <= staking0, "user0 exceeded staking!");
//         //     assertTrue(simulatedUsdt1 + usdtValue1 <= staking1, "user1 exceeded staking!");
//         // }


//     }

// //     function test_claim_normalcy() public {
// //         uint256 amount = 1000e18;
// //         _referral_and_stake_utils(user, amount, 2);
// //         //时间流逝
// //         vm.warp(block.timestamp + 15 days);
// //         (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
// //         assertEq(result.canClaim, true);

// //         vm.warp(block.timestamp + 15 days);
// //         (, Models.RuleResult memory result0) = router.getOrderStatus(user, 0);
// //         assertEq(result0.canClaim, true);

// //         vm.warp(block.timestamp + 2 days);
// //         (, Models.RuleResult memory result1) = router.getOrderStatus(user, 0);
// //         assertEq(result1.canClaim, false);
// //         //测试提现窗口
// //         //测试冻结后订单的收益
// //         //测试到期后24小时后不允许提取收益
// //         _freez_utils();
// //         // _referral_and_stake_utils(user, amount, 2);
// //         _transfer_utils(address(USDT), initialRecipient, user, amount);
// //         _stake_utils(address(USDT), user, amount, 2);
// //         (, Models.RuleResult memory result2) = router.getOrderStatus(user, 0);
// //         assertEq(result2.canUnstake, false);
// //         assertEq(result2.canRestake, false);

// //         vm.warp(block.timestamp + 14 days);
// //         (, Models.RuleResult memory result3) = router.getOrderStatus(user, 1);
// //         assertEq(result3.canClaim, false);
// //         vm.warp(block.timestamp + 1 days);
// //         (, Models.RuleResult memory result4) = router.getOrderStatus(user, 1);
// //         assertEq(result4.canClaim, true);
// //     }


// //     function test_restake_normalcy() public {
// //         uint256 amount = 1000e18;
// //         _referral_and_stake_utils(user, amount, 2);
// //         Models.Order[] memory orders = router.getUserOrders(user);
// //         assertEq(orders.length, 1);
// //         vm.warp(block.timestamp + 30 days);
// //         (, Models.RuleResult memory result) = router.getOrderStatus(user, 0);
// //         assertEq(result.canRestake, true);
// //         vm.expectRevert(bytes("Cannot restake"));
// //         _restake_utils(user, 0, 1);

// //         _restake_utils(user, 0, 2);
// //         console.log("After restake usdt balance of root:", USDT.balanceOf(rootAddr));
// //         console.log("After restake usdt balance of user:", USDT.balanceOf(user));
// //     }
    
// }