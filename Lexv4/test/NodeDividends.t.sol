// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

//导入要使用的接口
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Models} from "../src/libraries/Models.sol";
import {NodeDividends} from "../src/NodeDividends.sol";

contract NodeDividendsTest is Test{
    NodeDividends nodeDividends;
    address treasuryLiquidity;
    address lex;
    address USDT;
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
        lex = 0x9994dDf98fDb172E3d56826918538806b2166955;
        USDT = 0x153bB8E0E6b2fC7326c4Db9172d05b6e5f3BB98C;
        treasuryLiquidity = 0xA4cC46267E290eb4016Ad9d183e77c935860B9B9;

        owner = address(1);
        admin = address(2);

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
        vm.startPrank(lex);
        nodeDividends.updateFarm(Models.Source.TAX_FEE, amount);
        vm.stopPrank();
    }

    function _lex_updateFarm_profit_utils(uint256 amount) internal {
        vm.startPrank(lex);
        nodeDividends.updateFarm(Models.Source.PROFIT_FEE, amount);
        vm.stopPrank();
    }

    function _treasuryLiquidity_updateFarm_utils(uint256 amount) internal {
        vm.startPrank(treasuryLiquidity);
        nodeDividends.updateFarm(Models.Source.STAKE_FEE, amount);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_profit_fee_award() public {}

    function test_tax_fee_award() public {}    

    function test_stake_fee_award() public{}

    function test_total_fee_award() public {}

    function test_claim() public {}
}