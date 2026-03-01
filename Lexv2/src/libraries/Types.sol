/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

library Types{
    enum LevelType{INVALID, L1, L2, L3, L4, L5, L6, L7}
    enum Source{INVALID, TAX_FEE, PROFIT_FEE, STAKE_FEE}
    enum NodeType{invalid, envoy, director, partner}
    struct Revenue{
        address user;
        uint256 amount;
    }

    struct DirectReferral{
        address user;
        uint256 staked;
        uint256 performance;
    }
    
}