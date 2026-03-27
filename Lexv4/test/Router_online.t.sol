// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Router} from "../src/Router.sol";
// import {Queue} from "../src/Queue.sol";

// contract RouterTest is Test{
//     Router  router;
//     Queue   queue;
//     // address user;
//     // address owner;
//     // address lex;
//     address admin;
//     uint256 mainnetFork;

//     function setUp() public {
//         mainnetFork = vm.createFork(vm.envString("rpc_url"));
//         vm.selectFork(mainnetFork);
//         router = Router(0x078611fe3180271C4AdD917924c781f347eD71C3);
//         queue = Queue(payable(0x4DFdF40117039A5caeeD9A9a13eF1453e2697314));
//         admin = queue.admin();
//         // user = 0xB964E25082D850385bb37CA50a9740D3B6BBDafD;
//         // lex = 0x9994dDf98fDb172E3d56826918538806b2166955;
//         // owner = (0xd23bE199Ba3560F36c1311C0115AA48A5dd57CC8);
//         // upgrade();
//     }

//     // function upgrade() internal{
//     //     vm.startPrank(owner);
//     //     Queue impl = new Queue();
//     //     bytes memory data= "";
//     //     queue.upgradeToAndCall(address(impl), data);
//     //     vm.stopPrank();

//     // }

//     // function test_stake() public {
//     //     vm.startPrank(user);
//     //     IERC20(lex).approve(address(router), 1000e18);
//     //     router.stake(1000e18, 2);
//     //     vm.stopPrank();
//     // }

//     function test_fomo() public{
//         (
//             ,
//             address[21] memory lastQualified,
//             uint256 count,
//             uint256 poolBalance
//         ) = router.getFomoInfo();

//         address fomo0 = lastQualified[0];
//         console.log("Issue amount:", poolBalance * 40 / 100);
//         console.log("Count:", count);
//         vm.startPrank(admin);
//         queue.drawFomoRewards();
//         vm.stopPrank();
//         (, uint256 amount) = router.getFomoAwardsInfo(fomo0);
//         console.log("Fomo award:", amount);
//     }
//     // 4.720000000000000000
//     // 0.429090909090909090
// }