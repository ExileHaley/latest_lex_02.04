// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Types } from "./libraries/Types.sol";

interface ILexv1{
    function getParent(address user) external view returns(address);
}

interface IVault{
    function claim(address user, uint256 orderIndex) external returns(uint256);
}

contract Referrals is Initializable, OwnableUpgradeable, UUPSUpgradeable{
    using EnumerableSet for EnumerableSet.AddressSet;
    mapping(address => EnumerableSet.AddressSet) private directReferralAddrSets;
    mapping(address => EnumerableSet.AddressSet) private activeDirectReferralAddrSets;
    EnumerableSet.AddressSet private levelAddrSets;
    uint16[8] public percentsForAward;
    uint256[7] public levelThresholds;

    address public rootAddr;
    address public queue;
    address public lexv1;
    address public vault;

    struct Referral {
        address parent;        // 20 bytes
        Types.LevelType level;      // 1 byte (uint8 enum)
        bool valid;             // 1 byte
        uint16 referralNum;     // 2 bytes
        uint256 performance;    // 32 bytes
    }

    mapping(address => Referral) public referralInfo;
    mapping(address => uint256)  public totalUserStaked;


    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _rootAddr,
        address _lexv1,
        address _vault
    ) public initializer {
        __Ownable_init(_msgSender());
        rootAddr = _rootAddr;
        lexv1 = _lexv1;
        vault = _vault;
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

    function setAddrConfig(address _queue) external onlyOwner{
        queue = _queue;
    }

    function referral(address parent, address user) external {
        Referral storage r = referralInfo[user];
        require(r.parent == address(0), "Already exists.");
        r.parent = parent;
    }

    function batchMigrateReferral(address[] memory users) external {
        for(uint i=0; i<users.length; i++){
            address parent = ILexv1(lexv1).getParent(users[i]);
            referralInfo[users[i]].parent = parent;
        }
    }

    function processStakeInfo(address user, uint256 amount) external {
        totalUserStaked[user] += amount;

        address current = referralInfo[user].parent; 
        directReferralAddrSets[current].add(user);
        if(totalUserStaked[user] >= 200e18) activeDirectReferralAddrSets[current].add(user);

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
    
    function processUnstakeInfo(address user, uint256 amount) external {
        totalUserStaked[user] -= amount;

        address current = referralInfo[user].parent;
        // 移除有效直推
        if(totalUserStaked[user] < 200e18) activeDirectReferralAddrSets[current].remove(user);

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

    // ==================================================================== //
    function _updateLevel(address user) internal {
        Referral storage r = referralInfo[user];

        // 先判断是否满足基本条件
        bool shouldBeInvalid = totalUserStaked[user] < 1000 ether 
                            || activeDirectReferralAddrSets[user].length() < 3;

        if (shouldBeInvalid) {
            // 如果已经是 INVALID 就不用写入了
            if (r.level != Types.LevelType.INVALID) {
                r.level = Types.LevelType.INVALID;
            }
            return;
        }

        uint256 performance = r.performance;
        Types.LevelType newLevel;

        if (performance >= levelThresholds[6]) {
            newLevel = Types.LevelType.L7;
        } else if (performance >= levelThresholds[5]) {
            newLevel = Types.LevelType.L6;
        } else if (performance >= levelThresholds[4]) {
            newLevel = Types.LevelType.L5;
        } else if (performance >= levelThresholds[3]) {
            newLevel = Types.LevelType.L4;
        } else if (performance >= levelThresholds[2]) {
            newLevel = Types.LevelType.L3;
        } else if (performance >= levelThresholds[1]) {
            newLevel = Types.LevelType.L2;
        } else if (performance >= levelThresholds[0]) {
            newLevel = Types.LevelType.L1;
        } else {
            newLevel = Types.LevelType.INVALID;
        }
        
        Types.LevelType oldLevel = r.level;

        if (oldLevel != newLevel) {
            if (newLevel == Types.LevelType.INVALID) levelAddrSets.remove(user);
            else levelAddrSets.add(user);
            r.level = newLevel;
        }
    }

    function getLevelUsers() external view returns(address[] memory) {
        return levelAddrSets.values();
    }

    function getLevelUserCount() external view returns(uint256) {
        return levelAddrSets.length();
    }

    //计算指定用户的小区业绩
    //也就是我们这里只看直推地址的performance+totalUserStaked
    //比如有10个直推地址，那么performance+totalUserStaked值最大的地址就是大区
    //小区总业绩就等于除上述大区外的所有直推地址performance+totalUserStaked总和
    function getEffectivePerformance(address user) public view returns(uint256){
        uint256 length = directReferralAddrSets[user].length();
        if (length == 0) return 0;

        uint256 total;
        uint256 maxBranch;

        for (uint256 i = 0; i < length; i++) {
            address child = directReferralAddrSets[user].at(i);

            uint256 branchPerformance =
                referralInfo[child].performance +
                totalUserStaked[child];

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
        

    function processClaimInfo(address user, uint256 orderIndex) external{
        // - 收益的60%给到自己，35%给到动态分配，2%买子币放着，1.5%给节点分红，1.5%指定地址
        uint256 currentAward = IVault(vault).claim(user, orderIndex);
        uint256 stakingAward = currentAward * 60 / 100;
        uint256 levelAward = currentAward * 35 / 100;
        uint256 nodeAward = currentAward * 15 / 1000;
        // uint256 amountWallet = IERC20();
        // 1.给直推5%，这个保持不变
        // 2.级别奖励会出现极差的情况，比如首先碰到了L6，那么在L6之上低于L6的级别都不会再有奖励，只有L7会有，以此类推
        // 3.收益数量从Vault中调用claim获得
    }    

}
    // 自己质押总额要大于1000usdt，有效直推大于三个人：
    // 1.伞下总业绩1万usdt     L1  5%的奖励
    // 2.伞下总业绩5万usdt     L2  10%的奖励
    // 3.伞下总业绩15万usdt    L3  15%的奖励
    // 4.伞下总业绩50万usdt    L4  20%的奖励
    // 5.伞下总业绩100万usdt   L5  25%的奖励
    // 6.伞下总业绩300万usdt   L6  28%的奖励
    // 7.伞下总业绩1000万usdt  L7  30%的奖励
    // 我们要实现这个需求，要求升级方案从高到低，因为有极差的缘故