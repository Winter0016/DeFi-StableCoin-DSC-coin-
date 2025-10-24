// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/Helperconfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMMOUNT_COLLATERAL_REDEEM = 5 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 2000 ether; // which is 2000 stablecoin but in term of blockchain(we've already applied this term in other calculation function like pricefeed,... so we must apply it here too which means we will add e18 after the final result) so 2000 ether means 2000e18
    uint256 public constant AMOUNT_DSC_TO_BURN = 1000 ether;

    function setUp() public {   
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
    }

    // DSCEngine.sol
    function testGetUsdValue()public view{ /// @dev test getUsdValue function
        uint256 ethamount = 15e18;
        uint256 expectedUsd = 30000e18; //15e18 * 2000/ETH
        uint256 actualUsd = dsce.getUsdValue(weth,ethamount);
        assertEq(expectedUsd,actualUsd);
    }
    function testGetTokenAmountFromUsd()public view{ ///@dev test getTokenAmountFromUsd function
        uint256 usdamountinwei = 100 ether; //100e18
        //2000$ per eth => 100 dollars = 0.05 weth
        uint256 expectedWeth = 0.05 ether; //0.05e18
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth,usdamountinwei);
        assertEq(expectedWeth, actualWeth);
    }
    function testRevertsIfCollateralZero() public{ ///@dev test depositCollateral function revert is collateral of user is 0
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }
    address[] public tokenaddresses;
    address[] public pricefeedaddresses;
    function testRevertIfTokenLengthDoesntMatchPriceFeeds()public{ ///@dev test constructor token length condition.
        tokenaddresses.push(weth);
        pricefeedaddresses.push(ethUsdPriceFeed);
        pricefeedaddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenaddresses,pricefeedaddresses,address(dsc));
    }
    function testRevertsifTokenaddressisInvalid()public{ ///@dev test isallowedtoken condition modifier
        ERC20Mock randomToken = new ERC20Mock();
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        dsce.depositCollateral(address(randomToken),AMMOUNT_COLLATERAL);
    }
    modifier depositedCollateral(){
        uint256 balanceofuser = ERC20Mock(weth).balanceOf(address(USER));
        console.log("Wethbalanceofuser before deposit: ",balanceofuser);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    modifier redeemCollateral(){
        vm.startPrank(USER);
        dsce.redeemCollateral(weth,AMMOUNT_COLLATERAL_REDEEM);
        vm.stopPrank();
        _;
    }
    modifier mintDSC(){
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }
    modifier burnDSC(){
        uint256 UserDscbalance = ERC20Mock(address(dsc)).balanceOf(address(USER));
        console.log("DSCBalanceOfUser after minted: ",UserDscbalance);
        vm.startPrank(USER);
        dsce.burnDsc(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{ ///@dev test DepositCollateral function: user can fully deposit collateral
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER); //get the value in usd of collateral

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // get the amount of collateral based on the usd above => to check if this is equal to the amount of collateral we put it in the first place
        assertEq(totalDscMinted,expectedTotalDscMinted);
        assertEq(AMMOUNT_COLLATERAL,expectedDepositAmount);
    }
    function testCanRedeemCollateral()public depositedCollateral redeemCollateral{ ///@dev test RedeemCollateral function 
        uint256 DSCEngineWethAfterUserRedeemed = ERC20Mock(weth).balanceOf(address(dsce));
        console.log("DSCEngine balance: ",DSCEngineWethAfterUserRedeemed);
        uint256 expected_user_weth_after_redeemed = 5 ether;
        uint256 user_weth_after_redeemed = ERC20Mock(weth).balanceOf(address(USER));
        assertEq(user_weth_after_redeemed, expected_user_weth_after_redeemed);
    }
    function testIfUserCanMintDSC() public depositedCollateral mintDSC{ ///@dev test MintDsc function
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted,AMOUNT_DSC_TO_MINT);
    }
    function testCalculateHealthFactorIsFine() public view {
        uint256 healthfactortest = dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT,AMMOUNT_COLLATERAL,weth);
        console.log("HealthfactorTest : ",healthfactortest);
        console.log("minhealth: ",dsce.getMinHealthFactor());
        assertGt(healthfactortest, dsce.getMinHealthFactor(), "Health factor should be above minimum");
    }
    function testIfUserCanBurnDsc()public depositedCollateral mintDSC burnDSC{
        uint256 UserDscbalance = ERC20Mock(address(dsc)).balanceOf(address(USER));
        console.log("DSCBalanceOfUser after burned some dsc: ",UserDscbalance);
    }
}