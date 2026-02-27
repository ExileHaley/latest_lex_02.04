// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { Types } from "./libraries/Types.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import "./const.sol";

interface INodeDividendsV1 {
    function getMigrateInfo(address user)
        external
        view
        returns(address recommender, Types.NodeType nodeType, uint256 amount);
}

// enum Source{INVALID, TAX_FEE, PROFIT_FEE, STAKE_FEE}
// enum NodeType{invalid, envoy, director, partner}

//计算用户代币手续费分红数量：
// 如果user是envoy，或者说stakingAmount == 500e18，这里能获取的最大奖励值就是500e18
// 如果user是director，或者说stakingAmount == 2000e18，这里能获取的最大奖励值就是500e18 * 1.5
// 如果user是partner，或者说stakingAmount == 5000e18，这里能获取的最大奖励值就是500e18 * 2

//计算用户代币盈利税分红数量
// 如果user是envoy，或者说stakingAmount == 500e18，这里能获取的最大奖励值就是500e18
// 如果user是director，或者说stakingAmount == 2000e18，这里能获取的最大奖励值就是500e18 * 2
// 如果user是partner，或者说stakingAmount == 5000e18，这里能一直获取奖励
    
//计算用户质押税分红数量
// 如果user是envoy，或者说stakingAmount == 500e18，这里能获取的最大奖励值就是500e18
// 如果user是director，或者说stakingAmount == 2000e18，这里能获取的最大奖励值就是500e18 * 1.5
// 如果user是partner，或者说stakingAmount == 5000e18，这里能获取的最大奖励值就是500e18 * 2

contract NodeDividends is Initializable, OwnableUpgradeable, UUPSUpgradeable{

    struct User{
        Types.NodeType nodeType;
        uint256 stakingAmount;

        uint256 extracted;      // 已提取
        uint256 debt;           // 初始债务

        bool isOut;             // 是否出局
    }

    mapping(address => User) public userInfo;

    address public NodeDividendsV1;
    address public lex;
    address public stake;
    address public admin;

    mapping(Types.Source => uint256) public perStakingAward;
    uint256 public decimals = 1e13;
    uint256 public totalStaking;

    /* ========== 升级授权 ========== */

    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
        onlyOwner
    {}

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    modifier onlyFarm() {
        require(lex == msg.sender || stake == msg.sender, "NOT_PERMIT.");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "NOT_PERMIT.");
        _;
    }

    /* ========== 总倍数函数 ========== */

    function _getTotalMultiple(Types.NodeType nodeType)
        internal
        pure
        returns(uint256)
    {
        if(nodeType == Types.NodeType.envoy) return 3;
        if(nodeType == Types.NodeType.director) return 5;
        if(nodeType == Types.NodeType.partner) return type(uint256).max;

        return 0;
    }

    function _getTotalCap(User storage u)
        internal
        view
        returns(uint256)
    {
        uint256 m = _getTotalMultiple(u.nodeType);
        if(m == type(uint256).max) {
            return type(uint256).max;
        }
        return u.stakingAmount * m;
    }

    /* ========== 迁移 ========== */

    function batchAdd(address[] memory users) external onlyOwner{
        for(uint i=0; i<users.length; i++){
            User storage u = userInfo[users[i]];

            if(u.stakingAmount == 0){
                (,Types.NodeType nodeType, uint256 stakingAmount) =
                    INodeDividendsV1(NodeDividendsV1).getMigrateInfo(users[i]);

                u.nodeType = nodeType;
                u.stakingAmount = stakingAmount;

                uint256 totalPer =
                    perStakingAward[Types.Source.TAX_FEE] +
                    perStakingAward[Types.Source.PROFIT_FEE] +
                    perStakingAward[Types.Source.STAKE_FEE];

                u.debt = stakingAmount * totalPer / decimals;

                totalStaking += stakingAmount;
            }
        }
    }

    /* ========== 分红更新 ========== */

    function updateFarm(Types.Source source, uint256 amount) external onlyFarm{
        if(totalStaking == 0) return;
        perStakingAward[source] += amount * decimals / totalStaking;
    }

    /* ========== 单项封顶计算 ========== */

    function _cap(uint256 accumulated, uint256 maxReward)
        internal
        pure
        returns(uint256)
    {
        if(accumulated > maxReward) {
            return maxReward;
        }
        return accumulated;
    }

    function getTaxFeeAward(address user) public view returns(uint256){
        User storage u = userInfo[user];
        if(u.stakingAmount == 0) return 0;

        uint256 accumulated =
            u.stakingAmount *
            perStakingAward[Types.Source.TAX_FEE] /
            decimals;

        uint256 maxReward;

        if(u.nodeType == Types.NodeType.envoy){
            maxReward = u.stakingAmount;
        }
        else if(u.nodeType == Types.NodeType.director){
            maxReward = u.stakingAmount * 15 / 10;
        }
        else if(u.nodeType == Types.NodeType.partner){
            maxReward = u.stakingAmount * 2;
        }

        return _cap(accumulated, maxReward);
    }

    function getProfitFeeAward(address user) public view returns(uint256){
        User storage u = userInfo[user];
        if(u.stakingAmount == 0) return 0;

        uint256 accumulated =
            u.stakingAmount *
            perStakingAward[Types.Source.PROFIT_FEE] /
            decimals;

        if(u.nodeType == Types.NodeType.partner){
            return accumulated;
        }

        uint256 maxReward;

        if(u.nodeType == Types.NodeType.envoy){
            maxReward = u.stakingAmount;
        }
        else if(u.nodeType == Types.NodeType.director){
            maxReward = u.stakingAmount * 2;
        }

        return _cap(accumulated, maxReward);
    }

    function getStakeFeeAward(address user) public view returns(uint256){
        User storage u = userInfo[user];
        if(u.stakingAmount == 0) return 0;

        uint256 accumulated =
            u.stakingAmount *
            perStakingAward[Types.Source.STAKE_FEE] /
            decimals;

        uint256 maxReward;

        if(u.nodeType == Types.NodeType.envoy){
            maxReward = u.stakingAmount;
        }
        else if(u.nodeType == Types.NodeType.director){
            maxReward = u.stakingAmount * 15 / 10;
        }
        else if(u.nodeType == Types.NodeType.partner){
            maxReward = u.stakingAmount * 2;
        }

        return _cap(accumulated, maxReward);
    }

    /* ========== 总收益计算（含总封顶） ========== */

    function getUserAward(address user) public view returns(uint256){
        User storage u = userInfo[user];

        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 totalEarned =
            getTaxFeeAward(user)
            + getProfitFeeAward(user)
            + getStakeFeeAward(user);

        if(totalEarned <= u.debt) return 0;

        uint256 pending = totalEarned - u.debt;

        if(pending <= u.extracted) return 0;

        uint256 realPending = pending - u.extracted;

        uint256 totalCap = _getTotalCap(u);

        if(totalCap != type(uint256).max){
            if(u.extracted >= totalCap) return 0;

            uint256 remain = totalCap - u.extracted;

            if(realPending > remain){
                realPending = remain;
            }
        }

        return realPending;
    }

    /* ========== Claim ========== */

    function claim() external {
        User storage u = userInfo[msg.sender];
        require(u.stakingAmount > 0, "NO_NODE");
        require(!u.isOut, "OUT");

        uint256 pending = getUserAward(msg.sender);
        require(pending > 0, "NO_REWARD");

        u.extracted += pending;

        uint256 totalCap = _getTotalCap(u);
        if(totalCap != type(uint256).max){
            if(u.extracted >= totalCap){
                u.isOut = true;
            }
        }

        TransferHelper.safeTransfer(USDT, msg.sender, pending);
    }

    function emergencyWithdraw(address token, uint256 amount, address to)
        external
        onlyAdmin
    {
        TransferHelper.safeTransfer(token, to, amount);
    }
}