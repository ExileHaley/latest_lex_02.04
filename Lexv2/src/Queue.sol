// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
// import { ITreasury } from "../interfaces/ITreasury.sol";
import "./const.sol";

interface ILex{
    function getHighestReserve() external view returns(uint256);
}

interface ITreasury {
    function pause() external;
    function resume() external;
    function stake(address user, uint256 amount, uint8 stakeIndex) external;
    function unstake(address user, uint256 index) external;
    function restake(address user, uint256 orderIndex, uint8 newStakeIndex) external;
    function claim(address user, uint256 orderIndex) external;
    function getOrderAmount(address user, uint256 orderIndex) external view returns(uint256);
}

contract Queue is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard{
    uint8   constant PROCESS_BATCH = 5;
    address public treasury;
    address public referrals;
    address public lex;
    address public pair;


    uint256 public launchTime;          // 项目启动时间
    uint256 public freeDays;            // 前N天不限制

    uint256 public stakeRatio;          // 质押额度比例 (例如 2000 = 20%)
    uint256 public unstakeRatio;        // 赎回额度比例

    uint256 public stakeFee;      // 1 USDT
    uint256 public cancelFee;     // 2 USDT

    uint256 public fomoMinAmount;
    uint256 public constant fomoRewardCount = 21;

    uint256 public rounds; //记录开奖轮次
    struct Round {
        address[21] lastQualified;//存储实际上最后符合资格的21个地址
        uint256 count;// 当前轮已加入人数
    }
    mapping(uint256 => Round) public roundsData;
    uint256 public fomoPoolBalance; //记录总的开奖数额，每次分该数额的40%

    struct DailyQuota {
        uint256 stakeUsed;
        uint256 unstakeUsed;
    }
    mapping(uint256 => DailyQuota) public dailyQuota;

    struct PendingOrder {
        address user;
        uint256 amount;
        uint256 orderIndex;
        uint8 stakeIndex;
        //这里是记录用户的质押时间吗？这里真正进入国库作为质押时间，不能按照排队计算
        uint256 createdAt;
        bool isRestake;
    }
    //为什么使用uint256映射排队？
    mapping(uint256 => PendingOrder) public queue;
    uint256 public head;
    uint256 public tail;

    bool public circuitBreaker;
    uint256 public breakerReserve;
    uint256 public breakerTriggerRatio;    // 4000 = 40%

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _treasury,
        address _referrals,
        address _lex,
        address _pair
    ) public initializer {
        __Ownable_init(_msgSender());

        treasury = _treasury;
        referrals = _referrals;
        lex = _lex;
        pair = _pair;

        launchTime = block.timestamp;
        freeDays = 4;

        stakeRatio = 2000;          // 20%
        unstakeRatio = 2000;        // 20%

        stakeFee = 1e18;            // 注意单位，根据 USDT decimals 调整
        cancelFee = 2e18;

        fomoMinAmount = 500e18;
        breakerTriggerRatio = 4000; // 40%
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////owner set/////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    function setLaunchAndFreeDays(uint256 _launchTime, uint256 _freeDays) external onlyOwner {
        launchTime = _launchTime;
        freeDays = _freeDays;
    }

    function setQuotaRatios(uint256 _stakeRatio, uint256 _unstakeRatio) external onlyOwner {
        stakeRatio = _stakeRatio;
        unstakeRatio = _unstakeRatio;
    }

    function setFees(uint256 _stakeFee, uint256 _cancelFee) external onlyOwner {
        stakeFee = _stakeFee;
        cancelFee = _cancelFee;
    }

    function setFomoConfig(uint256 _fomoMinAmount) external onlyOwner {
        fomoMinAmount = _fomoMinAmount;
    }

    function setCircuitBreakerConfig(uint256 _breakerTriggerRatio) external onlyOwner {
        breakerTriggerRatio = _breakerTriggerRatio;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////external func///////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////


    //1.判断是否要更新额度
    //2.检查是否有额度
    //3.如果有额度，并且有排队订单，按照顺序将订单推到Treasury，每次尝试推5个排队订单
    //4.尝试推5个订单的前提是额度够用，如果不足5个就推实际数量，并且将自己的排队订单也推进去
    //5.如果不足以将自己的订单推进去则保存排队信息
    //6.推订单到Treasury合约：
    //6.1 如果排队订单不是重新质押，则使用TransferHelper.safeTransfer把PendingOrder.amount - 1数量的USDT转入Treasury合约，调用ITreasury.stake()
    //6.1.1 1U留在本合约作为fomo池，累加给fomoPoolBalance
    //6.2 如果排队订单是重新质押，不需要向Treasury合约转入USDT，调用ITreasury.restake()修改订单信息
    //7.推完订单后需要更新额度
    //8.推进去的订单如果数量大于fomoMinAmount，则添加fomo奖励池地址，也就是实现_addFomoQualified
    function stake(uint256 amount, uint8 stakeIndex) external nonReentrant {
        _executeOrQueue(
            msg.sender,
            amount,
            stakeIndex,
            false,
            0
        );
    }

    //1.检查是否更新赎回额度，并检查赎回额度是否足够
    //2.检查是否熔断
    //3.调用ITreasury.unstake进行质押解除
    function unstake(address user, uint256 orderIndex) external{}

    //1.检查是否更新质押额度
    //2.检查是否有额度
    //3.如果质押额度足够，且之前有排队订单，则先推5个排队订单到Treasury合约
    //4.尝试推5个订单的前提是额度够用，如果不足5个就推实际数量，并且将自己的排队订单也推进去
    //5.如果不足以将自己的订单推进去则保存排队信息,标注该排队订单是重新质押
    //6.推订单到Treasury合约：
    //6.1 如果排队订单不是重新质押，则使用TransferHelper.safeTransfer把PendingOrder.amount - 1数量的USDT转入Treasury合约，调用ITreasury.stake()
    //6.1.1 1U留在本合约作为fomo池，累加给fomoPoolBalance
    //6.2 如果排队订单是重新质押，不需要向Treasury合约转入USDT，调用ITreasury.restake()修改订单信息
    //7.推完订单后需要更新额度
    //8.推进去的订单如果数量大于fomoMinAmount，则添加fomo奖励池地址，也就是实现_addFomoQualified
    function restake(
        address user,
        uint256 orderIndex,
        uint256 newStakeIndex
    ) external nonReentrant {
        uint256 amount = ITreasury(treasury).getOrderAmount(user, orderIndex);
        _executeOrQueue(
            user,
            amount, // restake 不需要 amount
            uint8(newStakeIndex),
            true,
            orderIndex
        );
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////internal func///////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /// @notice 写入fomo信息
    function _addFomoQualified(address user) internal {
        Round storage round = roundsData[rounds];

        if (round.count < fomoRewardCount) {
            // 数组未满，直接加入尾部
            round.lastQualified[round.count] = user;
            round.count++;
        } else {
            // 数组已满，左移 1 个位置，丢掉最老的地址
            for (uint256 i = 0; i < fomoRewardCount - 1; i++) {
                round.lastQualified[i] = round.lastQualified[i + 1];
            }
            // 把最新地址放到数组尾部
            round.lastQualified[fomoRewardCount - 1] = user;
        }
    }
    /// @notice 尝试推送排队订单以及处理自己的质押或重新质押请求
    function _executeOrQueue(
        address user,
        uint256 amount,
        uint8 stakeIndex,
        bool isRestake,
        uint256 orderIndex // 仅 restake 用
    ) internal {

        _checkCircuitBreaker();

        // 先尝试推进队列
        _processQueue();

        // 检查当前订单是否可以直接执行
        if (_canStake(amount, stakeIndex)) {

            if (isRestake) {
                // 直接调用 Treasury restake
                ITreasury(treasury).restake(user, orderIndex, stakeIndex);

            } else {
                // 扣 1U 进入 FOMO 池
                uint256 stakeAmount = amount - stakeFee;

                TransferHelper.safeTransfer(USDT, treasury, stakeAmount);

                ITreasury(treasury).stake(user, stakeAmount, stakeIndex);

                fomoPoolBalance += stakeFee;
            }

            // 使用额度
            _useStakeQuota(amount, stakeIndex, isRestake);

            // FOMO 资格
            if (amount >= fomoMinAmount) {
                _addFomoQualified(user);
            }

        } else {
            // 不够额度，进入队列
            _enterQueue(user, amount, orderIndex, stakeIndex, isRestake);
        }
    }

    /// @notice 将订单放入队列
    function _enterQueue(address user, uint256 amount, uint256 orderIndex, uint8 stakeIndex, bool isRestake) internal {
        PendingOrder storage order = queue[tail];
        order.user = user;
        order.amount = amount;
        order.orderIndex = orderIndex;
        order.stakeIndex = stakeIndex;
        order.createdAt = block.timestamp;
        order.isRestake = isRestake;

        tail++; // tail指针后移
    }

    /// @notice 推送排队订单到国库，返回已处理订单数量
    function _processQueue() internal returns (uint256 processed) {
        uint256 maxBatch = PROCESS_BATCH;
        uint256 i = head;
        processed = 0;

        while (i < tail && processed < maxBatch) {
            PendingOrder storage order = queue[i];

            // 判断是否有额度
            if (!_canStake(order.amount, order.stakeIndex)) {
                break;
            }

            if (order.isRestake) {
                // ========================
                // 重新质押
                // ========================
                ITreasury(treasury).restake(
                    order.user,
                    order.orderIndex,      // ⚠️ 这里你要确认是否是 orderIndex
                    order.stakeIndex
                );

                // 扣额度
                _useStakeQuota(order.amount, order.stakeIndex, true);

            } else {
                // ========================
                // 普通质押
                // ========================

                uint256 stakeAmount = order.amount - stakeFee;

                // 转入 Treasury
                TransferHelper.safeTransfer(USDT, treasury, stakeAmount);

                // 1U 进入 FOMO 池
                fomoPoolBalance += stakeFee;

                ITreasury(treasury).stake(
                    order.user,
                    stakeAmount,
                    order.stakeIndex
                );

                // 扣额度
                _useStakeQuota(order.amount, order.stakeIndex, false);

                // FOMO资格
                if (order.amount >= fomoMinAmount) {
                    _addFomoQualified(order.user);
                }
            }

            delete queue[i];
            processed++;
            i++;
        }

        head += processed;
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////utils func//////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    /// @notice 获取今天距离 launchTime 的天数
    function _getToday() internal view returns(uint256) {
        return (block.timestamp - launchTime) / 1 days;
    }

    /// @notice 是否处于前 N 天免费期
    function _isFreePeriod() internal view returns(bool) {
        return block.timestamp < launchTime + freeDays * 1 days;
    }

    /// @notice 获取今日最大质押额度
    function _maxStakeQuota() internal view returns(uint256) {
        if (_isFreePeriod() || circuitBreaker) {
            return type(uint256).max; // 免费期或熔断期不限制额度
        }
        uint256 poolBalance = IERC20(pair).balanceOf(pair);
        return poolBalance * stakeRatio / 10000; // stakeRatio 千分比
    }

    /// @notice 获取今日最大赎回额度
    function _maxUnstakeQuota() internal view returns(uint256) {
        uint256 poolBalance = IERC20(pair).balanceOf(pair);
        return poolBalance * unstakeRatio / 10000;
    }

    /// @notice 检查熔断状态，根据 lex 最高储备触发/关闭
    function _checkCircuitBreaker() internal {
        uint256 highestReserve = ILex(lex).getHighestReserve();
        uint256 currentReserve = IERC20(pair).balanceOf(pair);

        if (!circuitBreaker && currentReserve < highestReserve * breakerTriggerRatio / 10000) {
            circuitBreaker = true;
            breakerReserve = currentReserve;
            ITreasury(treasury).pause();
        } else if (circuitBreaker && currentReserve >= breakerReserve * 2) {
            circuitBreaker = false;
            breakerReserve = 0;
            ITreasury(treasury).resume();
        }
    }

    /// @notice 是否允许质押
    /// @param amount 质押金额
    /// @param stakeIndex 订单类型，0 = 1天订单，不受额度限制
    function _canStake(uint256 amount, uint8 stakeIndex) internal view returns(bool) {
        if (stakeIndex == 0) return true;               // 1天订单质押不受限制
        if (_isFreePeriod() || circuitBreaker) return true; // 免费期或熔断期不限制额度

        uint256 today = _getToday();
        return dailyQuota[today].stakeUsed + amount <= _maxStakeQuota();
    }

    /// @notice 是否允许赎回
    /// @param amount 赎回金额
    /// @param stakeIndex 订单类型，0 = 1天订单，不受额度限制
    function _canUnstake(uint256 amount, uint8 stakeIndex) internal view returns(bool) {
        if (stakeIndex == 0) return true;               // 1天订单赎回不受限制
        if (circuitBreaker) return false;               // 熔断期间禁止赎回

        uint256 today = _getToday();
        return dailyQuota[today].unstakeUsed + amount <= _maxUnstakeQuota();
    }

    /// @notice 使用质押额度
    /// @param amount 质押金额
    /// @param stakeIndex 订单类型
    /// @param isRestake 是否是 restake
    function _useStakeQuota(uint256 amount, uint8 stakeIndex, bool isRestake) internal {
        // 1天订单质押且非 restake，不扣额度
        if (stakeIndex == 0 && !isRestake) return;
        if (_isFreePeriod() || circuitBreaker) return; // 免费期或熔断期不扣额度

        uint256 today = _getToday();
        dailyQuota[today].stakeUsed += amount;
    }

    /// @notice 使用赎回额度
    /// @param amount 赎回金额
    /// @param stakeIndex 订单类型
    function _useUnstakeQuota(uint256 amount, uint8 stakeIndex) internal {
        if (stakeIndex == 0) return;       // 1天订单不扣额度
        if (circuitBreaker) return;        // 熔断期间不扣额度，也不允许赎回

        uint256 today = _getToday();
        dailyQuota[today].unstakeUsed += amount;
    }

}
