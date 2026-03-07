### contract address:
#### Lex token: 0xbE0b36cA2bCc6DEb811B1F6F634d650cB3EB428E
#### Leo token: 0x5a2Cd7311dAD231c7fb62c632176388724Ea6742
#### USDT test token: 0x33197a1d84Ec164413853B227174166c71475Db4
=========================================================
#### Treasury: 0xDc2cEdb481c18d9bE48ecC9118f64B85F1c539A4
#### TreasuryLiquidity: 0xae33fc0C731ec15BB57cCD8D9FA11317498820d2
#### NodeDividends: 0xc1534f77813e9f41132e2188D1e40f7Ca9C925F3
#### Queue: 0x3E03ad2f51d5D0584B835Ab4069C77f1d882DF34
#### Referrals: 0xda6E96c707c703F556081d2F2C99AE434aEE7C46
#### Router: 0x5c51bd302F867e80A50340F5DA74F39537ea6996

#### 质押、赎回、重新质押、提取收益gas都给到1000万
#### router func list
```solidity
// 获取系统状态，是否处于熔断中，true熔断中，false系统正常
function getSystemStatus() external view returns(bool circuitBreaker);
// 获取首码地址
function rootAddr() external view returns(address);
// 验证当前地址是否有邀请资格
function verifyReferralCode(address user) external view returns(bool);
// 获取USDT地址
function USDT() external view returns(address);
// 绑定邀请关系，parent是邀请人的地址
function referral(address parent) external;
// amount要质押的数量，stakeIndex要小于4，0/1/2/3代表1天、15天、30天、90天，这里质押的代币是usdt，包括赎回等
function stake(uint256 amount, uint8 stakeIndex) external;
// 通过orderIndex订单编号赎回订单
function unstake(uint256 orderIndex) external;
// 通过orderIndex订单编号和newStakeIndex(质押类型索引)对已有订单进行重新质押
function restake(uint256 orderIndex, uint8 newStakeIndex) external;
// 取消排队订单，根据排队订单编号queueOrderId取消排队订单
function cancelQueue(uint256 queueOrderId) external;
// 根据订单编号orderIndex提取订单收益
function claim(uint256 orderIndex) external;
struct Order {
        uint128 amount; //质押数量
        uint128 claimed; //正常收益已提取部分
        uint32  claimedPeriods; 
        uint32  startTime;  //订单开始时间
        uint8   stakeIndex; //订单类型，0、1、2、3分别是1天，15天，30天，90天
        uint8   status; // 0代表质押中、1代表已赎回

        uint32  createdAt; //订单创建时间

        uint128 frozenReward; //冻结的总奖励，熔断后
        uint128 frozenClaimed; //冻结奖励释放并且已提取的数量
        uint32  freezeStart; //冻结时间
        uint32  freezeRound; //冻结轮次
}
// TreasuryRules.Order[]的索引就是订单Id(orderIndex)
function getUserOrders(address user) external view returns(TreasuryRules.Order[] memory);
// 通过订单编号和用户地址获取订单倒计时和状态等
struct RuleResult {
        uint256 claimCountdown; //收益提取倒计时
        uint256 unstakeCountdown; //赎回倒计时
        bool canClaim;  //是否可以提取收益，可用作按钮置灰判断
        bool canUnstake; //是否可以赎回，可用作按钮置灰判断
        bool canRestake; //是否可以重新质押，可用作按钮置灰判断
        //下面三个可以不用展示
        bool isFrozen; //当前订单是否熔断或冻结
        bool isExpired; //当前订单是否超过12个月
        bool isMatured; //当前订单是否到期
}
//是当前订单真实可提取收益，result是上述结构体
function getOrderStatus(address user, uint256 orderIndex) 
        external 
        view 
        returns(
            uint256 truthAward,
            Models.RuleResult memory result
);
// 获取用户的所有订单，返回order结构体数组
function getUserOrders(address user) external view returns(TreasuryRules.Order[] memory);
// 根据排队订单编号获取获取排队详情
function getQueueInfo(uint256 queueId) 
        external 
        view 
        returns(
            address user,   //当前排队订单拥有者
            uint256 amount, //当前排队数量
            uint256 orderIndex, //订单编号，重新质押并进入排队的订单才会有值，通过isRestake判断
            uint8 stakeIndex,//当前排队订单要质押的类型或者说期限，这里类型代表的就是不同的期限
            uint256 createdAt,//当前排队订单创建时间
            bool isRestake, //是否是旧订单重新质押
            uint8 status    //当前排队订单的状态，0排队中，1已经质押，2已取消
        );
//获取当前时间的质押额度以及赎回额度
function getCurrentQuota() 
        external 
        view 
        returns(
            uint256 stakeUsed, //当前已使用的质押额度
            uint256 stakeRemaining, //当前剩余的可质押额度
            uint256 unstakeUsed, //当前已使用的赎回额度
            uint256 unstakeRemaining //当前剩余的可赎回额度
        );
//获取fomo池奖励
function getFomoInfo() 
        external 
        view 
        returns(
            uint256 roundId,    //当前属于第几轮奖励
            address[21] memory lastQualified, //当前轮游资格参与奖励的21个用户地址，有可能不足21个
            uint256 count,  //当前有资格参与奖励的地址数量
            uint256 poolBalance //当前轮次的fomo奖池总量
        );

struct DirectReferral{
        address user; //用户地址
        uint256 staked; //当前用户的总质押
        uint256 performance; //当前用户的伞下业绩
}
//获取直推信息
function getDirectReferralInfo(address user) 
        external 
        view 
    returns(Models.DirectReferral[] memory);
//获取邀请信息
enum LevelType{INVALID, L1, L2, L3, L4, L5, L6, L7}
function getReferralInfo(address user) 
        external 
        view 
        returns(
            address parent, //当前用户的邀请人地址
            Models.LevelType level,//当前用户的级别，INVALID就是没有级别
            uint16 referralNum, //当前用户的总邀请人数
            uint256 totalStaked, //当前用户的总质押数量
            uint256 performance //当前用户的伞下业绩
        );
```

#### nodeDividends func list
```solidity
////invalid(0/无效)，envoy(1/大使)，director(2/股东)，partner(3/合伙人)
enum NodeType{INVALID, ENVOY, DIRECTOR, PARTNER}
function userInfo(address user) external view returns(
        Models.NodeType nodeType, //节点类型
        uint256 stakingAmount, //节点对应的数量
        uint256 extracted, //已提取收益
        uint256 debt, //负债，这个不用展示
        bool isOut      //是否出局，这个也不用展示
);
//获取用户可提取收益
function getUserAward(address user) public view returns(uint256);
//提取收益
function claim() external;

```




#### exchange func list
```solidity
// 当前用户拥有的token购买额度，根据用户地址以及代币地址获取
function availableLimit(address user, address token) external view returns(uint256);
// 预估兑换结果，比如买入lex，就是fromToken==USDT，toToken==lex，fromAmount == usdt的数量
function getAmountOut(address fromToken, address toToken, uint256 fromAmount) external view returns(uint256);
// 卖出子币，这里用于卖出leo，获取预估结果的时候就是fromToken==leo，toToken==USDT， fromAmount == leo的数量，这里需要leo授权
function sellSubCoin(uint256 amountLeo) external;
// 买入代币，token这里是要买入的代币地址，比如lex或者leo，amountUsdt是买入多少USDT的代币，所以这里需要USDT授权
function buy(address token, uint256 amountUsdt) external;


///////////////////////////////////////管理员方法////////////////////////////////////////////////
//获取管理员地址
function admin() external view returns(address);
//管理员批量减少token购买额度，users[i]的token对应购买额度减少amountUsdt
function subAvailableLimit(address token, address[] memory users, uint256 amountUsdt) external;
//管理员批量增加token购买额度，users[i]的token对应购买额度增加amountUsdt
function addAvailableLimit(address token, address[] memory users, uint256 amountUsdt) external;
```





#### 下面都是管理员方法
#### referrals func list
```solidity
//获取级别从L1到L7的所有用户地址
function getLevelUsers() external view returns(address[] memory);
//通过级别用户的地址，批量获取对应地址的小区额度
function getEffectivePerformance(address[] memory users)
        external
        view
        returns (Models.Effective[] memory);
```
