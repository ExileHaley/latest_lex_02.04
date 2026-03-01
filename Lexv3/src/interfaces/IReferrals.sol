/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import { Models } from "../libraries/Models.sol";

interface IReferrals{
    function rootAddr() external view returns(address);
    function referralInfo(address user) 
        external 
        view 
    returns(
        address parent,
        Models.LevelType level,
        uint16 referralNum,
        uint256 totalStaked,
        uint256 performance
    );
    function referral(address parent, address user) external;
    function processStakeInfo(address user, uint256 amount) external;
    function processUnstakeInfo(address user, uint256 amount) external;
    function getLevelUsers() external view returns(address[] memory);
    function getEffectivePerformance(address[] memory users)
        external
        view
    returns (Models.Effective[] memory);
    function calcLevelAward(address user, uint256 amount)
        external
        view
    returns (Models.Revenue[] memory);
    function getDirectReferralInfo(address user) 
        external 
        view 
    returns(Models.DirectReferral[] memory);
}