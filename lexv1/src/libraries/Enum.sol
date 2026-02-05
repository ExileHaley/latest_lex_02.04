/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

library Enum {
    enum NodeType{invalid, envoy, director, partner}

    struct RecordAward{
        address user;
        uint256 amount;
        uint256 time;
    }
    
    struct DirectInfo{
        address user;
        Enum.NodeType nodeType;
        uint256 performance;
    }
}