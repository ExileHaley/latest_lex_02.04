// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVenus {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
}


contract Exchange is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public constant USDT =
        0x55d398326f99059fF775485246999027B3197955;

    address public constant VENUS = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;

    mapping(address => mapping(address => uint256)) public availableLimit;
    address public lex;
    address public leo;
    address public admin;
    address public wallet;

    uint256 public taxRate;

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _lex,
        address _leo,
        address _wallet,
        address _admin
    ) public initializer {
        __Ownable_init(_msgSender());
        lex = _lex;
        leo = _leo;
        wallet = _wallet;
        admin = _admin;
        taxRate = 5;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "Not permit.");
        _;
    }

    function setTaxRate(uint256 _taxRate) external onlyAdmin{
        taxRate = _taxRate;
    }

    function subAvailableLimit(address token, address[] memory users, uint256 amountUsdt) external onlyAdmin{
        for(uint i=0; i<users.length; i++){
            uint256 currentLimit = availableLimit[users[i]][token];
            if(currentLimit >= amountUsdt) availableLimit[users[i]][token] -= amountUsdt;
            else availableLimit[users[i]][token] = 0;
        }
    }

    function addAvailableLimit(address token, address[] memory users, uint256 amountUsdt) external onlyAdmin{
        for(uint i=0; i<users.length; i++){
            availableLimit[users[i]][token] += amountUsdt;
        }
    }
    
    function getAmountOut(address fromToken, address toToken, uint256 fromAmount) external view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        return pancakeRouter.getAmountsOut(fromAmount, path)[1];
    }

    function sellSubCoin(uint256 amountLeo) external{
        require(amountLeo > 0, "Error amount.");
        TransferHelper.safeTransferFrom(leo, msg.sender, address(this), amountLeo);
        _exchange(leo, USDT, amountLeo);
        uint256 balance = IERC20(USDT).balanceOf(address(this));
        
        if(balance > 0){
            uint256 fee = balance * taxRate / 100;
            require(IVenus(VENUS).mint(fee) == 0, "VENUS_MINT_FAILED");
            uint256 venusAmount = IERC20(VENUS).balanceOf(address(this));
            TransferHelper.safeTransfer(VENUS, wallet, venusAmount);
            TransferHelper.safeTransfer(USDT, msg.sender, balance - fee);
        }
    }

    function buy(address token, uint256 amountUsdt) external{
        require(token != address(0) && amountUsdt > 0, "Token and amount error.");
        require(availableLimit[msg.sender][token] >= amountUsdt, "Insufficient quota.");
        TransferHelper.safeTransferFrom(USDT, msg.sender, address(this), amountUsdt);
        uint256 fee = amountUsdt * taxRate / 100;
        
        require(IVenus(VENUS).mint(fee) == 0, "VENUS_MINT_FAILED");
        uint256 venusAmount = IERC20(VENUS).balanceOf(address(this));
        TransferHelper.safeTransfer(VENUS, wallet, venusAmount);
        
        _exchange(USDT, token, amountUsdt - fee);
        uint256 balance = IERC20(token).balanceOf(address(this));
        if(balance > 0){
            TransferHelper.safeTransfer(token, msg.sender, balance);
        }

        availableLimit[msg.sender][token] - amountUsdt;
    }

    function _exchange(address fromToken, address toToken, uint256 fromAmount) internal{
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        IERC20(fromToken).approve(address(pancakeRouter), fromAmount);
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            fromAmount, 
            0, 
            path, 
            address(this), 
            block.timestamp + 30
        );
    }

    
    
}