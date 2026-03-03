// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { INodeDividends } from "./interfaces/INodeDividends.sol";
import { IReferrals } from "./interfaces/IReferrals.sol";
import { ILex } from "./interfaces/ILex.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Models } from "./libraries/Models.sol";
import { TreasuryRules } from "./libraries/TreasuryRules.sol";
import { ITreasury } from "./interfaces/ITreasury.sol";

contract Treasury is Initializable, OwnableUpgradeable, UUPSUpgradeable, ITreasury{
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    mapping(uint8 => TreasuryRules.StakePlan) public stakePlans;
    mapping(address => TreasuryRules.Order[]) public userOrders;

    address public token;
    address public wallet;
    address public admin;
    
    address public referrals;
    address public nodeDividends;
    address public queue;
    address public USDT;

    bool   public paused;
    uint32 public pauseTime;
    uint32 public pauseRound;
    uint64 public releaseRatePerDay; // 1e15 = 0.1%

    function _authorizeUpgrade(address newImplementation)internal view override onlyOwner{}

    function initialize(address _admin, address _token, address _wallet, address _USDT) public initializer {
        __Ownable_init(_msgSender());
        admin = _admin;
        token = _token;
        wallet = _wallet;
        USDT = _USDT;
        releaseRatePerDay = 1e15; // 冻结释放 0.1%
        uint256 day = 1 days;

        stakePlans[0] = TreasuryRules.StakePlan({
            duration: 1 days,
            claimInterval: 1 days,
            rate: uint64(3e15 / day)
        });
        stakePlans[1] = TreasuryRules.StakePlan({
            duration: 15 days,
            claimInterval: 15 days,
            rate: uint64(6e15 / day)
        });
        stakePlans[2] = TreasuryRules.StakePlan({
            duration: 30 days,
            claimInterval: 15 days,
            rate: uint64(12e15 / day)
        });
        stakePlans[3] = TreasuryRules.StakePlan({
            duration: 90 days,
            claimInterval: 10 days,
            rate: uint64(13e15 / day)
        });
    }

    modifier onlyQueue() {
        require(queue == msg.sender, "Not permit.");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "Not permit.");
        _;
    }

    function setAddrConfig(
        address _referrals,
        address _nodeDividends,
        address _queue
    ) external onlyOwner{
        referrals = _referrals;
        nodeDividends = _nodeDividends;
        queue = _queue;
    }


    function pause() external onlyQueue{
        require(!paused, "Already paused");
        paused = true;
        pauseTime = uint32(block.timestamp);
        pauseRound += 1;
    }

    function resume() external  onlyQueue{
        require(paused, "Not paused");
        paused = false;
    }
    /// @notice 添加流动性并组成订单
    function stake(address user, uint256 amount, uint8 stakeIndex) external onlyQueue{
        addLiquidity(amount);
        TreasuryRules.Order memory order = TreasuryRules.Order({
            amount: uint128(amount),
            claimed: 0,
            claimedPeriods:0,
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

    // 1. 收益提取首先要看StakePlan中的claimInterval，
    // 1.1 startTime+claimInterval，到达这个时间点24小时内可以领取，24小时后不可以领取只能等待到期
    // 1.2 到期后超过24小时不能领取收益，只能走unstake和restake
    // 1.3 stakeIndex == 0 赎回本金和提取收益都是100%到账，且不向上分发收益,不受冻结影响
    // 2. 已赎回的订单不允许提取，且应该在赎回的方法中将收益置为0
    // 3. 如果当是冻结状态：
    // 3.1 那么就将冻结前订单已产生未提取收益作为总量住每天0.1释放，然后用户可以随时可以领取，不可以按照claimInterval进行领取
    // 3.2 冻结后质押的订单，收益领取按照1执行，不受影响
    // 3.3 恢复正常后所有订单都可以按照1执行
    // 4. 如果收益按照1正常执行：
    // 4.1 60%打给用户
    // 4.2 35%分给7个不同的级别，IReferrals(referrals).calcLevelAward(user, amount)获取要分配的地址，然后按照地址和数量打币
    // 4.3 1.5%给节点分红，调用IDividends.updateFarm
    // 4.4 剩余的打给指定地址wallet
    // 5. 如果收益大于0：
    // 5.1 uint256 amountToken = getAmountOut(收益数量)，返回token数量
    // 5.2 _exchange(token, USDT, amountToken, address(this))，将计算后的token数量进行兑换
    // 5.3 ILex(token).specialWithdraw(amountToken);必须要调用
    // 5.4 所有币是usdt全部给地址地址，包括级别等等
    // 6. 如果收益只是领取冻结后释放的部分，则只需要记录领取的数额防止重复领取并且为恢复做好准备，不执行向上分发收益
    // 7. 到期后应该是不会再继续有收益的
    /// @notice 提取收益，正常订单、冻结前的订单、冻结后的订单、1天的订单
    function claim(address user, uint256 orderIndex) external onlyQueue{
        TreasuryRules.Order storage order = userOrders[user][orderIndex];
        TreasuryRules.isActive(order);

        _applyPause(user, orderIndex);

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 reward;

        // ===== 体验单 =====
        if(order.stakeIndex == 0){
            require(block.timestamp >= order.startTime + 1 days, "Order not matured yet");

            uint256 total = calculateNormal(user, orderIndex);
            reward = total > order.claimed ? total - order.claimed : 0;
            require(reward > 0, "No reward");

            order.claimed += uint128(reward);
            _swapTokenToUsdt(reward);
            TransferHelper.safeTransfer(USDT, user, reward);
            return;
        }

        // ===== 冻结旧订单 =====
        if (_isFrozenOldOrder(order)) {
            uint256 released = releasedAmount(user, orderIndex);
            reward = released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;

            // 如果当前还没有可释放的金额，直接返回
            if (reward == 0) {
                return;
            }

            order.frozenClaimed += uint128(reward);

            _swapTokenToUsdt(reward);
            TransferHelper.safeTransfer(USDT, user, reward);
            return;
        }

        // ===== 正常订单 =====
        require(!TreasuryRules.isExpired(order, block.timestamp), "Claim expired");
        require(TreasuryRules.isInClaimWindow(order, plan, block.timestamp), "Not claim window");

        uint256 totalReward = calculateNormal(user, orderIndex);
        reward = totalReward > order.claimed ? totalReward - order.claimed : 0;
        require(reward > 0, "No reward");

        order.claimed += uint128(reward);
        order.claimedPeriods += 1;

        _issueAward(user, reward);
    }

    // stakeIndex > 0
    // 1.赎回限制
    // 1.1 未到期的订单不允许赎回
    // 1.2 已赎回的订单不允许赎回
    // 1.3 在冻结前质押的订单不允许赎回
    // 1.4 到期后超过12个月的订单不允许赎回

    // 2.赎回手续费，总质押为本金1000U
    // 2.1 用户赎回金额可以为0
    // 2.2 已提取收益保留10%给用户，假设用户已提取收益为100U，为用户保留10U(10%)
    // 2.3 用户在到期后，赎回手续费10%，每隔24小时赎回手续费增加10%
    // 2.4 赎回总额等于 = 1000 - (100 - 10) - (1000 * 10 / 100) - (1000 * 10 / 100) * x days
    // 2.5 本金*10/100作为固定手续费打给wallet，其余手续费不做处理
    // 2.6 给用户到账的本金 + 本金*10/100固定手续费执行兑换并发送，如果用户的金额为0，则只发送手续费

    // 3.收益处理
    // 3.1 赎回订单不发送订单收益，且在用户赎回后直接将该订单的收益清0

    // stake == 0
    // 1.未到期的订单不允许赎回
    // 2.已赎回的订单不允许赎回
    // 3.在冻结前质押的订单允许赎回
    // 4.订单到期后超过12个月不允许赎回

    // 5.赎回不收取手续费
    // 6.赎回将订单收益直接发送给用户，不用向上分发收益

    /// @notice 订单赎回
    function unstake(address user, uint256 index) external onlyQueue {
        TreasuryRules.Order storage order = userOrders[user][index];
        TreasuryRules.isActive(order); // 活跃检查
        _applyPause(user, index);

        // ===== 体验单分支 =====
        if(order.stakeIndex == 0){
            require(block.timestamp >= order.startTime + 1 days, "Order not matured yet");
            uint256 total = calculateNormal(user, index);
            uint256 reward = total > order.claimed ? total - order.claimed : 0;
            uint256 totalOut = order.amount + reward;
            order.status = 1;
            order.claimed = uint128(total);
            _swapTokenToUsdt(totalOut);
            TransferHelper.safeTransfer(USDT, user, totalOut);
            return;
        }

        // ===== 普通订单分支 =====
        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 endTime = order.startTime + plan.duration;
        uint256 hardStop = order.startTime + 365 days;

        require(block.timestamp >= endTime, "Not matured");
        require(block.timestamp <= hardStop, "Expired > 12 months");
        require(!_isFrozenOldOrder(order), "Frozen order cannot unstake");

        uint256 principal = order.amount;

        // ===== 回收已提取收益 90%，清零所有收益 =====
        uint256 claimedTotal = uint256(order.claimed) + uint256(order.frozenClaimed);
        if(claimedTotal > 0){
            uint256 reclaim = claimedTotal * 90 / 100;
            if(reclaim > principal) reclaim = principal; // 保证不会超
            principal -= reclaim;
        }

        // ===== 手续费计算 =====
        uint256 principalPenalty = principal * 10 / 100; // 固定10%
        uint256 t24 = endTime + 1 days;
        if(block.timestamp > t24){
            uint256 overdueDays = (block.timestamp - t24) / 1 days;
            principalPenalty += principal * overdueDays * 10 / 100;
        }
        if(principalPenalty > principal) principalPenalty = principal;

        uint256 payout = principal - principalPenalty;

        // ===== 更新订单状态 =====
        order.status = 1;

        // ===== 统一兑换和发放 =====
        uint256 totalToSwap = payout + principalPenalty;
        if(totalToSwap > 0) _swapTokenToUsdt(totalToSwap);

        if(principalPenalty > 0) TransferHelper.safeTransfer(USDT, wallet, principalPenalty);
        if(payout > 0) TransferHelper.safeTransfer(USDT, user, payout);
    }


    // 1.已赎回的订单不允许重新质押
    // 2.超过12个月的不允许重新质押
    // 3.未到期的不允许重新质押
    // 4.重新质押stakeIndex只能大于等于
    // 5.订单到期后24小时内重新质押，则将orderIndex收益打给用户，避免数据错乱
    // 6.订单到期后且超过了24小时，把用户未领取的订单收益清0，也就是不打给用户
    // 7.领取的收益：
    // 7.1 60%打给用户
    // 7.2 35%分给7个不同的级别，IReferrals(referrals).calcLevelAward(user, amount)获取要分配的地址，然后按照地址和数量打币
    // 7.2 1.5%给节点分红，调用IDividends.updateFarm
    // 7.3 剩余的打给指定地址wallet
    // 8.如果收益大于0：
    // 8.1 uint256 amountToken = getAmountOut(收益数量)，返回token数量
    // 8.2 _exchange(token, USDT, amountToken, address(this))，将计算后的token数量进行兑换
    // 8.3 ILex(token).specialWithdraw(amountToken);必须要调用
    // 8.4 所有币是usdt全部给地址地址，包括级别等等
    // 9. 冻结前的订单如果现在还是冻结状态那就不允许重新质押，然后冻结后质押的订单只要到期后就遵循上述的方案
    // 10. stakeIndex == 0的订单，重新质押时：
    // 10.1 收益不做任何扣除全部打给用户，不需要向上分发，重新质押时stakeIndex只能大于，不允许等于
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external onlyQueue{
        TreasuryRules.Order storage order = userOrders[user][orderIndex];
        TreasuryRules.isActive(order);

        uint256 reward;

        // ===== 体验单 =====
        if(order.stakeIndex == 0){
            require(block.timestamp >= order.startTime + 1 days, "Order not matured yet");
            require(newStakeIndex > 0, "Must upgrade");

            uint256 total = calculateNormal(user, orderIndex);
            reward = total > order.claimed ? total - order.claimed : 0;

            if(reward > 0){
                _swapTokenToUsdt(reward);
                TransferHelper.safeTransfer(USDT, user, reward);
            }

            order.status = 1;

            userOrders[user].push(_newOrder(order.amount, newStakeIndex));
            return;
        }

        _applyPause(user, orderIndex);

        TreasuryRules.StakePlan memory oldPlan = stakePlans[order.stakeIndex];
        uint256 endTime = order.startTime + oldPlan.duration;
        uint256 hardStop = order.startTime + 365 days;

        require(block.timestamp >= endTime, "Not matured");
        require(block.timestamp <= hardStop, "Expired > 12 months");
        require(newStakeIndex >= order.stakeIndex, "Invalid stake index");
        require(!_isFrozenOldOrder(order), "Frozen order cannot reStake");

        uint256 totalReward = calculateNormal(user, orderIndex) + order.frozenReward;
        uint256 claimedReward = uint256(order.claimed) + uint256(order.frozenClaimed);
        reward = totalReward > claimedReward ? totalReward - claimedReward : 0;

        if(block.timestamp > endTime + 1 days) reward = 0;

        if(reward > 0) _issueAward(user, reward);

        order.status = 1;

        userOrders[user].push(_newOrder(order.amount, newStakeIndex));
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////internal func////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    /// @notice 用户领取收益、赎回时都适用该方法兑换usdt
    function _swapTokenToUsdt(uint256 usdtAmount) internal {
        IUniswapV2Pair pair = IUniswapV2Pair(ILex(token).pancakePair());
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        uint256 reserveToken;
        uint256 reserveUsdt;

        // 判断 token/USDT 对顺序
        if(pair.token0() == USDT){
            reserveUsdt = uint256(reserve0);
            reserveToken = uint256(reserve1);
        } else {
            reserveToken = uint256(reserve0);
            reserveUsdt = uint256(reserve1);
        }

        // ===== 动态 buffer =====
        uint256 bufferPercent = 1;
        // ===== 反算需要的 token 数量 =====
        // Uniswap V2 公式: amountOut = amountIn * 997 * reserveOut / (reserveIn * 1000 + amountIn * 997)
        // 反算 amountIn，简化计算大致估算
        uint256 numerator = reserveToken * usdtAmount * 1000;
        uint256 denominator = (reserveUsdt - usdtAmount) * 997;
        uint256 amountToken = numerator / denominator;
        // 加上 buffer
        amountToken = amountToken + (amountToken * bufferPercent / 1000);

        // 执行兑换
        _exchange(token, USDT, amountToken, address(this));
        ILex(token).specialWithdraw(amountToken);

        require(IERC20(USDT).balanceOf(address(this)) >= usdtAmount, "USDT Insufficient Balance.");
    }

    /// @notice 发送动态奖励
    function _issueAward(address user, uint256 reward) internal {
        uint256 userAmount = reward * 60 / 100;
        uint256 referralAmount = reward * 35 / 100;
        uint256 nodeAmount = reward * 15 / 1000;
        uint256 walletAmount = reward - userAmount - referralAmount - nodeAmount;

        _swapTokenToUsdt(reward);

        if (userAmount > 0)
            TransferHelper.safeTransfer(USDT, user, userAmount);

        if (referralAmount > 0) {
            Models.Revenue[] memory revenues = IReferrals(referrals).calcLevelAward(user, referralAmount);
            for (uint256 i; i < revenues.length; i++) {
                if (revenues[i].amount > 0)
                    TransferHelper.safeTransfer(USDT, revenues[i].user, revenues[i].amount);
            }
        }

        if (nodeAmount > 0) {
            TransferHelper.safeTransfer(USDT, nodeDividends, nodeAmount);
            INodeDividends(nodeDividends).updateFarm(Models.Source.STAKE_FEE, nodeAmount);
        }

        if (walletAmount > 0)
            TransferHelper.safeTransfer(USDT, wallet, walletAmount);
    }

    /// @notice 检查和更新冻结状态
    function _applyPause(address user, uint256 orderIndex) internal {
        if(!paused) return;

        TreasuryRules.Order storage order = userOrders[user][orderIndex];

        // 只处理冻结前创建的订单
        if(order.createdAt >= pauseTime) return;

        // 如果已经冻结过，不重复冻结
        if(order.freezeStart != 0) return;

        // ===== 记录冻结时的未领取收益 =====
        uint256 total = calculateNormal(user, orderIndex);
        uint256 unclaimed = total > order.claimed
            ? total - order.claimed
            : 0;

        order.frozenReward = uint128(unclaimed);
        order.freezeStart = uint32(block.timestamp);
    }

    function _exchange(address fromToken, address toToken, uint256 fromAmount, address to) private{
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
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

    function _newOrder(uint256 amount, uint8 stakeIndex)
        internal
        view
        returns (TreasuryRules.Order memory)
    {
        return TreasuryRules.Order({
            amount: uint128(amount),
            claimed: 0,
            claimedPeriods: 0,
            startTime: uint32(block.timestamp),
            stakeIndex: stakeIndex,
            status: 0,
            createdAt: uint32(block.timestamp),
            frozenReward: 0,
            frozenClaimed: 0,
            freezeStart: 0,
            freezeRound: 0
        });
    }


    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////收益计算部分//////////////////////////////////////////////
    //////////////////////////////////正常收益计算//////////////////////////////////////////////
    ////////////////////////////////冻结后订单收益计算///////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    // | 函数              | 计算什么    | 是否考虑冻结 | 是否扣除已领取 | 是否判断状态 |
    // | --------------- | ------- | ------ | ------- | ------ |
    // | calculateNormal | 理论累计收益  | ❌      | ❌       | ❌      |
    // | calculateReward | 当前可领取收益 | ✅      | ✅       | ✅      |

    /// @notice 计算正常状态下的订单收益
    function calculateNormal(address user, uint256 orderIndex)public view returns (uint256){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if(order.status > 0) return 0;
        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 endTime = uint256(order.startTime) + plan.duration;
        uint256 toTime = block.timestamp;
        if (toTime > endTime) toTime = endTime;
        if (toTime <= order.startTime) return 0;
        uint256 elapsed = toTime - order.startTime;
        return uint256(order.amount) * elapsed * plan.rate / 1e18;
    }

    /// @notice 当前订单真实可领取收益
    function calculateReward(address user, uint256 orderIndex)
        public
        view
        returns (uint256)
    {
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if (order.status != 0) return 0;

        if (_isFrozenOldOrder(order)) {
            uint256 released = releasedAmount(user, orderIndex);
            return released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;
        }

        uint256 total = calculateNormal(user, orderIndex);
        return total > order.claimed ? total - order.claimed : 0;
    }
    /// @notice 冻结后订单截止目前释放的总收益
    // 该订单在“当前冻结轮次”下，从 freezeStart 到现在，
    // 按 releaseRatePerDay 规则，理论上累计已经释放的总金额
    function releasedAmount(address user, uint256 orderIndex)public view returns (uint256){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if (order.frozenReward == 0) return 0;
        uint256 daysPassed = (block.timestamp - order.freezeStart) / 1 days;
        uint256 ratio = daysPassed * releaseRatePerDay;
        if (ratio > 1e18) ratio = 1e18;
        return uint256(order.frozenReward) * ratio / 1e18;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////view func///////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////
    function getAmountOut(uint256 amountUsdt) public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = token;
        return pancakeRouter.getAmountsOut(amountUsdt, path)[1];
    }

     // =================== 辅助函数 ===================
    /// @notice 获取订单倒计时
    /// @param user 用户地址
    /// @param orderIndex 用户订单索引
    /// @return claimCountdown 提取收益倒计时（秒），0表示可以领取
    /// @return unstakeCountdown 订单到期/赎回倒计时（秒），0表示可以赎回
    function getCountdown(address user, uint256 orderIndex)
        external
        view
        returns(uint256 claimCountdown, uint256 unstakeCountdown)
    {
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if(order.status != 0){
            return (0, 0);
        }

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];

        if(order.stakeIndex == 0){
            uint256 remaining = order.startTime + 1 days > block.timestamp
                ? order.startTime + 1 days - block.timestamp
                : 0;
            return (remaining, remaining);
        }

        // 冻结旧订单
        if(_isFrozenOldOrder(order)){
            return (0, type(uint256).max);
        }

        uint256 nextClaimTime =
            order.startTime + plan.claimInterval * (order.claimedPeriods + 1);

        claimCountdown =
            block.timestamp >= nextClaimTime
                ? 0
                : nextClaimTime - block.timestamp;

        uint256 endTime = order.startTime + plan.duration;

        unstakeCountdown =
            block.timestamp >= endTime
                ? 0
                : endTime - block.timestamp;
    }

    /// @notice 获取订单当前状态
    /// @param user 用户地址
    /// @param orderIndex 用户订单索引
    /// @return canClaim 是否可以领取收益
    /// @return canUnstake 是否可以赎回本金
    /// @return canRestake 是否可以重新质押
    function getStatus(address user, uint256 orderIndex)
        external
        view
        returns(bool canClaim, bool canUnstake, bool canRestake)
    {
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if(order.status != 0){
            return (false, false, false);
        }

        if(_isFrozenOldOrder(order)){
            return (true, false, false);
        }

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];

        TreasuryRules.RuleResult memory r =
            TreasuryRules.checkRules(order, plan, block.timestamp);

        return (r.canClaim, r.canUnstake, r.canRestake);
    }

    function _isFrozenOldOrder(TreasuryRules.Order memory order)
        internal
        view
        returns (bool)
    {
        return paused && order.createdAt < pauseTime;
    }


    function getUserOrders(address user)external view returns (TreasuryRules.Order[] memory){
        return userOrders[user];
    }

    function getOrderInfo(address user, uint256 orderIndex) external view returns(uint256 amount, uint8 stakeIndex){
        TreasuryRules.Order storage order = userOrders[user][orderIndex];
        amount = order.amount;
        stakeIndex = order.stakeIndex;
    }

    /// @notice 获取冻结订单的状态
    /// @param user 用户地址
    /// @param orderIndex 用户订单索引
    /// @return frozenReward 冻结时的总收益
    /// @return frozenClaimed 已领取冻结收益
    /// @return releasable 当前可领取冻结收益
    function getFrozenReleasable(address user, uint256 orderIndex)
        external
        view
        returns (
            uint256 frozenReward,
            uint256 frozenClaimed,
            uint256 releasable
        )
    {
        TreasuryRules.Order memory order = userOrders[user][orderIndex];

        frozenReward = uint256(order.frozenReward);
        frozenClaimed = uint256(order.frozenClaimed);

        if (frozenReward == 0 || !_isFrozenOldOrder(order)) {
            releasable = 0;
        } else {
            uint256 released = releasedAmount(user, orderIndex);
            releasable = released > frozenClaimed ? released - frozenClaimed : 0;
        }
    }

    function emergencyWithdraw(address _token, uint256 _amount, address _to)
        external
        onlyAdmin
    {   
        require(_token == token || _token == USDT);
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}