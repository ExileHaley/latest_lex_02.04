// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Types } from "./libraries/Types.sol";

interface ILex {
    function specialWithdraw(uint256 amount) external;
}
contract Treasury is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public constant USDT =
        0x55d398326f99059fF775485246999027B3197955;
    // 质押类型
    struct StakePlan {
        uint32 duration;
        uint32 claimInterval;
        uint64 rate;      // 1e18 精度
        uint32 fee;
    }
    mapping(uint8 => StakePlan) public stakePlans;
    // 订单
    struct Order {
        uint128 amount;
        uint128 claimed;
        uint32  startTime;
        uint8   stakeIndex;
        uint8   status;

        uint32  createdAt;

        // ===== 冻结模型 =====
        uint128 frozenReward;      // 冻结总额
        uint128 frozenClaimed;     // 已从冻结池领取
        uint32  freezeStart;       // 本轮冻结开始时间
        uint32  freezeRound;       // 冻结轮次
    }
    mapping(address => Order[]) public userOrders;
    address public token;
    address public wallet;

    // ===== pause 系统 =====
    bool public paused;
    uint32 public pauseTime;
    uint32 public pauseRound;
    uint64 public releaseRatePerDay; // 1e15 = 0.1%

    function _authorizeUpgrade(address newImplementation)internal view override onlyOwner{}

    function initialize(address _token) public initializer {
        __Ownable_init(_msgSender());
        token = _token;

        releaseRatePerDay = 1e15; // 冻结释放 0.1%

        uint256 day = 1 days;

        // ===================== 质押计划初始化 =====================

        // 0 = 1天  日化 0.3%
        stakePlans[0] = StakePlan({
            duration: 1 days,
            claimInterval: 1 days,
            rate: uint64(3e15 / day),   // 0.3% / day → 秒利率
            fee: 0
        });

        // 1 = 15天  日化 0.6%
        stakePlans[1] = StakePlan({
            duration: 15 days,
            claimInterval: 15 days,
            rate: uint64(6e15 / day),
            fee: 0
        });

        // 2 = 30天  日化 1.2%
        stakePlans[2] = StakePlan({
            duration: 30 days,
            claimInterval: 15 days,
            rate: uint64(12e15 / day),
            fee: 0
        });

        // 3 = 90天  日化 1.3%
        stakePlans[3] = StakePlan({
            duration: 90 days,
            claimInterval: 10 days,
            rate: uint64(13e15 / day),
            fee: 0
        });
    }
    // ================= PAUSE =================

    function pause() external onlyOwner {
        require(!paused, "Already paused");

        paused = true;
        pauseTime = uint32(block.timestamp);
        pauseRound += 1;
    }

    function resume() external onlyOwner {
        require(paused, "Not paused");
        paused = false;
    }

    // ================= STAKE =================
    function stake(address user, uint256 amount, uint8 stakeIndex) external {
        addLiquidity(amount);
        Order memory order = Order({
            amount: uint128(amount),
            claimed: 0,
            startTime: uint32(block.timestamp),
            stakeIndex: stakeIndex,
            status: 0,
            createdAt: uint32(block.timestamp),
            frozenReward: 0,
            frozenClaimed: 0,
            freezeStart: 0,
            freezeRound: 0
        });

        userOrders[user].push(order);
    }

    // ================= CLAIM =================
    // function claim(address user, uint256 index)external returns (uint256) {
    //     _applyPause(user, index);

    //     Order storage order = userOrders[user][index];
    //     require(order.status == 0, "Inactive");

    //     uint256 reward;

    //     if (paused && order.freezeRound == pauseRound) {

    //         uint256 released = _releasedAmount(order);

    //         reward = released > order.frozenClaimed
    //             ? released - order.frozenClaimed
    //             : 0;

    //         require(reward > 0, "No frozen reward");

    //         order.frozenClaimed += uint128(reward);

    //     } else {

    //         reward = _calculateNormal(order, block.timestamp);

    //         reward = reward > order.claimed
    //             ? reward - order.claimed
    //             : 0;

    //         require(reward > 0, "No reward");

    //         order.claimed += uint128(reward);
    //     }

    //     TransferHelper.safeTransfer(USDT, user, reward);
    //     return reward;
    // }

    function claim(address user, uint256 orderIndex, Types.Send[] memory sendInfos) external{
        // 1.提取收益时首先通过claimInterval判断是否到收益领取时间点，在到时间点其24小时内可以领取，否则等下一个周期或者到期24小时内领取
        // 2.
    }

    // ================= UNSTAKE =================
    function unstake(address user, uint256 index) external {
        _applyPause(user, index);

        Order storage order = userOrders[user][index];
        require(order.status == 0, "Not active");

        StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 principal = order.amount;

        uint256 startTime = order.startTime;
        uint256 endTime = startTime + plan.duration;
        uint256 hardStop = startTime + 365 days;

        // =====================================================
        // 1️⃣ 未到期禁止赎回
        // =====================================================
        require(block.timestamp >= endTime, "Not matured");

        // =====================================================
        // 2️⃣ 超过12个月永久锁死
        // =====================================================
        require(block.timestamp <= hardStop, "Permanently expired");

        // =====================================================
        // 3️⃣ 计算已领取利润（含冻结）
        // =====================================================
        uint256 alreadyClaimed = uint256(order.claimed) + uint256(order.frozenClaimed);

        // =====================================================
        // 4️⃣ 利润统一回收90%
        // =====================================================
        uint256 profitPenalty = alreadyClaimed * 90 / 100;

        // =====================================================
        // 5️⃣ 本金惩罚计算（三阶段）
        // =====================================================
        uint256 principalPenalty;
        uint256 t24 = endTime + 1 days;

        if (block.timestamp <= t24) {
            // 阶段2：到期 ~ 24小时内，本金扣10%
            principalPenalty = principal * 10 / 100;
        } else {
            // 阶段3：超过24小时
            // 基础10%
            principalPenalty = principal * 10 / 100;

            // 超过24小时后的整天数
            uint256 overdueDays = (block.timestamp - t24) / 1 days;
            if (overdueDays > 0) {
                uint256 extraPenalty = principal * overdueDays * 10 / 100;
                principalPenalty += extraPenalty;
            }
        }

        // =====================================================
        // 6️⃣ 汇总总扣除
        // =====================================================
        uint256 totalPenalty = profitPenalty + principalPenalty;

        uint256 payout;
        if (totalPenalty >= principal) {
            payout = 0;
        } else {
            payout = principal - totalPenalty;
        }

        // =====================================================
        // 7️⃣ 更新状态
        // =====================================================
        order.status = 1;

        // =====================================================
        // 8️⃣ 转账
        // =====================================================

        if(principalPenalty > 0 || payout > 0){
            uint256 amountToken = getAmountOut(principalPenalty + payout + 5e18);
            _exchange(token, USDT, amountToken, address(this));
            ILex(token).specialWithdraw(amountToken);
        }

        // 本金手续费打到 treasury
        if (principalPenalty > 0) {
            TransferHelper.safeTransfer(USDT, wallet, principalPenalty);
        }

        // 用户拿剩余本金 + 10%利润
        if (payout > 0) {
            TransferHelper.safeTransfer(USDT, user, payout);
        }
    }

    // ===================internal/external view ==================================
    function getUserOrders(address user)external view returns (Order[] memory){
        return userOrders[user];
    }
    
    //普通收益计算
    function calculateNormal(address user, uint256 orderIndex)public view returns (uint256){
        Order memory order = userOrders[user][orderIndex];
        StakePlan memory plan = stakePlans[order.stakeIndex];

        uint256 endTime =
            uint256(order.startTime) + plan.duration;

        uint256 toTime = block.timestamp;
        if (toTime > endTime) {
            toTime = endTime;
        }

        if (toTime <= order.startTime) return 0;

        uint256 elapsed = toTime - order.startTime;

        return uint256(order.amount)
            * elapsed
            * plan.rate
            / 1e18;
    }

    function calculateReward(address user, uint256 orderIndex)public view returns (uint256){
        Order memory order = userOrders[user][orderIndex];

        if (order.status != 0) return 0;

        if (paused && order.freezeRound == pauseRound) {

            uint256 released = releasedAmount(user, orderIndex);

            return released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;
        }

        uint256 total = calculateNormal(user, orderIndex);

        return total > order.claimed
            ? total - order.claimed
            : 0;
    }
    
    function releasedAmount(address user, uint256 orderIndex)public view returns (uint256){
        Order memory order = userOrders[user][orderIndex];
        if (order.frozenReward == 0) return 0;
        uint256 daysPassed =
            (block.timestamp - order.freezeStart) / 1 days;
        uint256 ratio =
            daysPassed * releaseRatePerDay;
        if (ratio > 1e18) ratio = 1e18;
        return uint256(order.frozenReward) * ratio / 1e18;
    }

    function _applyPause(address user, uint256 index) internal {
        Order storage order = userOrders[user][index];

        if (!paused) return;
        if (order.status != 0) return;
        if (order.createdAt >= pauseTime) return;
        if (order.freezeRound == pauseRound) return;

        uint256 earned = calculateNormal(user, index);
        uint256 unclaimed = earned > order.claimed
            ? earned - order.claimed
            : 0;

        order.frozenReward += uint128(unclaimed);
        order.freezeStart = pauseTime;
        order.freezeRound = pauseRound;
    }

    // ======================internal utils==================================
    function _exchange(address fromToken, address toToken, uint256 fromAmount, address to) private{
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        
        // 执行 token → USDT 的交换
        IERC20(fromToken).approve(address(pancakeRouter), fromAmount);
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            fromAmount,
            0,
            path,
            to,
            block.timestamp + 30
        );
    }

    function addLiquidity(uint256 amountUSDT) internal  {
        uint256 oneHalf = amountUSDT / 2;
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        _exchange(USDT, token, oneHalf, address(this));
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

    function getAmountOut(uint256 amountUsdt) public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = token;
        return pancakeRouter.getAmountsOut(amountUsdt, path)[1];
    }

    
}