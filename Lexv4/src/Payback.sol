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
    uint256 public dividendsRate;

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
        dividendsRate = 70;
    }

    function _harvest(User storage u) internal {
        if(u.staking == 0) return;
        uint256 reward = (u.staking * accRewardPerShare / ACC) - u.debt;
        if(reward > 0){
            u.pending += reward;
        }
    }

    function setDividendsRate(uint256 _dividendsRate) external onlyAdmin{
        dividendsRate = _dividendsRate;
    }

    function add(address user, uint256 amount) external onlyAdmin {
        User storage u = userInfo[user];
        _harvest(u);
        u.staking += amount;
        totalStaking += amount;
        u.debt = u.staking * accRewardPerShare / ACC;
    }

    function reduce(address user, uint256 amount) external onlyAdmin {

        User storage u = userInfo[user];

        require(u.staking >= amount,"exceed");

        _harvest(u);

        u.staking -= amount;
        totalStaking -= amount;

        u.debt = u.staking * accRewardPerShare / ACC;
    }

    function updateFarm(uint256 amount) external onlyFarm {
        uint256 dividendsAmount = amount * dividendsRate / 100;

        if(totalStaking == 0) return;

        accRewardPerShare += dividendsAmount * ACC / totalStaking;
    }

    function getUserAward(address user) public view returns(uint256){

        User memory u = userInfo[user];

        uint256 reward = (u.staking * accRewardPerShare / ACC) - u.debt;

        return u.pending + reward;
    }

    function claim() external {

        User storage u = userInfo[msg.sender];

        require(u.staking > 0,"out");

        _harvest(u);

        uint256 reward = u.pending;

        require(reward > 0,"no reward");

        uint256 usdtAmount = _getAmountsOut(reward);

        uint256 sendLeo;

        if(u.usdtValue + usdtAmount >= u.staking){

            uint256 remain = u.staking - u.usdtValue;

            sendLeo = reward * remain / usdtAmount;

            u.usdtValue = u.staking;

            totalStaking -= u.staking;

            u.staking = 0;
            u.debt = 0;
            u.pending = 0;

        }else{

            sendLeo = reward;

            u.usdtValue += usdtAmount;

            u.pending = 0;

            u.debt = u.staking * accRewardPerShare / ACC;
        }

        TransferHelper.safeTransfer(leo,msg.sender,sendLeo);
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

    function emergencyWithdraw(address _token, uint256 _amount, address _to)
        external
        onlyAdmin
    {   
        TransferHelper.safeTransfer(_token, _to, _amount);
    }

}
