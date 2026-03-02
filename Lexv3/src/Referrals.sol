// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IReferrals } from "./interfaces/IReferrals.sol";
import { ILexv1 } from "./interfaces/ILexv1.sol";
import { Models } from "./libraries/Models.sol";

contract Referrals is Initializable, OwnableUpgradeable, UUPSUpgradeable, IReferrals{
    using EnumerableSet for EnumerableSet.AddressSet;
    mapping(address => EnumerableSet.AddressSet) private directReferralAddrSets;
    mapping(address => EnumerableSet.AddressSet) private activeDirectReferralAddrSets;
    EnumerableSet.AddressSet private levelAddrSets;
    uint16[8]  percentsForAward;
    uint256[7]  levelThresholds;

    address public rootAddr;
    address public queue;
    address public router;
    address public lexv1;

    struct Referral {
        address parent;        // 20 bytes
        Models.LevelType level;      // 1 byte (uint8 enum)
        uint16 referralNum;     // 2 bytes
        uint256 totalStaked;    // 32 bytes
        uint256 performance;    // 32 bytes
    }
    mapping(address => Referral) public referralInfo;

    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _rootAddr,
        address _lexv1
    ) public initializer {
        __Ownable_init(_msgSender());
        rootAddr = _rootAddr;
        lexv1 = _lexv1;
        // vault = _vault;
        percentsForAward = [5, 5, 10, 15, 20, 25, 28, 30];
        // 等级门槛
        levelThresholds = [
            10000 ether,      // L1
            50000 ether,      // L2
            150000 ether,     // L3
            500000 ether,     // L4
            1000000 ether,    // L5
            3000000 ether,    // L6
            10000000 ether    // L7
        ];
    }

    modifier onlyQueue() {
        require(queue == msg.sender, "Not permit.");
        _;
    }

    modifier onlyRouter() {
        require(router == msg.sender, "Not permit.");
        _;
    }

    function setAddrConfig(address _queue, address _router) external onlyOwner{
        queue = _queue;
        router = _router;
    }

    function batchMigrateReferral(address[] memory users) external onlyOwner{
        for(uint i=0; i<users.length; i++){
            address parent = ILexv1(lexv1).getParent(users[i]);
            referralInfo[users[i]].parent = parent;
        }
    }

    function referral(address parent, address user) external onlyRouter{
        // require(parent != address(0), "Zero address.");
        if(parent != rootAddr) require(referralInfo[parent].totalStaked > 0 && referralInfo[parent].parent != address(0), "Not eligible to be invited.");
        // require(parent != user, "Error parent addr.");
        Referral storage r = referralInfo[user];
        require(r.parent == address(0), "Already exists.");
        r.parent = parent;
    }

    function processStakeInfo(address user, uint256 amount) external onlyQueue{
        Referral storage r = referralInfo[user];
        require(r.parent != address(0), "Invitation code is required.");
        r.totalStaked += amount;

        address current = referralInfo[user].parent; 
        directReferralAddrSets[current].add(user);

        if(r.totalStaked >= 200e18) activeDirectReferralAddrSets[current].add(user);

        while (current != address(0)) {
            // 增加父级业绩
            referralInfo[current].performance += amount;
            // 更新父级等级
            _updateLevel(current);
            // 往上走
            current = referralInfo[current].parent;
        }

        // 最后更新自己等级
        _updateLevel(user);
    }

    function processUnstakeInfo(address user, uint256 amount) external onlyQueue{
        Referral storage r = referralInfo[user];
        r.totalStaked -= amount;

        address current = referralInfo[user].parent;
        // 移除有效直推
        if(r.totalStaked < 200e18) activeDirectReferralAddrSets[current].remove(user);

        while (current != address(0)) {
            // 减少父级业绩
            referralInfo[current].performance -= amount;
            // 更新父级等级
            _updateLevel(current);
            // 往上走
            current = referralInfo[current].parent;
        }

        // 最后更新自己等级
        _updateLevel(user);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////view func////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    function getLevelUsers() external view returns(address[] memory) {
        return levelAddrSets.values();
    }

    function getLevelUserCount() external view returns(uint256) {
        return levelAddrSets.length();
    }

    function getEffectivePerformance(address[] memory users)
        external
        view
        returns (Models.Effective[] memory)
    {
        uint256 len = users.length;
        Models.Effective[] memory result = new Models.Effective[](len);

        for (uint256 i = 0; i < len; i++) {
            address user = users[i];

            result[i] = Models.Effective({
                level: referralInfo[user].level,
                user: user,
                amount: _getEffectivePerformance(user)
            });
        }

        return result;
    }

    function calcLevelAward(address user, uint256 amount)
        external
        view
        returns (Models.Revenue[] memory)
    {
        // 最多 8 个奖励（直推 + L1~L7）
        Models.Revenue[] memory temp = new Models.Revenue[](8);
        uint256 count;

        address current = referralInfo[user].parent;

        uint16 lastPercent; // 已发最高等级比例
        

        // =========================
        // 1️⃣ 直推奖励 5%
        // =========================
        if (current != address(0)) {
            if (referralInfo[current].totalStaked >= 200e18) {
                uint256 reward = (amount * percentsForAward[0]) / 35;

                temp[count++] = Models.Revenue({
                    user: current,
                    amount: reward
                });
            }
        }

        // =========================
        // 2️⃣ 等级奖励（级差 + 截断）
        // =========================
        while (current != address(0)) {
            Models.LevelType level = referralInfo[current].level;

            if (level != Models.LevelType.INVALID) {
                uint16 levelPercent = percentsForAward[uint8(level)];

                if (levelPercent > lastPercent) {
                    uint16 diffPercent = levelPercent - lastPercent;

                    uint256 reward = (amount * diffPercent) / 35;

                    temp[count++] = Models.Revenue({
                        user: current,
                        amount: reward
                    });

                    lastPercent = levelPercent;

                    // 到 30% 截断
                    if (lastPercent == percentsForAward[7]) {
                        break;
                    }
                }
            }

            current = referralInfo[current].parent;
        }

        // =========================
        // 3️⃣ 精确长度返回
        // =========================
        Models.Revenue[] memory result = new Models.Revenue[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    /// @notice 获取直推用户的信息
    function getDirectReferralInfo(address user) 
        external 
        view 
        returns(Models.DirectReferral[] memory) 
    {
        uint256 length = directReferralAddrSets[user].length();
        Models.DirectReferral[] memory result = new Models.DirectReferral[](length);

        for (uint256 i = 0; i < length; i++) {
            address child = directReferralAddrSets[user].at(i);

            result[i] = Models.DirectReferral({
                user: child,
                staked: referralInfo[child].totalStaked,
                performance: referralInfo[child].performance
            });
        }

        return result;
    }


    //////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////internal func////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////
    function _updateLevel(address user) internal {
        Referral storage r = referralInfo[user];

        // 先判断是否满足基本条件
        bool shouldBeInvalid = r.totalStaked < 1000 ether 
                            || activeDirectReferralAddrSets[user].length() < 3;

        if (shouldBeInvalid) {
            // 如果已经是 INVALID 就不用写入了
            if (r.level != Models.LevelType.INVALID) {
                r.level = Models.LevelType.INVALID;
            }
            return;
        }

        uint256 performance = r.performance;
        Models.LevelType newLevel;

        if (performance >= levelThresholds[6]) {
            newLevel = Models.LevelType.L7;
        } else if (performance >= levelThresholds[5]) {
            newLevel = Models.LevelType.L6;
        } else if (performance >= levelThresholds[4]) {
            newLevel = Models.LevelType.L5;
        } else if (performance >= levelThresholds[3]) {
            newLevel = Models.LevelType.L4;
        } else if (performance >= levelThresholds[2]) {
            newLevel = Models.LevelType.L3;
        } else if (performance >= levelThresholds[1]) {
            newLevel = Models.LevelType.L2;
        } else if (performance >= levelThresholds[0]) {
            newLevel = Models.LevelType.L1;
        } else {
            newLevel = Models.LevelType.INVALID;
        }
        
        Models.LevelType oldLevel = r.level;

        if (oldLevel != newLevel) {
            if (newLevel == Models.LevelType.INVALID) levelAddrSets.remove(user);
            else levelAddrSets.add(user);
            r.level = newLevel;
        }
    }


    function _getEffectivePerformance(address user) internal view returns(uint256){
        uint256 length = directReferralAddrSets[user].length();
        if (length == 0) return 0;

        uint256 total;
        uint256 maxBranch;

        for (uint256 i = 0; i < length; i++) {
            address child = directReferralAddrSets[user].at(i);

            uint256 branchPerformance =
                referralInfo[child].performance +
                referralInfo[child].totalStaked;

            total += branchPerformance;

            if (branchPerformance > maxBranch) {
                maxBranch = branchPerformance;
            }
        }

        // 只有一个直推时，小区为 0
        if (length == 1) {
            return 0;
        }

        return total - maxBranch;
    }
}

