// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script,console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
//要部署的合约
import {Treasury} from "../src/Treasury.sol";
import {TreasuryLiquidity} from "../src/TreasuryLiquidity.sol";
import {NodeDividends} from "../src/NodeDividends.sol";
import {Queue} from "../src/Queue.sol";
import {Referrals} from "../src/Referrals.sol";
import {Router} from "../src/Router.sol";
import {Exchange} from "../src/Exchange.sol";
import {Payback} from "../src/Payback.sol";

//导入要部署的代币
import {Lex} from "../src/token/Lex.sol";
import {Leo} from "../src/token/Leo.sol";
import {Tether} from "../src/mock/Tether.sol";

contract DeployScript is Script {
    address initialRecipient;
    address lexWallet;
    address leoWallet;
    address unstakeWallet;
    address remainingWallet;
    address claimWallet;
    address universalAdmin;
    address queueAdmin;
    address nodeTestAddr0;
    address nodeTestAddr1;

    //已有地址
    address nodeV1;
    address rootAddr;

    //部署代币合约
    Lex public lex;
    Leo public leo;
    Tether public USDT;
    //部署质押合约
    Treasury public treasury;
    TreasuryLiquidity public treasuryLiquidity;
    NodeDividends public nodeDividends;
    Payback public payback;
    Queue public queue;
    Referrals public referrals;
    Router public router;
    Exchange public exchange;

    function setUp() public {
        nodeV1 = vm.envAddress("node_v1");
        rootAddr = vm.envAddress("root_addr");


        initialRecipient = vm.envAddress("initial_recipient");
        universalAdmin = vm.envAddress("universal_admin");
        queueAdmin = vm.envAddress("queue_admin");

        lexWallet = vm.envAddress("lex_wallet");
        leoWallet = vm.envAddress("leo_wallet");
        unstakeWallet = vm.envAddress("unstake_wallet");
        remainingWallet = vm.envAddress("remaining_wallet");
        claimWallet = vm.envAddress("claim_wallet");
        nodeTestAddr0 = vm.envAddress("node_test_addr0");
        nodeTestAddr1 = vm.envAddress("node_test_addr1");
    }

    function run() public {
        vm.startBroadcast();
        vm.txGasPrice(100_000_0000); // 0.05 gwei

        USDT = new Tether(initialRecipient);
        lex = new Lex(initialRecipient, lexWallet, address(USDT));
        leo = new Leo(initialRecipient, leoWallet, address(USDT));

        //部署质押以及相关合约
        deployTreasury();
        deployNodeDividends();
        deployReferrals();
        deployTreasuryLiquidity();
        deployQueue();
        deployPayback();
        deployRouetr();
        deployExchange();

        treasury.setAddrConfig(address(queue), address(treasuryLiquidity));
        referrals.setAddrConfig(address(queue), address(router));
        queue.setAddrConfig(address(router));
        nodeDividends.setAddrConfig(address(treasuryLiquidity));
        treasuryLiquidity.setPaybackAddr(address(payback));

        lex.setAddrConfig(address(treasuryLiquidity), address(payback), address(nodeDividends), address(leo));
        leo.setAddrConfig(address(nodeDividends), address(payback));

        address[] memory addrs = new address[](3);
        addrs[0] = address(lex);
        addrs[1] = address(treasuryLiquidity);
        addrs[2] = address(exchange);
        leo.setAllowlist(addrs, true);

        address[] memory addrsForLex = new address[](1);
        addrsForLex[0] = address(exchange);
        lex.setAllowlist(addrsForLex, true);

        lex.transferOwnership(initialRecipient);
        leo.transferOwnership(initialRecipient);
        router.transferOwnership(universalAdmin);
        add_nodev1_data();

        vm.stopBroadcast();

        console.log("### contract address:");
        console.log("#### Lex token:",address(lex));
        console.log("#### Lex`s pair:",lex.pancakePair());
        console.log("#### Leo token:",address(leo));
        console.log("#### USDT test token:",address(USDT));
        console.log("=========================================================");
        console.log("#### Treasury:",address(treasury));
        console.log("#### TreasuryLiquidity:",address(treasuryLiquidity));
        console.log("#### NodeDividends:",address(nodeDividends));
        console.log("#### Queue:",address(queue));
        console.log("#### Referrals:",address(referrals));
        console.log("#### Router:",address(router));
        console.log("#### Exchange:",address(exchange));
        console.log("#### Payback:",address(payback));
    }


    function deployTreasury() internal{
        // initialize(address unstakeWallet) 
        // setAddrConfig(
        //     address _queue,
        //     address _treasuryLiquidity
        // ) 
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(treasuryImpl.initialize,(unstakeWallet))
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
        // setAddrConfig(address _treasuryLiquidity)
        NodeDividends nodeDividendsImpl = new NodeDividends();
        ERC1967Proxy nodeDividendsProxy = new ERC1967Proxy(
            address(nodeDividendsImpl),
            abi.encodeCall(nodeDividendsImpl.initialize,(address(lex), nodeV1, universalAdmin, address(USDT)))
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
            // address _admin,
            // address _treasury,
            // address _token,
            // address _usdt,
            // address _leo,
            // address _referrals,
            // address _nodeDividends,
            // address _remainingWallet,
            // address _claimWallet
        // ) 
        TreasuryLiquidity impl = new TreasuryLiquidity();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(
                universalAdmin,
                address(treasury),
                address(lex),
                address(USDT),
                address(leo),
                address(referrals),
                address(nodeDividends),
                // address(payback),
                address(remainingWallet),
                address(claimWallet)
            ))
        );
        treasuryLiquidity = TreasuryLiquidity(payable(address(proxy)));
    }

    function deployQueue() internal{
        // initialize(
        // address _admin,
        // address _lex,
        // address _pair,
        // address _USDT,
        // address _treasury, 
        // address _treasuryLiquidity,
        // address _referrals
        // )
        // setAddrConfig(
        //     address _router
        // ) 
        Queue queueImpl = new Queue();
        ERC1967Proxy queueProxy = new ERC1967Proxy(
            address(queueImpl),
            abi.encodeCall(queueImpl.initialize,(
                queueAdmin, 
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

    function deployPayback() internal{
        // initialize(
        //     address _USDT,
        //     address _treasuryLiquidity,
        //     address _lex,
        //     address _leo,
        //     address _admin
        // ) 
        Payback impl = new Payback();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(address(USDT), address(treasuryLiquidity), address(lex), address(leo), universalAdmin))
        );
        payback = Payback(payable(address(proxy)));
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

    function deployExchange() internal{
        // address _lex,
        // address _leo,
        // address _USDT,
        // address _wallet,
        // address _admin
        Exchange impl = new Exchange();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize,(address(lex), address(leo), address(USDT), leoWallet, universalAdmin))
        );
        exchange = Exchange(payable(address(proxy)));
    }

    function add_nodev1_data() internal{
        address[] memory addrs = new address[](2);
        addrs[0] = nodeTestAddr0;
        addrs[1] = nodeTestAddr1;
        nodeDividends.batchAdd(addrs);
    }


}