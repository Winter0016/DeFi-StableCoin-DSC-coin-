// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {Script} from "forge-std/Script.sol";

import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/Helperconfig.s.sol";


contract DeployDSC is Script{
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run()external returns(DecentralizedStableCoin,DSCEngine,HelperConfig){
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed,address wbtcUsdPriceFeed,address weth,address wbtc,uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth,wbtc];
        priceFeedAddresses = [wethUsdPriceFeed,wbtcUsdPriceFeed];

        if(block.chainid == 11155111){
            vm.startBroadcast();
            DecentralizedStableCoin dsc = new DecentralizedStableCoin();
            DSCEngine engine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
            dsc.transferOwnership((address(engine)));
            vm.stopBroadcast();
            return (dsc,engine,config);
        }else{
            vm.startBroadcast(deployerKey);
            DecentralizedStableCoin dsc = new DecentralizedStableCoin();
            DSCEngine engine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
            dsc.transferOwnership((address(engine)));
            vm.stopBroadcast();
            return (dsc,engine,config);
        }
    }
}