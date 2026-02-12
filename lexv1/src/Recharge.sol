// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TransferHelper } from "./libraries/TransferHelper.sol";
import { ReentrancyGuard } from "./libraries/ReentrancyGuard.sol";
import { Enum } from "./libraries/Enum.sol";

interface IVenus {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
}

contract Recharge is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard{
    event Referral(address recommender,address referred);
    event Staked(address user, uint256 amount, Enum.NodeType nodeType);
    
    address public constant VENUS = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    uint256 public constant MAX_REFERRAL_DEPTH = 50;
    struct User{
        address recommender;
        Enum.NodeType nodeType;
        uint256 referralNum;
        uint256 performance;
        uint256 award;
        uint256 awardRatio;
        uint256 extracted;
    }
    mapping(address => User) public userInfo;

    mapping(address => Enum.RecordAward[]) recordAwardInfo; 
    mapping(address => address[]) public directReferrals;
    mapping(Enum.NodeType => uint256) public nodePrice;
    address public admin;
    address public initialCode;
    address public recipient;
    address[] addrCollection;
    mapping(address => bool) public isAddCollection;

    uint256 public totalPerformance;
    bool    private pause;

    uint256[50] private __gap;

    modifier onlyAdmin() {
        require(admin == msg.sender, "Not permit.");
        _;
    }

    modifier Pause() {
        require(!pause, "Already Paused.");
        _;
    }

    receive() external payable {
        revert("NO_DIRECT_SEND");
    }


    // Authorize contract upgrades only by the owner
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(){}

    function initialize(
        address _admin,
        address _recipient,
        address _initialCode
    ) public initializer {
        __Ownable_init(_msgSender());
        admin = _admin;
        recipient = _recipient;
        initialCode = _initialCode;
        // nodePrice[Enum.NodeType.envoy] = 500e18;
        // nodePrice[Enum.NodeType.director] = 2000e18;
        // nodePrice[Enum.NodeType.partner] = 5000e18;
        nodePrice[Enum.NodeType.envoy] = 1e17;
        nodePrice[Enum.NodeType.director] = 2e17;
        nodePrice[Enum.NodeType.partner] = 3e17;
    }

    
    function emergencyWithdraw(address token, uint256 amount, address to) external onlyAdmin {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function setAwardRatio(address user, uint256 _ratio) external onlyAdmin{
        require(_ratio <= 90, "Error ratio.");
        userInfo[user].awardRatio = _ratio;
    }

    function referral(address recommender) external Pause{
        require(recommender != address(0),"ZERO_ADDRESS.");
        require(recommender != msg.sender,"INVALID_RECOMMENDER.");
        if(recommender != initialCode) require(userInfo[recommender].recommender != address(0),"RECOMMENDATION_IS_REQUIRED_REFERRAL.");
        require(userInfo[msg.sender].recommender == address(0),"INVITER_ALREADY_EXISTS.");
        userInfo[msg.sender].recommender = recommender;
        directReferrals[recommender].push(msg.sender);

        //collect address
        if (!isAddCollection[msg.sender]) {
            addrCollection.push(msg.sender);
            isAddCollection[msg.sender] = true;
        }

        _processReferralNumber(msg.sender);
        emit Referral(recommender, msg.sender);
    }

    function _processReferralNumber(address user) private{
        address current = userInfo[user].recommender;
        uint256 depth = 0;
        while (current != address(0) && depth < MAX_REFERRAL_DEPTH) {
            if (current == user) {
                break;
            }
            userInfo[current].referralNum += 1;
            current = userInfo[current].recommender;
            depth++;
        }
    }

    function singleRecharge(Enum.NodeType nodeType) external nonReentrant Pause{
        require(nodePrice[nodeType] > 0, "ERROR_NODE_TYPE.");
        User storage u = userInfo[msg.sender];
        require(u.nodeType == Enum.NodeType.invalid, "ALREADY_RECHARGE.");
        require(u.recommender != address(0),"RECOMMENDATION_IS_REQUIRED_RECHARGE.");
        TransferHelper.safeTransferFrom(USDT, msg.sender, address(this), nodePrice[nodeType]);

        uint256 toRecipient = nodePrice[nodeType] * 80 / 100;
        TransferHelper.safeApprove(USDT, VENUS, 0);
        TransferHelper.safeApprove(USDT, VENUS, toRecipient);
        require(IVenus(VENUS).mint(toRecipient) == 0, "VENUS_MINT_FAILED");

        uint256 venusAmount = IERC20(VENUS).balanceOf(address(this));
        TransferHelper.safeTransfer(VENUS, recipient, venusAmount);

        u.nodeType = nodeType;
        totalPerformance +=  nodePrice[nodeType];
        
        if (userInfo[msg.sender].recommender != address(0)) _processReferral(msg.sender, nodePrice[nodeType]);
        emit Staked(msg.sender, nodePrice[nodeType], nodeType);
    }

    function _processReferral(
        address user,
        uint256 amountUSDT
    ) internal {
        address current = userInfo[user].recommender;
        uint256 depth = 0;

        uint256 distributedRatio = 0; // 已经分发的总比例

        while (current != address(0) && depth < MAX_REFERRAL_DEPTH) {
            if (current == user) break;

            // 1️⃣ 累加业绩
            userInfo[current].performance += amountUSDT;

            // 2️⃣ 处理奖励
            uint256 currentRatio = userInfo[current].awardRatio;

            if (currentRatio > distributedRatio) { // 差额模式
                uint256 realRatio = currentRatio - distributedRatio;
                uint256 rewardAmount = amountUSDT * realRatio / 100;

                if (rewardAmount > 0) {
                    userInfo[current].award += rewardAmount;
                    recordAwardInfo[current].push(
                        Enum.RecordAward({
                            user: user,
                            amount: rewardAmount,
                            time: block.timestamp
                        })
                    );
                }

                distributedRatio += realRatio;
                if (distributedRatio >= 100) break;
            }

            current = userInfo[current].recommender;
            depth++;
        }
    }




    function claim() external nonReentrant {
        User storage u = userInfo[msg.sender];
        uint256 amount = u.award - u.extracted;
        require(amount > 0, "NO_AWARD");

        // effects
        userInfo[msg.sender].extracted += amount;

        // interactions
        TransferHelper.safeTransfer(USDT, msg.sender, amount);
    }


    function getUserInfo(address user) external view returns(
        address recommender,
        Enum.NodeType nodeType,
        uint256 referralNum,
        uint256 performance,
        uint256 award,
        uint256 awardRatio,
        uint256 totalAward,
        Enum.RecordAward[] memory recordAwards
    ){
        User memory u = userInfo[user];
        recommender = u.recommender;
        nodeType = u.nodeType;
        referralNum = u.referralNum;
        performance = u.performance;
        award = u.award - u.extracted;
        totalAward = u.award;
        awardRatio = u.awardRatio;
        recordAwards = recordAwardInfo[user];
    }
    

    function getDirectReferralInfo(address user)
        external
        view
        returns (Enum.DirectInfo[] memory infos)
    {
        address[] memory directs = directReferrals[user];
        uint256 len = directs.length;

        infos = new Enum.DirectInfo[](len);

        for (uint256 i = 0; i < len; i++) {
            address addr = directs[i];
            User storage u = userInfo[addr];

            infos[i] = Enum.DirectInfo({
                user: addr,
                nodeType: u.nodeType,
                performance: u.performance
            });
        }
    }

    function getAddrCollectionLength() external view returns(uint){
        return addrCollection.length;
    }

    function validInvitationCode(address user) external view returns(bool){
        if(user == initialCode) return true;
        else return userInfo[user].recommender != address(0);
    }

    function getAddrCollection() external view returns (address[] memory) {
        return addrCollection;
    }

    function getMigrateInfo(address user) external view returns(address recommender, Enum.NodeType nodeType, uint256 amount){
        User memory u = userInfo[user];
        recommender = u.recommender;
        nodeType = u.nodeType;
        amount = nodePrice[u.nodeType];
    }
}