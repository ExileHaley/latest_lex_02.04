// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script,console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Treasury} from "../src/Treasury.sol";
import {TreasuryLiquidity} from "../src/TreasuryLiquidity.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Queue} from "../src/Queue.sol";
import {Referrals} from "../src/Referrals.sol";
import {Router} from "../src/Router.sol";
import {Exchange} from "../src/Exchange.sol";

//导入要部署的代币
import {Lex} from "../src/token/Lex.sol";
import {Leo} from "../src/token/Leo.sol";
import {Tether} from "../src/mock/Tether.sol";

contract DeployScript is Script {
    address initialRecipient;
    address wallet;
    address nodeV1;
    address admin;
    address rootAddr;

    Tether public USDT;
    Lex public lex;
    Leo public leo;
    
    Treasury public treasury;
    TreasuryLiquidity public treasuryLiquidity;
    NodeDividends public nodeDividends;
    Queue public queue;
    Referrals public referrals;
    Router public router;
    Exchange public exchange;
    
    function setUp() public {
        initialRecipient = vm.envAddress("initial_recipient");
        wallet = vm.envAddress("wallet");
        nodeV1 = vm.envAddress("node_v1");
        admin = vm.envAddress("admin");
        rootAddr = vm.envAddress("root_addr");
    }

    function run() public {
        
        vm.startBroadcast();
        vm.txGasPrice(100_000_0000); // 0.05 gwei

        USDT = new Tether(initialRecipient);
        lex = new Lex(initialRecipient, wallet, address(USDT));
        leo = new Leo(initialRecipient, wallet, address(USDT));

        deployTreasury();
        deployNodeDividends();
        deployReferrals();
        deployTreasuryLiquidity();
        deployQueue();
        deployRouetr();

        treasury.setAddrConfig(address(queue), address(treasuryLiquidity));
        referrals.setAddrConfig(address(queue), address(router));
        queue.setAddrConfig(address(router));
        nodeDividends.setAddrConfig(address(treasuryLiquidity));

        lex.setNodeDividends(address(nodeDividends));
        lex.setTreasuryLiquidityAddr(address(treasuryLiquidity));
        leo.setNodeDividends(address(nodeDividends));

        vm.stopBroadcast();
        console.log("### contract address:");
        console.log("#### Lex token:",address(lex));
        console.log("#### Leo token:",address(leo));
        console.log("#### USDT test token:",address(USDT));
        console.log("=========================================================");
        console.log("#### Treasury:",address(treasury));
        console.log("#### TreasuryLiquidity:",address(treasuryLiquidity));
        console.log("#### NodeDividends:",address(nodeDividends));
        console.log("#### Queue:",address(queue));
        console.log("#### Referrals:",address(referrals));
        console.log("#### Router:",address(router));

        
    }

    function deployExchange() internal{
        // address _lex,
        // address _leo,
        // address _USDT,
        // address _wallet,
        // address _admin
        Exchange impl = new Exchange();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(address(lex), address(leo), address(USDT), wallet, admin))
        );
        exchange = Exchange(payable(address(proxy)));
    }

    function deployTreasury() internal{
        // initialize(address _wallet) 
        // setAddrConfig(
        //     address _queue,
        //     address _treasuryLiquidity
        // ) 
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(treasuryImpl.initialize,(wallet))
        );
        treasury = Treasury(payable(address(treasuryProxy)));
    } 

    function deployNodeDividends() internal{
        // initialize(
        //     address _lex,
        //     address _nodeDividendsV1,
        //     address _admin,
        //     address _USDT,
        // ) 

        NodeDividends nodeDividendsImpl = new NodeDividends();
        ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
            address(nodeDividendsImpl),
            abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeV1, admin, address(USDT)))
        );
        nodeDividends = NodeDividends(payable(address(nodeDividendsProxy)));
    }

    function deployReferrals() internal{
        // initialize(
        //     address _rootAddr,
        //     address _lexv1
        // )
        // setAddrConfig(address _queue, address _router)
        Referrals referralsImpl = new Referrals();
        ERC1967Proxy referralsProxy = new ERC1967Proxy(
            address(referralsImpl),
            abi.encodeCall(referralsImpl.initialize,(rootAddr, nodeV1))
        );
        referrals = Referrals(payable(address(referralsProxy)));
    }

    function deployTreasuryLiquidity() internal{
        // initialize(
        //     address _admin,
        //     address _treasury,
        //     address _token,
        //     address _usdt,
        //     address _wallet,
        //     address _referrals,
        //     address _nodeDividends
        // ) 
        TreasuryLiquidity impl = new TreasuryLiquidity();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(
                admin,
                address(treasury),
                address(lex),
                address(USDT),
                wallet,
                address(referrals),
                address(nodeDividends)
            ))
        );
        treasuryLiquidity = TreasuryLiquidity(payable(address(proxy)));
    }

    function deployQueue() internal{
        // initialize(
        //     address _admin,
        //     address _lex,
        //     address _pair,
        //     address _USDT,
        //     address _treasury, 
        //     address _treasuryLiquidity,
        //     address _referrals, 
        // )
        // setAddrConfig(
        //     address _router
        // ) 
        Queue queueImpl = new Queue();
        ERC1967Proxy queueProxy = new ERC1967Proxy(
            address(queueImpl),
            abi.encodeCall(queueImpl.initialize,(
                admin, 
                address(lex), 
                lex.pancakePair(), 
                address(USDT),
                address(treasury),
                address(treasuryLiquidity),
                address(referrals)
            ))
        );
        queue = Queue(payable(address(queueProxy)));
    }

    function deployRouetr() internal{
        // (
        //     address _treasury, 
        //     address _queue, 
        //     address _referrals,
        //     address _USDT
        // )
        router = new Router(address(treasury), address(queue), address(referrals), address(USDT));
    }
}