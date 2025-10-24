// SPDX-License-Identifier: MIT

// Have our invariants aka properties
/* 
    what are our invariants?
    1. the total supply of dsc should be less than the total value of collateral
    2. Getter view functions should never revert <-- evergreen invariant
    
*/
pragma solidity ^0.8.19;

import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {HelperConfig} from "script/Helperconfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";
contract InvariantsTest is StdInvariant,Test (){
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    address public USER = makeAddr("user");
    uint256 public constant AMMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMMOUNT_COLLATERAL_REDEEM = 5 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 2000 ether; // which is 2000 stablecoin but in term of blockchain(we've already applied this term in other calculation function like pricefeed,... so we must apply it here too which means we will add e18 after the final result) so 2000 ether means 2000e18
    uint256 public constant AMOUNT_DSC_TO_BURN = 1000 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce,dsc);
        targetContract(address(handler)); // telling foundry to go "wild" on this contract, input any random numbers for many cases based on adjustment in foundry.toml,foundry will only go "wild" for public functions
        // hey, don't call redeemcollateral, unless there is acollateral to redeem
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
        //get the value of all the collateral in the protocol
        //compare it to all the debt (dsc)
        console.log("testing the contract");
        uint256 totalSupply = dsc.totalSupply();
        console.log("total supply: ",totalSupply);
        // if (totalSupply == 0) return;
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
 }