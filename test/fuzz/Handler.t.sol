// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call function

pragma solidity ^0.8.18;
import {Test,console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test{
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; //the max uint96 value
    address public USER = makeAddr("user");
    MockV3Aggregator public ethUsdPriceFeeds;
    constructor(DSCEngine _dscEngine,DecentralizedStableCoin _dsc){
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeeds = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }
    function depositCollateral(uint256 collateralSeed,uint256 amountCollateral) public{
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(USER);
        collateral.mint(USER, amountCollateral);
        collateral.approve(address(dsce),amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed,uint256 amountCollateral)public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(USER,address(collateral));
        if(maxCollateralToRedeem == 0){
            return;
        }
        amountCollateral = bound(amountCollateral,1,maxCollateralToRedeem);
        uint256 amountCollateralInUsdToRedeem = dsce.getUsdValue(address(collateral), amountCollateral);
        (uint256 TotalDscMinted,uint256 TotalusdvalueOfUsersCollateral) = dsce.getAccountInformation(address(USER));
        if((TotalusdvalueOfUsersCollateral - amountCollateralInUsdToRedeem) / 2 < TotalDscMinted ){
            return;
        }
        vm.startPrank(USER);
        dsce.redeemCollateral(address(collateral),amountCollateral);
        vm.stopPrank();
    }
    function mintDsc(uint256 amountDscToMint)public{
        (uint256 TotalDscMinted,uint256 usdvalueOfUsersCollateral) = dsce.getAccountInformation(address(USER));
        uint256 maxMintable = (usdvalueOfUsersCollateral / 2) - TotalDscMinted;
        if (maxMintable <= 0) {
            return;
        }
        amountDscToMint = bound(amountDscToMint,1,maxMintable);
        if(amountDscToMint == 0){
            return;
        }
        vm.startPrank(USER);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();
    }
    // function updateCollateralPrice(uint96 newPrice)public{
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeeds.updateAnswer(newPriceInt);

    // }
    //Helper function
    function _getCollateralFromSeed(uint256 collateralseed) private view returns(ERC20Mock){
        if(collateralseed % 2 == 0){
            return weth;
        }
        return wbtc;
    }
}