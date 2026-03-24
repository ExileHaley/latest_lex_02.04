// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

//导入要使用的接口
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Models} from "../src/libraries/Models.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Tether} from "../src/mock/Tether.sol";

contract NodeDividendsTest is Test{
    NodeDividends nodeDividends;
    address USDT;
    address lex;
    address treasuryLiquidity;
    address node_test_user0;
    address node_test_user1;
    address nodeDividendsV1;

    address owner;
    address admin;

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("rpc_url"));
        vm.selectFork(mainnetFork);
        node_test_user0 = 0x57813A9194080874cAC554166A833a73c2B80DDa;
        node_test_user1 = 0x2eB038d513a8C305fE5E001C6Aca977142D921A8;
        nodeDividendsV1 = 0x285Ca769Ab57CBB623513921C9a9B3a8fd8F936A;
        USDT = 0x153bB8E0E6b2fC7326c4Db9172d05b6e5f3BB98C;

        owner = address(1);
        admin = address(2);
        lex = address(3);
        treasuryLiquidity = address(4);

        vm.startPrank(owner);
        deployNodeDividends();
        nodeDividends.setAddrConfig(treasuryLiquidity);
        _add_nodeDividends_test_data();
        
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
            abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeDividendsV1, admin, address(USDT)))
        );
        nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
    }

    function _add_nodeDividends_test_data() internal{
        vm.startPrank(owner);
        address[] memory addrs = new address[](2);
        addrs[0] = node_test_user0;
        addrs[1] = node_test_user1;
        nodeDividends.batchAdd(addrs);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _lex_updateFarm_tax_utils(uint256 amount) internal {
        deal(USDT, address(nodeDividends), amount);
        vm.startPrank(lex);
        nodeDividends.updateFarm(Models.Source.TAX_FEE, amount);
        vm.stopPrank();
    }

    function _lex_updateFarm_profit_utils(uint256 amount) internal {
        deal(USDT, address(nodeDividends), amount);
        vm.startPrank(lex);
        nodeDividends.updateFarm(Models.Source.PROFIT_FEE, amount);
        vm.stopPrank();
    }

    function _treasuryLiquidity_updateFarm_utils(uint256 amount) internal {
        deal(USDT, address(nodeDividends), amount);
        vm.startPrank(treasuryLiquidity);
        nodeDividends.updateFarm(Models.Source.STAKE_FEE, amount);
        vm.stopPrank();
    }

    function _claim_utils(address user) internal{
        vm.startPrank(user);
        nodeDividends.claim();
        vm.stopPrank();
    }

    function _console_log() internal view{
        uint256 staking_user0 = nodeDividends.getUserStaking(node_test_user0);
        uint256 staking_user1 = nodeDividends.getUserStaking(node_test_user1);
        console.log("Staking for user0:",staking_user0 / 1e18);
        console.log("Staking for user1:",staking_user1 / 1e18);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_profit_fee_award() public {
        _console_log();
        _lex_updateFarm_profit_utils(100000e18);
        _claim_utils(node_test_user0);

        uint256 awardProfitFee0 = nodeDividends.getProfitFeeAward(node_test_user0);
        uint256 award0 = nodeDividends.getUserAward(node_test_user0);
        console.log("User award:",award0 / 1e18);
        console.log("User profit fee award:",awardProfitFee0 / 1e18);
        assertEq(awardProfitFee0, 0);
        assertEq(award0, 0);
    }

    function test_tax_fee_award() public {
        _lex_updateFarm_tax_utils(100000e18);

        uint256 awardTaxFee0 = nodeDividends.getTaxFeeAward(node_test_user0);
        uint256 award0 = nodeDividends.getUserAward(node_test_user0);
        console.log("User award:",award0 / 1e18);
        console.log("User tax fee award:",awardTaxFee0 / 1e18);

        _claim_utils(node_test_user0);
        _lex_updateFarm_tax_utils(100000e18);
        uint256 awardTaxFee1 = nodeDividends.getTaxFeeAward(node_test_user0);
        uint256 award1 = nodeDividends.getUserAward(node_test_user0);
        assertEq(awardTaxFee1, 0);
        assertEq(award1, 0);
    }    

    function test_total_fee_award() public {
        _treasuryLiquidity_updateFarm_utils(1000000e18);
        // assertEq(left, right);
        uint256 award0 = nodeDividends.getUserAward(node_test_user0);
        assertEq(award0, 5000e18 * 2);
        _claim_utils(node_test_user0);
        assertEq(nodeDividends.getUserAward(node_test_user0), 0);
        _lex_updateFarm_profit_utils(100e18);
        uint256 total = nodeDividends.getUserAward(node_test_user0);
        uint256 profitFee = nodeDividends.getProfitFeeAward(node_test_user0);
        console.log("total award:", total);
        assertEq(total, profitFee);
    }

    
}