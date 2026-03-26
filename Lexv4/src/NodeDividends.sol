// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    address public leo;
    address public treasuryLiquidity;
    address public admin;
    address public USDT;
    address public nodeDividendsV1;

    mapping(Models.Source => uint256) public perStakingAward;
    uint256 public totalStaking;
    uint256 public constant DECIMALS = 1e13;

    uint256[50] private __gap;
    
    function _authorizeUpgrade(address) internal view override onlyOwner {}

    function initialize(
        address _lex,
        address _leo,
        address _nodeDividendsV1,
        address _admin,
        address _USDT
    ) public initializer {
        __Ownable_init(_msgSender());
        lex = _lex;
        leo = _leo;
        nodeDividendsV1 = _nodeDividendsV1;
        admin = _admin;
        USDT = _USDT;
    }

    modifier onlyFarm() {
        require(msg.sender == lex || msg.sender == treasuryLiquidity || msg.sender == leo, "NOT_PERMIT");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_PERMIT");
        _;
    }

    function setAddrConfig(address _treasuryLiquidity) external onlyOwner {
        treasuryLiquidity = _treasuryLiquidity;
    }

    function getUserStaking(address user) external view returns(uint256){
        return userInfo[user].stakingAmount;
    }

    /* ==================== 封顶逻辑 ==================== */
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

    /* ==================== 数据迁移 ==================== */
    function batchAdd(address[] memory users) external onlyOwner {
        for(uint i=0; i<users.length; i++){
            User storage u = userInfo[users[i]];
            if(u.stakingAmount == 0){
                (, Models.NodeType nodeType, uint256 stakingAmount) =
                    INodeDividendsV1(nodeDividendsV1).getMigrateInfo(users[i]);

                u.nodeType = nodeType;
                u.stakingAmount = stakingAmount;

                // 初始化 debt
                u.debtTax = uint128(stakingAmount * perStakingAward[Models.Source.TAX_FEE] / DECIMALS);
                u.debtProfit = uint128(stakingAmount * perStakingAward[Models.Source.PROFIT_FEE] / DECIMALS);
                u.debtStake = uint128(stakingAmount * perStakingAward[Models.Source.STAKE_FEE] / DECIMALS);

                totalStaking += stakingAmount;
            }
        }
    }

    /* ==================== 更新池 ==================== */
    function updateFarm(Models.Source source, uint256 amount) external onlyFarm {
        if(totalStaking == 0) return;
        perStakingAward[source] += amount * DECIMALS / totalStaking;
    }

    /* ==================== 计算单项 pending ==================== */
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

    /* ==================== 单项收益（含封顶） ==================== */
    function _getMaxReward(User storage u, Models.Source source) internal view returns(uint256) {
        if(source == Models.Source.PROFIT_FEE){
            if(u.nodeType == Models.NodeType.ENVOY) return u.stakingAmount;
            if(u.nodeType == Models.NodeType.DIRECTOR) return u.stakingAmount * 2;
            if(u.nodeType == Models.NodeType.PARTNER) return type(uint256).max; // 永久分红
        } else {
            if(u.nodeType == Models.NodeType.ENVOY) return u.stakingAmount;
            if(u.nodeType == Models.NodeType.DIRECTOR) return u.stakingAmount * 15 / 10;
            if(u.nodeType == Models.NodeType.PARTNER) return u.stakingAmount * 2;
        }
        return 0;
    }

    function getTaxFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(u.stakingAmount, perStakingAward[Models.Source.TAX_FEE], u.debtTax, u.taxExtracted);
        uint256 maxReward = _getMaxReward(u, Models.Source.TAX_FEE);

        // ⚡ 单项封顶
        if(u.taxExtracted + pending > maxReward){
            pending = maxReward > u.taxExtracted ? maxReward - u.taxExtracted : 0;
        }
        return pending;
    }

    function getProfitFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(u.stakingAmount, perStakingAward[Models.Source.PROFIT_FEE], u.debtProfit, u.profitExtracted);
        uint256 maxReward = _getMaxReward(u, Models.Source.PROFIT_FEE);

        if(u.profitExtracted + pending > maxReward){
            pending = maxReward > u.profitExtracted ? maxReward - u.profitExtracted : 0;
        }
        return pending;
    }

    function getStakeFeeAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 pending = _pending(u.stakingAmount, perStakingAward[Models.Source.STAKE_FEE], u.debtStake, u.stakeExtracted);
        uint256 maxReward = _getMaxReward(u, Models.Source.STAKE_FEE);

        if(u.stakeExtracted + pending > maxReward){
            pending = maxReward > u.stakeExtracted ? maxReward - u.stakeExtracted : 0;
        }
        return pending;
    }

    /* ==================== 总收益封顶 ==================== */
    function getUserAward(address user) public view returns(uint256) {
        User storage u = userInfo[user];
        if(u.stakingAmount == 0 || u.isOut) return 0;

        uint256 tax = getTaxFeeAward(user);
        uint256 profit = getProfitFeeAward(user);
        uint256 stake = getStakeFeeAward(user);

        uint256 total = tax + profit + stake;
        uint256 totalCap = _getTotalCap(u);

        // 总封顶裁剪
        if(u.extracted + total > totalCap){
            total = totalCap > u.extracted ? totalCap - u.extracted : 0;
        }
        return total;
    }

    /* ==================== Claim ==================== */
    function claim() external {
        User storage u = userInfo[msg.sender];
        require(u.stakingAmount > 0, "NO_NODE");
        require(!u.isOut, "OUT");

        uint256 tax = getTaxFeeAward(msg.sender);
        uint256 profit = getProfitFeeAward(msg.sender);
        uint256 stake = getStakeFeeAward(msg.sender);

        uint256 total = tax + profit + stake;
        require(total > 0, "NO_REWARD");

        u.taxExtracted += uint128(tax);
        u.profitExtracted += uint128(profit);
        u.stakeExtracted += uint128(stake);
        u.extracted += uint128(total);

        if(u.extracted >= _getTotalCap(u)){
            u.isOut = true;
        }

        TransferHelper.safeTransfer(USDT, msg.sender, total);
    }

    /* ==================== 管理员 ==================== */
    function emergencyWithdraw(address token, uint256 amount, address to)
        external onlyAdmin
    {
        TransferHelper.safeTransfer(token, to, amount);
    }
}