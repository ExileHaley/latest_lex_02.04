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
        uint32 fee;              //本金赎回手续费
    }
    //0代表1天，1代表15天，2代表30天，3代表90天
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
    function claim(address user, uint256 orderIndex) external returns(uint256){
        Order storage order = userOrders[user][orderIndex];
        require(order.status != 1, "Already unstaked.");

        StakePlan memory plan = stakePlans[order.stakeIndex];

        // 提取周期控制
        if(plan.claimInterval > 0){
            uint256 elapsed = block.timestamp - order.startTime;
            require(elapsed >= plan.claimInterval, "Too early to claim.");

            // 当前属于第几个周期
            uint256 periods = elapsed / plan.claimInterval;
            uint256 windowStart = order.startTime + periods * plan.claimInterval;
            uint256 windowEnd   = windowStart + 1 days; // 24h 提取窗口
            require(block.timestamp >= windowStart && block.timestamp <= windowEnd, "Not in claim window.");
        }

        uint256 award = calculateReward(user, orderIndex);
        require(award > 0, "No reward to claim.");

        //TODO 转账占位
        TransferHelper.safeTransfer(USDT, address(this), award);

        order.claimed += uint128(award);

        return award;
    }

    //赎回订单
    function unstake(address user, uint256 orderIndex) external {
        Order storage order = userOrders[user][orderIndex];
        require(order.status == 0, "Not active");

        StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 principal = order.amount;
        uint256 claimed = order.claimed;

        uint256 principalFee = principal * plan.fee / 100; 
        uint256 reclaimedClaimed = claimed * 90 / 100; // 已领取收益回收部分，仅用于计算

        // 处理减法可能出现的负数情况
        uint256 payout;
        if (principalFee + reclaimedClaimed >= principal) {
            payout = 0;
        } else {
            payout = principal - principalFee - reclaimedClaimed;
        }

        // 更新状态
        order.status = 1; // unstaked
        userTotalStaked[user] -= principal;

        // 给用户转账
        if(payout > 0){
            TransferHelper.safeTransfer(USDT, user, payout);
        }

        // 手续费转合约/treasury
        if(principalFee > 0){
            // TODO: 改成 treasury 地址
            TransferHelper.safeTransfer(USDT, address(this), principalFee);
        }
    }



    //修改订单，重质押
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external {
        Order storage order = userOrders[user][orderIndex];
        // 订单必须是 active
        require(order.status == 0, "Order not active");
        // 新的 stakeIndex 必须大于等于当前订单
        require(newStakeIndex >= order.stakeIndex, "Cannot downgrade stake plan");
        // 校验 stakePlan 有效
        StakePlan memory newPlan = stakePlans[newStakeIndex];
        require(newPlan.duration > 0, "Invalid stake plan");
        // 重置订单
        order.stakeIndex = newStakeIndex;
        order.startTime = uint32(block.timestamp);
        // 注意：本金保持不变，claimed 保留，未提取收益累积

    }

    //计算单个订单的收益
    function calculateReward(address user, uint256 orderIndex) public view returns (uint256) {
        Order memory order = userOrders[user][orderIndex];
        
        // 如果订单不是 active 状态，收益为 0
        if (order.status != 0) {
            return 0;
        }

        StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 endTime = uint256(order.startTime) + plan.duration;

        // 计算截止时间，不超过订单到期时间
        uint256 currentTime = block.timestamp;
        if (currentTime > endTime) {
            currentTime = endTime;
        }

        // 已过去时间
        uint256 elapsed = currentTime - order.startTime;
        if (elapsed == 0) return 0;

        // 按秒利率计算收益
        // 注意 rate 精度，需要与 amount 对应
        uint256 totalEarned = uint256(order.amount) * elapsed * plan.rate / 1e18;

        // 扣除已提取的收益
        if (totalEarned <= order.claimed) {
            return 0;
        }
        return totalEarned - order.claimed;
    }


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