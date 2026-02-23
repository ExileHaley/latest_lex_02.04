// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Exchange is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    enum TokenType{INVALID, LEX, LEO}
    IUniswapV2Router02 public constant pancakeRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public constant USDT =
        0x55d398326f99059fF775485246999027B3197955;

    mapping(address => mapping(Token => uint256)) public availableLimit;
    mapping(TokenType => address) public token;


    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(address _leo) public initializer {
        __Ownable_init(_msgSender());
        leo = _leo;
    }

    function subAvailableLimit(TokenType tokenType, address[] memory users, uint256 amountUsdt) external{
        for(uint i=0; i<users.length; i++){
            uint256 currentLimit = availableLimit[users[i]][tokenType];
            if(currentLimit >= amountUsdt) availableLimit[users[i]][tokenType] -= amountUsdt;
            else availableLimit[users[i]][tokenType] = 0;
        }
    }

    function addAvailableLimit(TokenType tokenType, address[] memory users, uint256 amountUsdt) external {
        for(uint i=0; i<users.length; i++){
            availableLimit[users[i]][tokenType] += amountUsdt;
        }
    }
    
    function getAmountOut(TokenType fromTokenType, TokenType toTokenType, uint256 fromAmount) external view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = token[fromTokenType];
        path[1] = token[toTokenType];
        return pancakeRouter.getAmountsOut(fromAmount, path)[1];
    }

    function sellSubCoin(uint256 amountLeo) external{

    }

    function buy(TokenType tokenType, uint256 amountUsdt) external{}

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