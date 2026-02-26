// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Types } from "./libraries/Types.sol";
import { TreasuryRules } from "./libraries/TreasuryRules.sol";

import "./const.sol";

interface ILex {
    function specialWithdraw(uint256 amount) external;
}

interface INodeDividends{
    function updateFarm(uint256 amount) external;
}

interface IReferrals{
    function calcLevelAward(address user, uint256 amount)
        external
        view
        returns (Types.Revenue[] memory);
}

contract Treasury is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // address public constant USDT =
    //     0x55d398326f99059fF775485246999027B3197955;

    mapping(uint8 => TreasuryRules.StakePlan) public stakePlans;
    mapping(address => TreasuryRules.Order[]) public userOrders;
    mapping(address => mapping(uint256 => bool)) public notEligible;

    address public token;
    address public wallet;
    address public referrals;
    address public nodeDividends;
    address public queue;

    bool public paused;
    uint32 public pauseTime;
    uint32 public pauseRound;
    uint64 public releaseRatePerDay; // 1e15 = 0.1%

    function _authorizeUpgrade(address newImplementation)internal view override onlyOwner{}

    function initialize(address _token, address _wallet) public initializer {
        __Ownable_init(_msgSender());
        token = _token;
        wallet = _wallet;
        releaseRatePerDay = 1e15; // 冻结释放 0.1%
        uint256 day = 1 days;

        stakePlans[0] = TreasuryRules.StakePlan({
            duration: 1 days,
            claimInterval: 1 days,
            rate: uint64(3e15 / day),
            fee: 0
        });
        stakePlans[1] = TreasuryRules.StakePlan({
            duration: 15 days,
            claimInterval: 15 days,
            rate: uint64(6e15 / day),
            fee: 0
        });
        stakePlans[2] = TreasuryRules.StakePlan({
            duration: 30 days,
            claimInterval: 15 days,
            rate: uint64(12e15 / day),
            fee: 0
        });
        stakePlans[3] = TreasuryRules.StakePlan({
            duration: 90 days,
            claimInterval: 10 days,
            rate: uint64(13e15 / day),
            fee: 0
        });
    }

    modifier onlyQueue() {
        require(queue == msg.sender, "Only the queue can be called.");
        _;
    }

    function setConfig(address _referrals, address _nodeDividends, address _queue) external onlyOwner{
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
        require(queue == msg.sender, "Not permit.");
        require(paused, "Not paused");
        paused = false;
    }

    function stake(address user, uint256 amount, uint8 stakeIndex) external onlyQueue{
        if(stakeIndex == 0) {
            require(amount <= 100e18, "Exceeding the trial limit.");
            require(!notEligible[user][stakeIndex], "Reuse trial qualification.");
            notEligible[user][stakeIndex] = true;
        }
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
    function claim(address user, uint256 orderIndex) external onlyQueue{
        TreasuryRules.Order storage order = userOrders[user][orderIndex];
        TreasuryRules.isActive(order); // 活跃检查

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];

        uint256 reward; // 统一在函数开头声明

        // stakeIndex == 0 特殊体验单
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

        // 冻结释放逻辑
        if(TreasuryRules.isFrozenOldOrder(order, paused, pauseRound)){
            uint256 released = releasedAmount(user, orderIndex);
            reward = released > order.frozenClaimed ? released - order.frozenClaimed : 0;
            require(reward > 0, "No released reward");
            order.frozenClaimed += uint128(reward);
            _swapTokenToUsdt(reward);
            TransferHelper.safeTransfer(USDT, user, reward);
            return;
        }

        // 正常 stakeIndex > 0
        require(!TreasuryRules.isExpired(order, block.timestamp), "Claim expired");
        require(TreasuryRules.isInClaimWindow(order, plan, block.timestamp), "Not claim window");

        uint256 totalReward = calculateNormal(user, orderIndex);
        reward = totalReward > order.claimed ? totalReward - order.claimed : 0;
        require(reward > 0, "No reward");

        order.claimed += uint128(reward);
        order.claimedPeriods += 1;

        _issueAward(user, reward);
    }

    // 1.未到期的订单不允许赎回
    // 2.已赎回的订单不允许重复赎回
    // 3.冻结前的旧订单不允许赎回，冻结后的新订单在到期后可以按照下述规则进行赎回
    // 4.到期后的订单在到期后24小时内赎回，遵循以下原则：
    // 4.1 比如用户订单金额是1000usdt，提取的收益总量是100usdt
    // 4.2 用户赎回时，应该是1000 * 10 / 100，这是本金赎回手续费
    // 4.3 给用户保留10%的利润，也就是已提取的100其中10个归于用户，90个算作已提取本金
    // 4.4 那么用户总共可提取 = 1000 - 100(本金手续费) - 90个(算作已提取本金) = 810个
    // 4.5 这里可能会存在减不过的情况，那么用户赎回金额就是0，修改订单状态即可
    // 4.6 扣减的手续费部分打给wallet
    // 5. 如果提取金额或者手续费大于0，则:
    // 5.1 uint256 amountToken = getAmountOut(收益数量)，返回token数量
    // 5.2 _exchange(token, USDT, amountToken, address(this));
    // 5.3 ILex(token).specialWithdraw(amountToken);
    // 5.4 对应手续费可用户可提总金额都直接打币到账
    // 6. 如果到期后，且赎回时时间已经大于24小时
    // 6.1 本金手续费原本有10%，每超过1天就增加10%，用户赎回金额可以为0
    // 6.2 做完赎回后订单不允许有收益，这里可以通过修改时间或者其他方案及将该订单当前以及后续收益都置为0
    // 7. 用户的订单stakeIndex == 0的情况
    // 7.1 用户赎回时将用户的收益和本金全部给到用户
    // 7.2 这里收益包括本金都不收取任何手续费，且收益不需要向上分发
    function unstake(address user, uint256 index) external onlyQueue{
        TreasuryRules.Order storage order = userOrders[user][index];
        TreasuryRules.isActive(order); // 活跃检查

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

        _applyPause(user, index);

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 endTime = order.startTime + plan.duration;
        uint256 hardStop = order.startTime + 365 days;

        require(block.timestamp >= endTime, "Not matured");
        require(block.timestamp <= hardStop, "Expired > 12 months");

        require(!TreasuryRules.isFrozenOldOrder(order, paused, pauseRound), "Frozen old order cannot unstake");

        uint256 principal = order.amount;
        uint256 principalPenalty = principal * 10 / 100;
        uint256 t24 = endTime + 1 days;

        if(block.timestamp > t24){
            uint256 overdueDays = (block.timestamp - t24) / 1 days;
            principalPenalty += principal * overdueDays * 10 / 100;
        }

        if(principalPenalty > principal) principalPenalty = principal;

        uint256 payout = principal - principalPenalty;
        order.status = 1;

        _swapTokenToUsdt(principal);

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
        TreasuryRules.isActive(order); // 活跃检查

        uint256 reward; // ✅ 在函数开头统一声明

        // stakeIndex == 0 特殊体验单
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

            userOrders[user].push(TreasuryRules.Order({
                amount: order.amount,
                claimed: 0,
                claimedPeriods: 0,
                startTime: uint32(block.timestamp),
                stakeIndex: newStakeIndex,
                status: 0,
                createdAt: uint32(block.timestamp),
                frozenReward: 0,
                frozenClaimed: 0,
                freezeStart: 0,
                freezeRound: 0
            }));

            return;
        }

        _applyPause(user, orderIndex);

        TreasuryRules.StakePlan memory oldPlan = stakePlans[order.stakeIndex];
        uint256 endTime = order.startTime + oldPlan.duration;
        uint256 hardStop = order.startTime + 365 days;

        require(block.timestamp >= endTime, "Not matured");
        require(block.timestamp <= hardStop, "Expired > 12 months");
        require(newStakeIndex >= order.stakeIndex, "Invalid stake index");
        require(!TreasuryRules.isFrozenOldOrder(order, paused, pauseRound), "Frozen order cannot reStake");

        uint256 totalReward = calculateNormal(user, orderIndex) + order.frozenReward;
        uint256 claimedReward = uint256(order.claimed) + uint256(order.frozenClaimed);
        reward = totalReward > claimedReward ? totalReward - claimedReward : 0;

        if(block.timestamp > endTime + 1 days) reward = 0;
        if(reward > 0) _issueAward(user, reward);

        order.status = 1;

        userOrders[user].push(TreasuryRules.Order({
            amount: order.amount,
            claimed: 0,
            claimedPeriods: 0,
            startTime: uint32(block.timestamp),
            stakeIndex: newStakeIndex,
            status: 0,
            createdAt: uint32(block.timestamp),
            frozenReward: 0,
            frozenClaimed: 0,
            freezeStart: 0,
            freezeRound: 0
        }));
    }

    function getUserOrders(address user)external view returns (TreasuryRules.Order[] memory){
        return userOrders[user];
    }
    
    function calculateNormal(address user, uint256 orderIndex)public view returns (uint256){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        uint256 endTime = uint256(order.startTime) + plan.duration;
        uint256 toTime = block.timestamp;
        if (toTime > endTime) toTime = endTime;
        if (toTime <= order.startTime) return 0;
        uint256 elapsed = toTime - order.startTime;
        return uint256(order.amount) * elapsed * plan.rate / 1e18;
    }

    function calculateReward(address user, uint256 orderIndex)public view returns (uint256){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if (order.status != 0) return 0;
        if (paused && order.freezeRound == pauseRound) {
            uint256 released = releasedAmount(user, orderIndex);
            return released > order.frozenClaimed
                ? released - order.frozenClaimed
                : 0;
        }
        uint256 total = calculateNormal(user, orderIndex);
        return total > order.claimed ? total - order.claimed : 0;
    }
    
    function releasedAmount(address user, uint256 orderIndex)public view returns (uint256){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if (order.frozenReward == 0) return 0;
        uint256 daysPassed = (block.timestamp - order.freezeStart) / 1 days;
        uint256 ratio = daysPassed * releaseRatePerDay;
        if (ratio > 1e18) ratio = 1e18;
        return uint256(order.frozenReward) * ratio / 1e18;
    }

    function _applyPause(address user, uint256 index) internal {
        TreasuryRules.Order storage order = userOrders[user][index];
        if (!paused) return;
        if (order.status != 0) return;
        if (order.createdAt >= pauseTime) return;
        if (order.freezeRound == pauseRound) return;
        uint256 earned = calculateNormal(user, index);
        uint256 unclaimed = earned > order.claimed ? earned - order.claimed : 0;
        order.frozenReward += uint128(unclaimed);
        order.freezeStart = pauseTime;
        order.freezeRound = pauseRound;
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

    function getAmountOut(uint256 amountUsdt) public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = token;
        return pancakeRouter.getAmountsOut(amountUsdt, path)[1];
    }

    function _swapTokenToUsdt(uint256 usdtAmount) internal {
        uint256 amountToken = getAmountOut(usdtAmount);
        _exchange(token, USDT, amountToken, address(this));
        ILex(token).specialWithdraw(amountToken);
    }
    
    function _issueAward(address user, uint256 reward) internal {
        uint256 userAmount = reward * 60 / 100;
        uint256 referralAmount = reward * 35 / 100;
        uint256 nodeAmount = reward * 15 / 1000;
        uint256 walletAmount = reward - userAmount - referralAmount - nodeAmount;

        _swapTokenToUsdt(reward);

        if (userAmount > 0)
            TransferHelper.safeTransfer(USDT, user, userAmount);

        if (referralAmount > 0) {
            Types.Revenue[] memory revenues = IReferrals(referrals).calcLevelAward(user, referralAmount);
            for (uint256 i; i < revenues.length; i++) {
                if (revenues[i].amount > 0)
                    TransferHelper.safeTransfer(USDT, revenues[i].user, revenues[i].amount);
            }
        }

        if (nodeAmount > 0) {
            TransferHelper.safeTransfer(USDT, nodeDividends, nodeAmount);
            INodeDividends(nodeDividends).updateFarm(nodeAmount);
        }

        if (walletAmount > 0)
            TransferHelper.safeTransfer(USDT, wallet, walletAmount);
    }

    // =================== 辅助函数 ===================
    /// @notice 获取订单倒计时
    /// @param user 用户地址
    /// @param orderIndex 用户订单索引
    /// @return claimCountdown 提取收益倒计时（秒），0表示可以领取
    /// @return unstakeCountdown 订单到期/赎回倒计时（秒），0表示可以赎回
    function getCountdown(address user, uint256 orderIndex) external view returns(uint256 claimCountdown, uint256 unstakeCountdown){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if(order.status != 0){
            return (0, 0);
        }

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];
        
        // stakeIndex == 0 特殊体验单
        if(order.stakeIndex == 0){
            uint256 remaining = order.startTime + 1 days > block.timestamp
                ? order.startTime + 1 days - block.timestamp
                : 0;
            return (remaining, remaining);
        }

        // 冻结旧订单
        if(TreasuryRules.isFrozenOldOrder(order, paused, pauseRound)){
            return (0, type(uint256).max);
        }

        // 正常 stakeIndex > 0
        uint256 nextClaimTime = order.startTime + plan.claimInterval * (order.claimedPeriods + 1);
        claimCountdown = block.timestamp >= nextClaimTime ? 0 : nextClaimTime - block.timestamp;
        uint256 endTime = order.startTime + plan.duration;
        unstakeCountdown = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
    }

    /// @notice 获取订单当前状态
    /// @param user 用户地址
    /// @param orderIndex 用户订单索引
    /// @return canClaim 是否可以领取收益
    /// @return canUnstake 是否可以赎回本金
    /// @return canRestake 是否可以重新质押
    function getStatus(address user, uint256 orderIndex) external view returns(bool canClaim, bool canUnstake, bool canRestake){
        TreasuryRules.Order memory order = userOrders[user][orderIndex];
        if(order.status != 0){
            return (false, false, false);
        }

        TreasuryRules.StakePlan memory plan = stakePlans[order.stakeIndex];

        TreasuryRules.RuleResult memory r = TreasuryRules.checkRules(order, plan, paused, pauseRound, block.timestamp);
        canClaim = r.canClaim;
        canUnstake = r.canUnstake;
        canRestake = r.canRestake;
    }

}

// 整体合约需求：
// 1. stakeIndex == 0，
// 1.1 也就是1天到期的订单只能体验一次，不允许重复体验
// 1.2 订单收益提取不向上分发，全部都给用户
// 1.4 订单赎回全部赎回，没有赎回限制
// 1.5 订单重新质押stakeIndex > 0
// 1.6 冻结前后订单不受都不受冻结限制

// 2. stakeIndex > 0
// 2.1 可以重复质押
// 2.2 收益提取有时间窗口，窗口内24小时可以提取，24小时后等待下一个窗口，如果到期后24小时只能选择untsake和restake
// 2.3 领取收益时兑换，然后向上分发等级收益
// 2.3 冻结前的订单只能将已产生未领取的收益按照每天0.1%的数量进行释放，用户随时可以提取，不受提取窗口限制，且不分发手续费和等级收益
// 2.4 冻结后质押的订单，收益正常计算，按照2.2领取
// 2.5 赎回时冻结前质押的订单不允许，冻结后质押的允许，到期后24小时内赎回扣除手续费，超过24小时有单独的规则
// 2.6 重新质押，冻结前质押的订单不允许，冻结后质押的允许，24小时内将收益打给用户，24小时后没有收益，且将订单修正为新订单