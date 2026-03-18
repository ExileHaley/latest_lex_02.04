// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.20;

// import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import { TransferHelper } from "./libraries/TransferHelper.sol";
// import { Models } from "./libraries/Models.sol";

// interface INodeDividendsV1 {
//     function getMigrateInfo(address user)
//         external
//         view
//         returns(address recommender, Models.NodeType nodeType, uint256 amount);
// }

// contract NodeDividends is Initializable, OwnableUpgradeable, UUPSUpgradeable {

//     struct User {
//         Models.NodeType nodeType;       // 节点类型
//         uint256 stakingAmount;          // 质押量

//         uint128 taxExtracted;           // 单项 tax 已提取
//         uint128 profitExtracted;        // 单项 profit 已提取
//         uint128 stakeExtracted;         // 单项 stake 已提取
//         uint128 extracted;              // 总提取量

//         uint128 debtTax;                // 可选，暂未使用
//         uint128 debtProfit;
//         uint128 debtStake;

//         bool isOut;                     // 是否出局
//     }

//     mapping(address => User) public userInfo;

//     address public lex;
//     address public treasuryLiquidity;
//     address public admin;
//     address public USDT;
//     address public nodeDividendsV1;

//     mapping(Models.Source => uint256) public perStakingAward;
//     uint256 public totalStaking;
//     uint256 public constant DECIMALS = 1e13;

//     function _authorizeUpgrade(address) internal view override onlyOwner {}

//     function initialize(
//         address _lex,
//         address _nodeDividendsV1,
//         address _admin,
//         address _USDT
//     ) public initializer {
//         __Ownable_init(_msgSender());
//         lex = _lex;
//         nodeDividendsV1 = _nodeDividendsV1;
//         admin = _admin;
//         USDT = _USDT;
//     }

//     modifier onlyFarm() {
//         require(msg.sender == lex || msg.sender == treasuryLiquidity, "NOT_PERMIT.");
//         _;
//     }

//     modifier onlyAdmin() {
//         require(msg.sender == admin, "NOT_PERMIT.");
//         _;
//     }

//     function setAddrConfig(address _treasuryLiquidity) external onlyOwner {
//         treasuryLiquidity = _treasuryLiquidity;
//     }

//     /* ========== 单项/总封顶计算 ========== */

//     function _getTotalMultiple(Models.NodeType nodeType) internal pure returns(uint256) {
//         if(nodeType == Models.NodeType.ENVOY) return 3;
//         if(nodeType == Models.NodeType.DIRECTOR) return 5;
//         if(nodeType == Models.NodeType.PARTNER) return type(uint256).max;
//         return 0;
//     }

//     function _getTotalCap(User storage u) internal view returns(uint256) {
//         uint256 m = _getTotalMultiple(u.nodeType);
//         if(m == type(uint256).max) return type(uint256).max;
//         return u.stakingAmount * m;
//     }

//     function _capSingle(uint256 extracted, uint256 pending, uint256 maxReward) internal pure returns(uint256) {
//         if(extracted >= maxReward) return 0;
//         uint256 remain = maxReward - extracted;
//         if(pending > remain) return remain;
//         return pending;
//     }

//     function _capTotal(uint256 extracted, uint256 pending, uint256 totalCap) internal pure returns(uint256) {
//         if(totalCap == type(uint256).max) return pending;
//         if(extracted >= totalCap) return 0;
//         uint256 remain = totalCap - extracted;
//         if(pending > remain) return remain;
//         return pending;
//     }

//     /* ========== 迁移 ========== */

//     function batchAdd(address[] memory users) external onlyOwner {
//         for(uint i=0; i<users.length; i++){
//             User storage u = userInfo[users[i]];
//             if(u.stakingAmount == 0){
//                 (, Models.NodeType nodeType, uint256 stakingAmount) = 
//                     INodeDividendsV1(nodeDividendsV1).getMigrateInfo(users[i]);

//                 u.nodeType = nodeType;
//                 u.stakingAmount = stakingAmount;

//                 uint256 totalPer = perStakingAward[Models.Source.TAX_FEE]
//                     + perStakingAward[Models.Source.PROFIT_FEE]
//                     + perStakingAward[Models.Source.STAKE_FEE];

//                 totalPer = totalPer > 0 ? totalPer : DECIMALS; // 防止除零
//                 u.debtTax = uint128(stakingAmount * perStakingAward[Models.Source.TAX_FEE] / DECIMALS);
//                 u.debtProfit = uint128(stakingAmount * perStakingAward[Models.Source.PROFIT_FEE] / DECIMALS);
//                 u.debtStake = uint128(stakingAmount * perStakingAward[Models.Source.STAKE_FEE] / DECIMALS);

//                 totalStaking += stakingAmount;
//             }
//         }
//     }

//     /* ========== 更新分红 ========== */

//     function updateFarm(Models.Source source, uint256 amount) external onlyFarm {
//         if(totalStaking == 0) return;
//         perStakingAward[source] += amount * DECIMALS / totalStaking;
//     }

//     /* ========== 单项奖励计算 ========== */

//     function getTaxFeeAward(address user) public view returns(uint256) {
//         User storage u = userInfo[user];
//         if(u.stakingAmount == 0) return 0;
//         uint256 accumulated = u.stakingAmount * perStakingAward[Models.Source.TAX_FEE] / DECIMALS;

//         uint256 maxReward;
//         if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
//         else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 15 / 10;
//         else if(u.nodeType == Models.NodeType.PARTNER) maxReward = u.stakingAmount * 2;

//         return _capSingle(u.taxExtracted, accumulated, maxReward);
//     }

//     function getProfitFeeAward(address user) public view returns(uint256) {
//         User storage u = userInfo[user];
//         if(u.stakingAmount == 0) return 0;
//         uint256 accumulated = u.stakingAmount * perStakingAward[Models.Source.PROFIT_FEE] / DECIMALS;

//         if(u.nodeType == Models.NodeType.PARTNER) return accumulated;

//         uint256 maxReward;
//         if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
//         else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 2;

//         return _capSingle(u.profitExtracted, accumulated, maxReward);
//     }

//     function getStakeFeeAward(address user) public view returns(uint256) {
//         User storage u = userInfo[user];
//         if(u.stakingAmount == 0) return 0;
//         uint256 accumulated = u.stakingAmount * perStakingAward[Models.Source.STAKE_FEE] / DECIMALS;

//         uint256 maxReward;
//         if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
//         else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 15 / 10;
//         else if(u.nodeType == Models.NodeType.PARTNER) maxReward = u.stakingAmount * 2;

//         return _capSingle(u.stakeExtracted, accumulated, maxReward);
//     }

//     /* ========== 总奖励计算 ========== */

//     function getUserAward(address user) public view returns(uint256) {
//         User storage u = userInfo[user];
//         if(u.stakingAmount == 0 || u.isOut) return 0;

//         uint256 tax = getTaxFeeAward(user);
//         uint256 profit = getProfitFeeAward(user);
//         uint256 stake = getStakeFeeAward(user);

//         uint256 totalPending = tax + profit + stake;
//         totalPending = _capTotal(u.extracted, totalPending, _getTotalCap(u));

//         return totalPending;
//     }

//     /* ========== Claim ========== */

//     function claim() external {
//         User storage u = userInfo[msg.sender];
//         require(u.stakingAmount > 0, "NO_NODE");
//         require(!u.isOut, "OUT");

//         uint256 tax = getTaxFeeAward(msg.sender);
//         uint256 profit = getProfitFeeAward(msg.sender);
//         uint256 stake = getStakeFeeAward(msg.sender);

//         uint256 total = tax + profit + stake;
//         total = _capTotal(u.extracted, total, _getTotalCap(u));
//         require(total > 0, "NO_REWARD");

//         u.taxExtracted += uint128(tax);
//         u.profitExtracted += uint128(profit);
//         u.stakeExtracted += uint128(stake);
//         u.extracted += uint128(total);

//         if(u.extracted >= _getTotalCap(u)) u.isOut = true;

//         TransferHelper.safeTransfer(USDT, msg.sender, total);
//     }

//     /* ========== Admin emergency withdraw ========== */

//     function emergencyWithdraw(address token, uint256 amount, address to)
//         external onlyAdmin
//     {
//         TransferHelper.safeTransfer(token, to, amount);
//     }
// }


pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Models } from "./libraries/Models.sol";

interface INodeDividendsV1 {
    function getMigrateInfo(address user)
        external
        view
        returns(address recommender, Models.NodeType nodeType, uint256 amount);
}

contract NodeDividends is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    struct User {
        Models.NodeType nodeType;
        uint256 stakingAmount;

        uint128 taxExtracted;
        uint128 profitExtracted;
        uint128 stakeExtracted;
        uint128 extracted;

        uint128 debtTax;
        uint128 debtProfit;
        uint128 debtStake;

        bool isOut;
    }

    mapping(address => User) public userInfo;

    address public lex;
    address public treasuryLiquidity;
    address public admin;
    address public USDT;
    address public nodeDividendsV1;

    mapping(Models.Source => uint256) public perStakingAward;
    uint256 public totalStaking;
    uint256 public constant DECIMALS = 1e13;

    function _authorizeUpgrade(address) internal view override onlyOwner {}

    function initialize(
        address _lex,
        address _nodeDividendsV1,
        address _admin,
        address _USDT
    ) public initializer {
        __Ownable_init(_msgSender());
        lex = _lex;
        nodeDividendsV1 = _nodeDividendsV1;
        admin = _admin;
        USDT = _USDT;
    }

    modifier onlyFarm() {
        require(msg.sender == lex || msg.sender == treasuryLiquidity, "NOT_PERMIT");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_PERMIT");
        _;
    }

    function setAddrConfig(address _treasuryLiquidity) external onlyOwner {
        treasuryLiquidity = _treasuryLiquidity;
    }

    /* ========== 封顶 ========== */

    function _getTotalMultiple(Models.NodeType nodeType) internal pure returns(uint256) {
        if(nodeType == Models.NodeType.ENVOY) return 3;
        if(nodeType == Models.NodeType.DIRECTOR) return 5;
        if(nodeType == Models.NodeType.PARTNER) return type(uint256).max;
        return 0;
    }

    function _getTotalCap(User storage u) internal view returns(uint256) {
        uint256 m = _getTotalMultiple(u.nodeType);
        if(m == type(uint256).max) return type(uint256).max;
        return u.stakingAmount * m;
    }

    function _capSingle(uint256 extracted, uint256 pending, uint256 maxReward) internal pure returns(uint256) {
        if(extracted >= maxReward) return 0;
        uint256 remain = maxReward - extracted;
        return pending > remain ? remain : pending;
    }

    function _capTotal(uint256 extracted, uint256 pending, uint256 totalCap) internal pure returns(uint256) {
        if(totalCap == type(uint256).max) return pending;
        if(extracted >= totalCap) return 0;
        uint256 remain = totalCap - extracted;
        return pending > remain ? remain : pending;
    }

    /* ========== 迁移 ========== */

    function batchAdd(address[] memory users) external onlyOwner {
        for(uint i=0; i<users.length; i++){
            User storage u = userInfo[users[i]];
            if(u.stakingAmount == 0){
                (, Models.NodeType nodeType, uint256 stakingAmount) =
                    INodeDividendsV1(nodeDividendsV1).getMigrateInfo(users[i]);

                u.nodeType = nodeType;
                u.stakingAmount = stakingAmount;

                u.debtTax = uint128(stakingAmount * perStakingAward[Models.Source.TAX_FEE] / DECIMALS);
                u.debtProfit = uint128(stakingAmount * perStakingAward[Models.Source.PROFIT_FEE] / DECIMALS);
                u.debtStake = uint128(stakingAmount * perStakingAward[Models.Source.STAKE_FEE] / DECIMALS);

                totalStaking += stakingAmount;
            }
        }
    }

    /* ========== 更新池 ========== */

    function updateFarm(Models.Source source, uint256 amount) external onlyFarm {
        if(totalStaking == 0) return;
        perStakingAward[source] += amount * DECIMALS / totalStaking;
    }

    /* ========== 单项收益（含 debt） ========== */

    function _pending(
        uint256 staking,
        uint256 per,
        uint256 debt,
        uint256 extracted
    ) internal pure returns(uint256) {
        uint256 accumulated = staking * per / DECIMALS;
        if(accumulated <= debt) return 0;
        uint256 net = accumulated - debt;
        if(net <= extracted) return 0;
        return net - extracted;
    }

    function getTaxFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(
            u.stakingAmount,
            perStakingAward[Models.Source.TAX_FEE],
            u.debtTax,
            u.taxExtracted
        );

        uint256 maxReward;
        if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
        else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 15 / 10;
        else if(u.nodeType == Models.NodeType.PARTNER) maxReward = u.stakingAmount * 2;

        return _capSingle(u.taxExtracted, pending, maxReward);
    }

    function getProfitFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(
            u.stakingAmount,
            perStakingAward[Models.Source.PROFIT_FEE],
            u.debtProfit,
            u.profitExtracted
        );

        if(u.nodeType == Models.NodeType.PARTNER) return pending;

        uint256 maxReward;
        if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
        else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 2;

        return _capSingle(u.profitExtracted, pending, maxReward);
    }

    function getStakeFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(
            u.stakingAmount,
            perStakingAward[Models.Source.STAKE_FEE],
            u.debtStake,
            u.stakeExtracted
        );

        uint256 maxReward;
        if(u.nodeType == Models.NodeType.ENVOY) maxReward = u.stakingAmount;
        else if(u.nodeType == Models.NodeType.DIRECTOR) maxReward = u.stakingAmount * 15 / 10;
        else if(u.nodeType == Models.NodeType.PARTNER) maxReward = u.stakingAmount * 2;

        return _capSingle(u.stakeExtracted, pending, maxReward);
    }

    function getUserAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 tax = getTaxFeeAward(user);
        uint256 profit = getProfitFeeAward(user);
        uint256 stake = getStakeFeeAward(user);

        uint256 total = tax + profit + stake;
        return _capTotal(u.extracted, total, _getTotalCap(u));
    }

    /* ========== Claim（已修复核心bug） ========== */

    function claim() external {
        User storage u = userInfo[msg.sender];
        require(u.stakingAmount > 0, "NO_NODE");
        require(!u.isOut, "OUT");

        uint256 tax = getTaxFeeAward(msg.sender);
        uint256 profit = getProfitFeeAward(msg.sender);
        uint256 stake = getStakeFeeAward(msg.sender);

        uint256 totalBefore = tax + profit + stake;
        uint256 total = _capTotal(u.extracted, totalBefore, _getTotalCap(u));
        require(total > 0, "NO_REWARD");

        // ⭐ 核心修复：按比例裁剪
        if(total < totalBefore){
            tax = tax * total / totalBefore;
            profit = profit * total / totalBefore;
            stake = stake * total / totalBefore;
        }

        u.taxExtracted += uint128(tax);
        u.profitExtracted += uint128(profit);
        u.stakeExtracted += uint128(stake);
        u.extracted += uint128(total);

        if(u.extracted >= _getTotalCap(u)){
            u.isOut = true;
        }

        TransferHelper.safeTransfer(USDT, msg.sender, total);
    }

    /* ========== 管理员 ========== */

    function emergencyWithdraw(address token, uint256 amount, address to)
        external onlyAdmin
    {
        TransferHelper.safeTransfer(token, to, amount);
    }
}