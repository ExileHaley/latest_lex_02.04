// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { INodeDividends } from "./interfaces/INodeDividends.sol";
import { IReferrals } from "./interfaces/IReferrals.sol";
import { ILex } from "./interfaces/ILex.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Models } from "./libraries/Models.sol";



contract TreasuryLiquidity is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public admin;
    address public treasury;
    address public token;
    address public USDT;
    address public wallet;
    address public referrals;
    address public nodeDividends;

     modifier onlyTreasury() {
        require(msg.sender == treasury, "Only Treasury");
        _;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function initialize(
        address _admin,
        address _treasury,
        address _token,
        address _usdt,
        address _wallet,
        address _referrals,
        address _nodeDividends
    ) public initializer {
        __Ownable_init(_msgSender());
        admin = _admin;
        treasury = _treasury;
        token = _token;
        USDT = _usdt;
        wallet = _wallet;
        referrals = _referrals;
        nodeDividends = _nodeDividends;
    }

    function setAddrConfig(address _treasury, address _referrals, address _nodeDividends) external onlyOwner{
        treasury = _treasury;
        referrals = _referrals;
        nodeDividends = _nodeDividends;
    }

    /// @notice 奖励分发（claim / restake 使用）
    function issueAward(address user, uint256 reward)
        external
        onlyTreasury
    {
        if (reward == 0) return;

        uint256 userAmount = reward * 60 / 100;
        uint256 referralAmount = reward * 35 / 100;
        uint256 nodeAmount = reward * 15 / 1000;
        uint256 walletAmount = reward - userAmount - referralAmount - nodeAmount;

        _swapTokenToUsdt(reward);

        if (userAmount > 0)
            TransferHelper.safeTransfer(USDT, user, userAmount);

        if (referralAmount > 0) {
            Models.Revenue[] memory revenues =
                IReferrals(referrals).calcLevelAward(user, referralAmount);

            for (uint256 i; i < revenues.length; i++) {
                if (revenues[i].amount > 0) {
                    TransferHelper.safeTransfer(
                        USDT,
                        revenues[i].user,
                        revenues[i].amount
                    );
                }
            }
        }

        if (nodeAmount > 0) {
            TransferHelper.safeTransfer(USDT, nodeDividends, nodeAmount);
            INodeDividends(nodeDividends)
                .updateFarm(Models.Source.STAKE_FEE, nodeAmount);
        }

        if (walletAmount > 0)
            TransferHelper.safeTransfer(USDT, wallet, walletAmount);
    }

    function _swapTokenToUsdt(uint256 usdtAmount) internal{
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

    function swapTokenToUsdt(address to, uint256 usdtAmount) external onlyTreasury{
        _swapTokenToUsdt(usdtAmount);
        if(to != address(0)) TransferHelper.safeTransfer(USDT, to, usdtAmount);
    }


    function addLiquidity(uint256 amountUSDT) external onlyTreasury  {
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

}