### install foundry-rs/forge-std
```shell
$ forge install foundry-rs/forge-std --no-commit --no-git
```
### install openzeppelin-contracts
```shell
$ forge install openzeppelin/openzeppelin-contracts  --no-git
```

### install openzeppelin-contracts-upgradeable
```shell
$ forge install openzeppelin/openzeppelin-contracts-upgradeable  --no-git
```

### deploy 
```shell
$ forge script script/Deploy.s.sol -vvv --rpc-url=https://bsc.blockrazor.xyz --broadcast --private-key=[privateKey]
```
### USDT:0x55d398326f99059fF775485246999027B3197955
### recharge:
### abi:./out/Recahrge.sol/Recharge.json
### recharge func list
```solidity
//查询管理员地址
function admin() external view returns(address);
//管理员提取代币，token代币地址，amount要提取的数量，to代币接收地址
function emergencyWithdraw(address token, uint256 amount, address to) external;
//管理员设置奖励百分比，这里输入90以下的整数，_ratio输入10则代表10%
function setAwardRatio(address user, uint256 _ratio) external;
```
------------------------------------------------------------------------
```solidity
//获取首码地址
function initialCode() external view returns(address);
//验证当前地址user是否可以作为邀请吗
function validInvitationCode(address user) external view returns(bool);
//invalid(0/无效)，envoy(1/大使)，director(2/股东)，partner(3/合伙人)
enum NodeType{invalid, envoy, director, partner}
//通过节点类型获取不同节点的价格，然后进行充值
function nodePrice(NodeType nodeType) external view returns(uint256);
//邀请，recommender输入邀请人地址
function referral(address recommender) external;
//充值，这里参数是nodeType节点类型
function singleRecharge(Enum.NodeType nodeType) external;
//提取管理员设置的奖励百分比，这个页面项目方要求没有奖励的不要展示，根据getUserInfo中的awardRatio是否大于0决定展示和隐藏
function claim() external;
//奖励记录
struct RecordAward{
    address user; //用户地址
    uint256 amount; //奖励数量
    uint256 time; //奖励时间
}
//获取用户信息
function getUserInfo(address user) external view returns(
    address recommender, //当前用户的邀请人地址
    Enum.NodeType nodeType, //当前用户的节点类型
    uint256 referralNum, //当前用户的总邀请人数
    uint256 performance, //当前用户的总邀请业绩(伞下业绩)
    uint256 award,  //当前用户的奖励数量
    uint256 awardRatio, //当前用户的奖励百分比，只用于判断，不做展示
    Enum.RecordAward[] memory recordAwards //奖励信息数组
);
//直推信息
struct DirectInfo{
    address user;   //用户地址
    Enum.NodeType nodeType; //节点类型
    uint256 performance; //伞下业绩
}
//返回直推地址的信息数据数组
function getDirectReferralInfo(address user)
    external
    view
returns (Enum.DirectInfo[] memory infos)
```