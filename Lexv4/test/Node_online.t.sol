// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {NodeDividends} from "../src/NodeDividends.sol";

// contract NodeDividendsTest is Test{
//     NodeDividends public nodeDividends;
//     address public owner;
//     address public user;

//     address public USDT;
//     uint256 mainnetFork;

//     function setUp() public {
//         mainnetFork = vm.createFork(vm.envString("rpc_url"));
//         vm.selectFork(mainnetFork);
        
//         nodeDividends = NodeDividends((0xeA0e347786E075c37cC35530c41708a8deff5BB0));
//         USDT = address(0x153bB8E0E6b2fC7326c4Db9172d05b6e5f3BB98C);
//         owner = address(0xd23bE199Ba3560F36c1311C0115AA48A5dd57CC8);
//         user = address(0x57813A9194080874cAC554166A833a73c2B80DDa);
//         upgrade();
//     }


//     function upgrade() internal{
//         vm.startPrank(owner);

//         NodeDividends impl = new NodeDividends();
//         bytes memory data= "";
//         nodeDividends.upgradeToAndCall(address(impl), data);

//         vm.stopPrank();
//     }


//     function test_claim() public {
//         deal(USDT, address(nodeDividends), 100e18);
//         vm.startPrank(user);
//         uint256 beforeClaim = nodeDividends.getUserAward(user);
//         uint256 balanceOfNode = IERC20(USDT).balanceOf(address(nodeDividends));
//         nodeDividends.claim();
//         uint256 afterClaim = nodeDividends.getUserAward(user);
//         vm.stopPrank();
        
//         console.log("NodeDividends before claim data:", beforeClaim);
//         console.log("NodeDividends balance:", balanceOfNode);
//         console.log("NodeDividends after claim data:", afterClaim);
//     }
    
// }