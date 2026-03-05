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
$ forge script script/Treasury.s.sol -vvv --rpc-url=https://bsc.blockrazor.xyz --broadcast --private-key=[privateKey]
```


### build token constructor
```shell
$ cast abi-encode "constructor(string,string,address,address,address)" "GAT" "GAT" 0x27500f497A6195913ad93eaA7f9ffce9C156350a 0xBb294E00Cc67dF18f7DCA4010c90074Ae2867AC3 0x015c0E4B40EC22F4Dc570c658361fb4f3cBb9A97

```

### verify token contract
```shell
$ forge verify-contract --chain-id 56 --compiler-version v0.8.30+commit.a1b79de6 0xbfd3736B318a84D61B393D6c666C718Eb7e08e74 src/Snt.sol:Snt  --constructor-args 0x00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000027500f497a6195913ad93eaa7f9ffce9c156350a000000000000000000000000bb294e00cc67df18f7dca4010c90074ae2867ac3000000000000000000000000015c0e4b40ec22f4dc570c658361fb4f3cbb9a970000000000000000000000000000000000000000000000000000000000000003534e5400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003534e540000000000000000000000000000000000000000000000000000000000 --etherscan-api-key Y43WNBZNXWR5V4AWQKGAQ9RCQEXTUHK88V

```