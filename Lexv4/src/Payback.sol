// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

contract Payback is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    uint256 constant ACC = 1e18;

    address public USDT;
    address public treasuryLiquidity;
    address public lex;
    address public leo;
    address public admin;

    struct User{
        uint256 staking;
        uint256 pending;
        uint256 debt;
        uint256 usdtValue;
    }

    mapping(address => User) public userInfo;

    uint256 public totalStaking;
    uint256 public accRewardPerShare;

    modifier onlyFarm() {
        require(msg.sender == treasuryLiquidity || msg.sender == lex, "Not permit.");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "Not permit.");
        _;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
        onlyOwner
    {}

    function initialize(
        address _USDT,
        address _treasuryLiquidity,
        address _lex,
        address _leo,
        address _admin
    ) public initializer {
        __Ownable_init(_msgSender());
        USDT = _USDT;
        treasuryLiquidity = _treasuryLiquidity;
        lex = _lex;
        leo = _leo;
        admin = _admin;
    }

    function add(address user, uint256 amount) external onlyAdmin {

        User storage u = userInfo[user];

        if(u.staking > 0){
            uint256 pending = (u.staking * accRewardPerShare / ACC) - u.debt;
            u.pending += pending;
        }

        u.staking += amount;
        totalStaking += amount;

        u.debt = u.staking * accRewardPerShare / ACC;
    }

    function reduce(address user, uint256 amount) external onlyAdmin {

        User storage u = userInfo[user];

        require(u.staking >= amount,"exceed");

        uint256 pending = (u.staking * accRewardPerShare / ACC) - u.debt;
        u.pending += pending;

        u.staking -= amount;
        totalStaking -= amount;

        u.debt = u.staking * accRewardPerShare / ACC;
    }

    function updateFarm(uint256 amount) external onlyFarm {

        if(totalStaking == 0) return;

        accRewardPerShare += amount * ACC / totalStaking;
    }

    function getUserAward(address user) public view returns(uint256){

        User memory u = userInfo[user];

        uint256 pending = (u.staking * accRewardPerShare / ACC) - u.debt;

        return u.pending + pending;
    }

    function getUserInfo(address user)
        external
        view
        returns(
            uint256 staking,
            uint256 usdtValue,
            uint256 truthAward
        )
    {
        User memory u = userInfo[user];

        staking = u.staking;
        usdtValue = u.usdtValue;
        truthAward = getUserAward(user);
    }

    function claim() external {

        User storage u = userInfo[msg.sender];

        uint256 reward = (u.staking * accRewardPerShare / ACC) - u.debt;
        reward += u.pending;

        require(reward > 0,"no reward");

        u.pending = 0;
        u.debt = u.staking * accRewardPerShare / ACC;

        uint256 usdtAmount = _getAmountsOut(reward);

        if(u.usdtValue + usdtAmount >= u.staking){

            uint256 remain = u.staking - u.usdtValue;

            uint256 leoNeed = reward * remain / usdtAmount;

            u.usdtValue = u.staking;

            TransferHelper.safeTransfer(leo,msg.sender,leoNeed);

        }else{

            u.usdtValue += usdtAmount;

            TransferHelper.safeTransfer(leo,msg.sender,reward);
        }
    }

    function _getAmountsOut(uint256 amountLeo) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = leo;
        path[1] = USDT;
        return pancakeRouter.getAmountsOut(amountLeo, path)[1];
    }

    function getAmountsOut(uint256 amountLeo) external view returns (uint256) {
        return _getAmountsOut(amountLeo);
    }

    
}