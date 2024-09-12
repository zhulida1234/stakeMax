// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RewardToken} from "../token/RewardToken.sol";
import {MaxStake} from "../MaxStake.sol";
import {CupToken} from "../token/CupToken.sol";
import {SalesFactory} from "../factory/SalesFactory.sol";

contract MTest is Test {

    uint256 mainnetFork;
    address account1;
    address _pancakeFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address _pancakeRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    uint256 constant ONE_DAY = 86400;

    function setUp() public {
        // vm.createSelectFork("https://bsc-dataseed.bnbchain.org");
        //anvil --fork-url=https://bsc-dataseed.bnbchain.org --block-time 3
        //anvil --fork-url=https://binance.llamarpc.com --block-time 3
        //anvil --fork-url=https://bsc-rpc.publicnode.com --block-time 3
        //ganache-cli --fork https://binance.llamarpc.com

        mainnetFork = vm.createFork("https://bsc-dataseed.bnbchain.org");

    }


    function test_pancake() public {
        vm.selectFork(mainnetFork);
        //deployed mint token
        address account = createAccount("tom");
        vm.startPrank(account1);
        //部署RewardToken并mint
        RewardToken reward = new RewardToken();
        reward.mint(account, 10e37);
        //初始化MaxStake
        MaxStake maxstake = new MaxStake();
        maxstake.initialize(address(reward), 10, block.timestamp, block.timestamp + ONE_DAY);
        address maxstakeAddress = address(maxstake);
        console.log("maxstake:", maxstakeAddress);
        //授权
        reward.approve(maxstakeAddress, 10e37);
        //注入奖励
        maxstake.fund(10e37);
        //部署Cup
        CupToken reward = new CupToken();
        reward.mint(account, 10e37);

        //部署 SalesFactory
        SalesFactory saleFactory = new SalesFactory(maxstakeAddress);

        saleFactory.deploySale();

        vm.stopPrank();
    }


    function createAccount(string memory name) public returns (address) {
        address test = makeAddr(name);
//        deal(WBNB, test, 10 ether);
//        deal(BUSD, test, 1000 ether);
        vm.deal(test, 100 ether);
        return test;
    }


}

