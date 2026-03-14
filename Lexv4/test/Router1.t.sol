// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Router} from "../src/Router.sol";

// contract RouterTest is Test{
//     Router public router;

//     address public user;
//     address public USDT;
//     uint256 mainnetFork;

//     function setUp() public {
//         mainnetFork = vm.createFork(vm.envString("rpc_url"));
//         vm.selectFork(mainnetFork);
        
//         router = Router((0xE00c4A5998b08135C650D056646c0be4bB9B362b));
//         USDT = address(0x6D1F1D97D01D8879451fE11Cd8c848a9fe4F8424);

//         user = address(0x9a854F2b62930aAd1924738563C5039cE52E2Dd1);
//     }

//     function _stake_utils(address _token, address _user, uint256 _amount, uint8 _stakeIndex) internal{
//         vm.startPrank(_user);
//         IERC20(_token).approve(address(router), _amount);
//         router.stake(_amount, _stakeIndex);
//         vm.stopPrank();
//     }

//     function test_stake() public {
//         _stake_utils(USDT, user, 100e18, 2);
//     }
// }