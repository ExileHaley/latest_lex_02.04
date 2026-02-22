/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

library Types{
    enum LevelType{INVALID, L1, L2, L3, L4, L5, L6, L7}
    struct Send{
        address user;
        uint256 amount;
    }
}