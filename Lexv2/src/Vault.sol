// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";


contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    IUniswapV2Router02 public constant pancakeRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    struct Order {
        uint128 amount;       // 质押本金
        uint128 claimed;      // 已提取收益

        uint32  startTime;    // 质押开始时间

        uint8   stakeIndex;   // 质押类型（不同期限/利率/提取间隔）
        uint8   status;       // 0=active, 1=unstaked, 2=finished
    }

    struct StakePlan {
        uint32 duration;         // 锁仓总时长（秒）
        uint32 claimInterval;    // 每多少秒可提取一次收益
        uint64 rate;             // 秒级利率（可乘 1e18 或 1e6）
    }
    mapping(uint8 => StakePlan) public stakePlans;
    mapping(address => Order[]) userOrders;
    mapping(address => uint256) public userTotalStaked;

    address public token;

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _token
    ) public initializer {
        __Ownable_init(_msgSender());
        token = _token;
    }

    //生成订单
    function stake(address user, uint256 amount, uint8 stakeIndex) external{
        addLiquidity(amount);

        Order memory order = Order({
            amount: uint128(amount),
            claimed: 0,
            startTime: uint32(block.timestamp),
            stakeIndex: stakeIndex,   // 默认计划类型，可通过参数传入
            status: 0        // active
        });

        userOrders[user].push(order);
        userTotalStaked[user] += amount;
    }
    //提取收益
    function claimOrder(address user, uint256 orderIndex) external returns(uint256){
        //提取订单收益，以当前calculateReward为准，另外再订单中记录已提取数量
    }
    function claimReferral(address user, uint256 amount) external {
        //只发送资金，不做校验信任core
    }
    //赎回订单
    function unstake(address user, uint256 orderIndex) external{
        // 用户赎回订单
        // 修改订单状态 order.status = 1/2
        // 扣减用户总质押量 userTotalStaked
        // 可触发返还本金 + 未提取收益
        // 注意点：
        // 判断 订单是否到期（或者允许提前赎回但收取手续费）
        // 更新 userTotalStaked，保持 Vault 数据一致
    }
    //修改订单，重质押
    function restake(address user, uint256 orderIndex, uint256 stakeIndex) external{
        // 职责：
        // 修改已有订单的质押类型（期限/利率/提取间隔）
        // 重置 startTime
        // 判断新 stakeIndex 必须 >= 原 stakeIndex（防止降级）
        // 判断旧订单是否赎回或者到期，到期允许操作，赎回则直接拒绝
        // 注意点：
        // 不改变本金，或者根据需求增加补差价逻辑
        // 可限制操作频率，防止滥用
    }
    //计算单个订单的收益
    function calculateReward(address user, uint256 orderIndex) external view returns (uint256) {}

    // ======================internal==================================
    function _exchange(address fromToken, address toToken, uint256 fromAmount) private{
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        
        // 执行 token → USDT 的交换
        IERC20(fromToken).approve(address(pancakeRouter), fromAmount);
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            fromAmount,
            0,
            path,
            address(this),
            block.timestamp + 30
        );
    }

    function addLiquidity(uint256 amountUSDT) internal  {
        uint256 oneHalf = amountUSDT / 2;
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        _exchange(USDT, token, oneHalf);
        uint256 afterBalance = IERC20(token).balanceOf(address(this));

        uint256 toLiquidityUSDT = amountUSDT - oneHalf;
        uint256 toLiquidityToken = afterBalance - beforeBalance;

        TransferHelper.safeApprove(USDT, address(pancakeRouter), toLiquidityUSDT);
        TransferHelper.safeApprove(token, address(pancakeRouter), toLiquidityToken);
        pancakeRouter.addLiquidity(
            USDT,
            token,
            toLiquidityUSDT,
            toLiquidityToken,
            0,
            0,
            address(this),
            block.timestamp + 30
        );

    }

    function emergencyWithdraw(address _token, uint256 _amount, address _to) external onlyOwner{
        TransferHelper.safeTransfer(_token, _to, _amount);
    }

    function getUserOrders(address user) external view returns(Order[] memory){
        return userOrders[user];
    } 
}