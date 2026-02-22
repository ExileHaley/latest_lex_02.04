// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public constant USDT =
        0x55d398326f99059fF775485246999027B3197955;

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

    struct StakePlan {
        uint32 duration;
        uint32 claimInterval;
        uint64 rate;      // 1e18 精度
        uint32 fee;
    }

    mapping(uint8 => StakePlan) public stakePlans;
    mapping(address => Order[]) public userOrders;
    mapping(address => uint256) public userTotalStaked;

    address public token;

    // ===== pause 系统 =====
    bool public paused;
    uint32 public pauseTime;
    uint32 public pauseRound;
    uint64 public releaseRatePerDay; // 1e15 = 0.1%

    // ================= UUPS =================
    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
        onlyOwner
    {}

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
            claimInterval: 1 days,
            rate: uint64(6e15 / day),
            fee: 0
        });

        // 2 = 30天  日化 1.2%
        stakePlans[2] = StakePlan({
            duration: 30 days,
            claimInterval: 1 days,
            rate: uint64(12e15 / day),
            fee: 0
        });

        // 3 = 90天  日化 1.3%
        stakePlans[3] = StakePlan({
            duration: 90 days,
            claimInterval: 1 days,
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

    // ================= INTERNAL FREEZE =================

    function _applyPause(address user, uint256 index) internal {
        Order storage order = userOrders[user][index];

        if (!paused) return;
        if (order.status != 0) return;
        if (order.createdAt >= pauseTime) return;
        if (order.freezeRound == pauseRound) return;

        uint256 earned = _calculateNormal(order, pauseTime);
        uint256 unclaimed = earned > order.claimed
            ? earned - order.claimed
            : 0;

        order.frozenReward += uint128(unclaimed);
        order.freezeStart = pauseTime;
        order.freezeRound = pauseRound;
    }

    function _releasedAmount(Order memory order)
        internal
        view
        returns (uint256)
    {
        if (order.frozenReward == 0) return 0;

        uint256 daysPassed =
            (block.timestamp - order.freezeStart) / 1 days;

        uint256 ratio =
            daysPassed * releaseRatePerDay;

        if (ratio > 1e18) ratio = 1e18;

        return uint256(order.frozenReward) * ratio / 1e18;
    }

    // ================= STAKE =================

    function stake(address user, uint256 amount, uint8 stakeIndex) external {

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
        userTotalStaked[user] += amount;
    }

    // ================= CLAIM =================

    function claim(address user, uint256 index)
        external
        returns (uint256)
    {
        _applyPause(user, index);

        Order storage order = userOrders[user][index];
        require(order.status == 0, "Inactive");

        uint256 reward;

        if (paused && order.freezeRound == pauseRound) {

            uint256 released = _releasedAmount(order);

            reward = released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;

            require(reward > 0, "No frozen reward");

            order.frozenClaimed += uint128(reward);

        } else {

            reward = _calculateNormal(order, block.timestamp);

            reward = reward > order.claimed
                ? reward - order.claimed
                : 0;

            require(reward > 0, "No reward");

            order.claimed += uint128(reward);
        }

        TransferHelper.safeTransfer(USDT, user, reward);
        return reward;
    }

    // ================= UNSTAKE =================

    function unstake(address user, uint256 index) external {

        _applyPause(user, index);

        Order storage order = userOrders[user][index];
        require(order.status == 0, "Not active");

        require(
            !paused || order.createdAt >= pauseTime,
            "Old order locked"
        );

        StakePlan memory plan = stakePlans[order.stakeIndex];

        uint256 principal = order.amount;
        uint256 principalFee = principal * plan.fee / 100;

        order.status = 1;
        userTotalStaked[user] -= principal;

        uint256 payout = principal - principalFee;

        TransferHelper.safeTransfer(USDT, user, payout);
    }

    // ================= REWARD CALC =================

    function calculateReward(address user, uint256 index)
        public
        view
        returns (uint256)
    {
        Order memory order = userOrders[user][index];

        if (order.status != 0) return 0;

        if (paused && order.freezeRound == pauseRound) {

            uint256 released = _releasedAmount(order);

            return released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;
        }

        uint256 total = _calculateNormal(order, block.timestamp);

        return total > order.claimed
            ? total - order.claimed
            : 0;
    }

    function _calculateNormal(Order memory order, uint256 toTime)
        internal
        view
        returns (uint256)
    {
        StakePlan memory plan = stakePlans[order.stakeIndex];

        uint256 endTime =
            uint256(order.startTime) + plan.duration;

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

    // ================= VIEW =================

    function getUserOrders(address user)
        external
        view
        returns (Order[] memory)
    {
        return userOrders[user];
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
    
}