// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test,console} from "forge-std/Test.sol";
import {Recharge} from "../src/Recharge.sol";
import {Enum} from "../src/libraries/Enum.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVenus {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
}

contract RechargeTest is Test{
    
    Recharge public recharge;
    address  public recipient;
    address  public initialCode;
    address  public owner;
    address  public admin;
    address  public user;
    address  public user1;
    address  public user2;
    address  public user3;
    address  public user4;

    address public USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public VENUS = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;

    uint256 mainnetFork;
    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);

        
        user = address(1);
        user1 = address(2);
        user2 = address(3);
        user3 = address(4);
        user4 = address(5);
        admin = address(6);

        recipient = address(7);
        initialCode = address(8);
        owner = address(9);

        vm.startPrank(owner);

        Recharge rechargeImpl = new Recharge();
        ERC1967Proxy rechargeProxy = new ERC1967Proxy(
            address(rechargeImpl),
            abi.encodeCall(rechargeImpl.initialize,(admin, recipient, initialCode))
        );
        recharge = Recharge(payable(address(rechargeProxy)));
        vm.stopPrank();
    }

    function test_referral() public {
        // ---------- 正确绑定 initialCode ----------
        vm.startPrank(user1);
        recharge.referral(initialCode);
        vm.stopPrank();

        (address recommender,,,,, )= recharge.userInfo(user1);
        assertEq(recommender, initialCode);

        // ---------- 错误情况测试 ----------

        // 1. 推荐自己
        vm.startPrank(user2);
        vm.expectRevert(bytes("INVALID_RECOMMENDER."));
        recharge.referral(user2);
        vm.stopPrank();

        // 2. 推荐地址为 0
        vm.startPrank(user2);
        vm.expectRevert(bytes("ZERO_ADDRESS."));
        recharge.referral(address(0));
        vm.stopPrank();

        // 3. 推荐者不是 initialCode 且没有上级
        // user3 没有绑定过 recommender
        vm.startPrank(user2);
        vm.expectRevert(bytes("RECOMMENDATION_IS_REQUIRED_REFERRAL."));
        recharge.referral(user3);
        vm.stopPrank();

        // 4. 用户已经绑定过 recommender
        vm.startPrank(user1);
        vm.expectRevert(bytes("INVITER_ALREADY_EXISTS."));
        recharge.referral(initialCode);
        vm.stopPrank();
    }

    function setRatio_utils() internal {
        // address  public user; = 40
        // address  public user1; = 20;
        // address  public user2; = 10;
        // address  public user3; = 10;

        vm.startPrank(admin);
        recharge.setAwardRatio(user3, 10);
        recharge.setAwardRatio(user2, 10);
        recharge.setAwardRatio(user1, 20);
        recharge.setAwardRatio(user, 40);
        vm.stopPrank();
    }

    function excute_referral(address _recommender, address _user) internal{
        vm.startPrank(_user);
        recharge.referral(_recommender);
        vm.stopPrank();
    }

    function referral_utils() internal{
        excute_referral(initialCode, user);
        excute_referral(user, user1);
        excute_referral(user1, user2);
        excute_referral(user2, user3);
        excute_referral(user3, user4);
    }

    function test_singleRecharge() public {
        setRatio_utils();
        referral_utils();

        deal(USDT, user4, 500e18);
        vm.startPrank(user4);
        IERC20(USDT).approve(address(recharge), 500e18);
        recharge.singleRecharge(Enum.NodeType.envoy);
        vm.stopPrank();
        //initialCode 0
        (
            ,,,,uint256 awardInitialCode,
        ) = recharge.userInfo(initialCode);
        assert(awardInitialCode == 0);
        //user 40
        (
            address recommender,
            Enum.NodeType nodeType,
            uint256 referralNum,
            uint256 performance,
            uint256 award,
        ) = recharge.userInfo(user);

        assertEq(recommender, initialCode);
        assert(nodeType == Enum.NodeType.invalid);
        assertEq(referralNum, 4); 
        assertEq(performance, 500e18);    
        assertEq(award, 100e18);

        // user1 20% - 10% = 10%
        (
            ,,
            uint256 referralNum1,
            uint256 performance1,
            uint256 award1,
        ) = recharge.userInfo(user1);        
        assertEq(referralNum1, 3); 
        assertEq(performance1, 500e18);    
        assertEq(award1, 50e18);

        //user2 10% - 10% = 0
        (
            ,,,,uint256 award2,
        ) = recharge.userInfo(user2);  
        assertEq(award2, 0);

        //user3 10% - 0 = 10%
        (
            ,,,,uint256 award3,
        ) = recharge.userInfo(user3);  
        assertEq(award3, 50e18);

        //user4
        (
            ,
            Enum.NodeType nodeType4,
            ,,,
        ) = recharge.userInfo(user4);
        assert(nodeType4 == Enum.NodeType.envoy);

        (,,,,,,Enum.RecordAward[] memory recordAwards) = recharge.getUserInfo(user);
        recordAwards[0].user = user4;
        recordAwards[0].amount = 100e18;

        uint256 num = recharge.getAddrCollectionLength();
        assertEq(num, 5);

        Enum.DirectInfo[] memory infos = recharge.getDirectReferralInfo(user3);
        assertEq(infos[0].user, user4);
        assert(infos[0].nodeType == Enum.NodeType.envoy);
        assertEq(infos[0].performance, 0);
    }
}