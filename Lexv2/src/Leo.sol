// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}


interface IDividends {
    function updateFarm(uint256 amount) external;
}

interface IUniswapV2Pair {
    function sync() external;
}

contract Leo is ERC20, Ownable{
    event SwapAndSendTax(address recipient, uint256 tokensSwapped);
    IUniswapV2Router02 public pancakeRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant BURN_MIN_LIMIT = 21000000 ether;
    uint256 public constant BURN_RATE = 5; // 5/1000
    uint256 public buyRate = 100;

    address public pancakePair;
    address public USDT;

    address public wallet;
    address public nodeDividends;
    address public subCoinDividends;

    bool    private swapping;
    bool    public burnFinished;
    uint256 public lastBurnTime;


    mapping(address => bool) public allowlist;

    constructor(
        address _initialRecipient, 
        address _wallet, 
        address _nodeDividends, 
        address _USDT
    )ERC20("LEO","LEO")Ownable(msg.sender){
        _mint(_initialRecipient, 21000000e18);
        
        allowlist[_initialRecipient] = true;
        allowlist[_wallet] = true;
        allowlist[_nodeDividends] = true;

        wallet = _wallet;
        nodeDividends = _nodeDividends;
        USDT = _USDT;

        lastBurnTime = block.timestamp;
        
        pancakePair = IPancakeFactory(pancakeRouter.factory())
            .createPair(address(this), USDT);
    }

    

    function setNodeDividends(address _nodeDividends) external onlyOwner{
        nodeDividends = _nodeDividends;
        allowlist[_nodeDividends] = true;
    }

    function setSubCoinDividends(address _subCoinDividends) external onlyOwner{
        subCoinDividends = _subCoinDividends;
        allowlist[_subCoinDividends] = true;
    }

    function setRate(uint256 _buyRate) external onlyOwner{
        buyRate = _buyRate;
    }

    function setAllowlist(address[] memory addrs, bool isAllow) external onlyOwner{
        for(uint i=0; i<addrs.length; i++){
            allowlist[addrs[i]] = isAllow;
        }
    }

    function _swap(uint256 amountToken, address to) private{
        if (amountToken == 0) return ;
        //update status
        swapping = true;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
        _approve(address(this), address(pancakeRouter), amountToken);
         try pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountToken,
            0, 
            path,
            to,
            block.timestamp + 30
        ) {
            emit SwapAndSendTax(to, amountToken);
        }catch{}
        //update status
        swapping = false;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (
            swapping ||
            from == address(0) ||
            to == address(0) ||
            allowlist[from] ||
            allowlist[to]
        ) {
            super._update(from, to, amount);
            return;
        }

        if (to == pancakePair) revert("SELL_ISDISABLED.");

        if (from == pancakePair) {
            uint256 fee = amount * buyRate / 100;
            uint256 userAmount = amount - fee;
            if (fee > 0) super._update(from, address(this), fee);
            super._update(from, to, userAmount);
            return;
        }

        _issue();

        _burnFromPair();
        
        super._update(from, to, amount);
    }

    function _burnFromPair() internal {

        if (burnFinished) return;
        if (block.timestamp < lastBurnTime + 1 days) return;
        uint256 currentSupply = totalSupply() - balanceOf(DEAD);
        if (currentSupply <= BURN_MIN_LIMIT) {
            burnFinished = true;
            buyRate = 0;
            return;
        }

        uint256 pairBalance = balanceOf(pancakePair);
        if (pairBalance == 0) {
            lastBurnTime += 1 days;
            return;
        }

        uint256 burnAmount = pairBalance * BURN_RATE / 1000;

        if (currentSupply - burnAmount < BURN_MIN_LIMIT) {
            burnAmount = currentSupply - BURN_MIN_LIMIT;
        }

        if (burnAmount > 0) {
            super._update(pancakePair, DEAD, burnAmount);
            IUniswapV2Pair(pancakePair).sync();
        }

        lastBurnTime += 1 days;
    }

    function _issue() internal {

        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) return;

        uint256 subAmount = contractBalance * 40 / 100;
        uint256 swapAmount = contractBalance * 40 / 100;
        uint256 walletAmount = contractBalance - subAmount - swapAmount;

        if (subCoinDividends != address(0) && subAmount > 0) {
            super._update(address(this), subCoinDividends, subAmount);
            IDividends(subCoinDividends).updateFarm(subAmount);
        }

        if (nodeDividends != address(0) && swapAmount > 0) {
            uint256 beforeSwap = IERC20(USDT).balanceOf(nodeDividends);
            _swap(swapAmount, nodeDividends);
            uint256 afterSwap = IERC20(USDT).balanceOf(nodeDividends);
            IDividends(nodeDividends).updateFarm(afterSwap - beforeSwap);
        }

        if (wallet != address(0) && walletAmount > 0) {
            _swap(walletAmount, wallet);
        }
    }

}

//差一个dapp里卖出功能，卖出的100%被销毁到dead，先收取5%的手续费再进行卖出，也就是用户到账95