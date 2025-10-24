// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracaleLib.sol";

/// @title DSCEngine
/// @author Chau Quang Phuc
/// The system is designed to be as minal as possible, and have the tokens maintain a 1 token == $1 peg
/// this is stablecoin has the properties:
// exogenous collateral
// dollar pegged
// algorithmically stable

// it is similar to DAI if DAI had no governance , no fees and was only backend by WETH and WBTC


contract DSCEngine is ReentrancyGuard{

    //errors
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine_AmountRedeemsExceedsBalance(uint256 balance,uint256 requested);
    error DSCEngine_BreakHealthFactor(uint256 healthfactor);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOK();
    error DSCEngine_HealthFactorNotImproved();
    //erros

    using OracleLib for AggregatorV3Interface;

    //state variable

    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATE_THRESHOLD = 50; //check note2 about the explanation of liquidate!
    uint256 private constant LIQUIDATE_PRECISION = 100;
    uint256 private constant LIQUIDATE_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping (address token => address priceFeed) private 
    s_priceFeeds; //token => (weth contract or wbtc contract)
    mapping (address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    DecentralizedStableCoin private immutable i_dsc;

    address[] private s_collateralTokens;
 
    //state variable

    //event
    event CollateralDeposited(address indexed user,address indexed token,uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo,address indexed token,uint256 amount );
    //event

    //modifiers
    modifier morethanZero(uint256 amount){
        if(amount == 0){
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine_NotAllowedToken();
        }
    _;
    }

    //modifers

    
    //non view Functions

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address dscAddress
    ){
        if(tokenAddress.length != priceFeedAddress.length){
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for(uint256 i = 0 ; i < tokenAddress.length;i++){
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(address tokencollateraddress , uint256 amountcollateral,uint256 amountdsctomint) external{
        depositCollateral(tokencollateraddress, amountcollateral);
        mintDsc(amountdsctomint);
    }


    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public morethanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant(){ /// @dev tested morethanZero condition and isAllowedToken condition,tested user can fully deposit collateral 
        /* 
        @notice follows CEI
        @param tokenCollateralAddress The address of the token to deposit as collateral
        @param amountCollateral The amount of collateral to deposit
        */
        s_collateralDeposited[msg.sender][tokenCollateralAddress] +=amountCollateral; 
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this),amountCollateral);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
    }
    
    function redeemCollateralForDsc(address tokencollateraladdress,uint256 ammountcollateral,uint256 amountdsctoburn) external{
        burnDsc(amountdsctoburn);
        redeemCollateral(tokencollateraladdress, ammountcollateral);
        //  redeemcollater already check health factor
    }

    function redeemCollateral(address tokencollateraddress,uint256 amountcollateral) public morethanZero(amountcollateral) nonReentrant { ///@dev tested
        /*
        in order to redeem collateral:
        1.health factor must be over 1 after collateral pulled
        DRY: don't repeat yourself
        */
       _redeemCollateral(tokencollateraddress,amountcollateral,msg.sender,msg.sender);
       _revertIfHealthFactorIsBroken(msg.sender);
    }

    // check if the collateral value -> DSC amount. Price feeds, value
    function mintDsc(uint256 amountDscToMint) public morethanZero(amountDscToMint) nonReentrant { ///@dev tested
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if they mminted too much like (150$dsc , 100$eth)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amountDscToMint);
        if(!minted){
            revert DSCEngine_MintFailed();
        }
    }

    // Threshold to let's say 150%
    // $100 worth eth collateral -> drop to $74
    // $50 DSC
    // 74$ worth eth / $50dsc = 148% 
    // =>>>>>>> UNDERCOLLATERALIZED!!!

    // other liquidate see this as an opportunity
    // i'll pay back the $50 DSC -> get all your collateral!
    // this user got $74
    // all they has to do is pay -$50 DSC
    // made $24 by liquidating you (this is ur punishment for you collateral get too low )
    
    // hey, if someone pays back your minted DSC, they can have all your collateral for discount.

    function burnDsc(uint256 amount) public morethanZero(amount){
        _burnDsc(amount,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //i dont think this would ever hit...
    }

    /*
    $100 eth backing $50 DSC
    $20 ETH back $50 DSC <-- DSC isnt worth $1

    if someone is almost undercollateralized,we will pay you to liquidate them!
    75$ backing 50$ DSC
    liquidator takes 75$ backing and burns off the 50$ DSC
     */
    function liquidate(address collateral,address user,uint256 debtToCover) external morethanZero(debtToCover) nonReentrant{
        /*
            @param collateral the erc20 collateral address to liquidate from the user
            @param user the user who has broken the health factor. their _healthfactor should be below min_health_factor
            @param debttocover the amount of dsc you want to to burn to improve the users health factor

            follows CEI:checks,effects,interaction
         */
        //check health factor(do they have enough collateral)
        // revert if they don't
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine_HealthFactorOK();
        }
        // we want to burn their DSC "debt"
        // And take their collateral
        // Bad user: $140 ETH, $100 DSC
        // debttocoer = $100 of DSC == ??? ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // and give them 10% bonus , so we are gving the liqidatte $110 of WETH for 100 DSC
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATE_BONUS) / LIQUIDATE_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        // we need to burn the dsc
        //the liquidater(msg.sender) needs to approve before this function is called
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    //non view Functions


    //private and internal view functions

    /* 
        @dev: low-level internal function, do not call unless the function calling it is checking for healthfactor being broken
    */
    function _burnDsc(uint256 amountDscToBurn,address onBehalfOf,address dscFrom) private{
        s_DSCMinted[onBehalfOf]-= amountDscToBurn;
        if(dscFrom != msg.sender){
            //transferfrom only success if the dscFrom has approved this contract to spend their dsc
            bool success = i_dsc.transferFrom(dscFrom, address(i_dsc), amountDscToBurn);
            if(!success){
                revert DSCEngine_TransferFailed();
            }
        }
        i_dsc.burn(onBehalfOf,amountDscToBurn);
    }

    function _redeemCollateral(address tokencollateraladdress,uint256 amountCollateral,address from,address to)private{ ///@dev tested
        if(s_collateralDeposited[from][tokencollateraladdress] < amountCollateral){
            revert DSCEngine_AmountRedeemsExceedsBalance(s_collateralDeposited[from][tokencollateraladdress], amountCollateral);
        }
       s_collateralDeposited[from][tokencollateraladdress] -= amountCollateral;
       emit CollateralRedeemed(from,to,tokencollateraladdress,amountCollateral);
       // _calculateHealthFactorafter() // most people dont do this cuz ,more gas fee
       bool success = IERC20(tokencollateraladdress).transfer(to, amountCollateral);
       if(!success){
        revert DSCEngine_TransferFailed();
       }
       _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation (address user) private view returns(uint256 totalDscMinted, uint256 TotalcollateralValueInUsd){
        totalDscMinted = s_DSCMinted[user];
        TotalcollateralValueInUsd = getAccountCOllateralValueInUsd(user);
    }

    function _healthFactor(address user)private view returns(uint256){
        /*
        returns how close to liquidate a user is
        if a user goes below 1 , then they can get liquidated
        */
       // Total DSC minted
       //  total collateral VALUE
       (uint256 totalDscMinted,uint256 TotalcollateralValueInUSD) = _getAccountInformation(user);
        if(totalDscMinted == 0){
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (TotalcollateralValueInUSD * LIQUIDATE_THRESHOLD) / LIQUIDATE_PRECISION;
        //$150 ETH / 100 DSC = 1.5
        // 150 * 50 = 7500/100 = 75/100 < 1

        //$1000 ETH / 100 DSC
        // 1000 * 50 = 5000 / 100 = (500/100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view{
        // 1. check health factor (do they have enough collateral?)
        // 2. revert if they don't have a good health factor

        uint256 Userhealthfactor = _healthFactor(user);
        if(Userhealthfactor < MIN_HEALTH_FACTOR){
            revert DSCEngine_BreakHealthFactor(Userhealthfactor);
        }
    }
    //private and internal view functions


    //public & external VIEW function
    function getTokenAmountFromUsd(address token,uint256 usdAmountInWei) public view returns(uint256){ /// @dev Tested
        // Price of ETH(token)
        // $/Eth Eth ??
        //$2000/eth . $1000 = 0.5 eth
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRound();
        return (usdAmountInWei * PRECISION) / (uint256(price)*ADDITION_FEED_PRECISION);
    }


    function getAccountCOllateralValueInUsd(address user) public view returns(uint256 totalCollateralValueInUsd){ ///@dev tested
        //loop through each collateral token, get the amount they have deposited, and map it to the price to get the USD VALUE

        for(uint256 i = 0;i< s_collateralTokens.length;i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }
    function getUsdValue(address token,uint256 amount) public view returns(uint256){ /// @dev Tested
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // let's say 1 ETH = $1000
        // then the returned value from CL will be 1000 * 1*e8 dollars~ (how i know this? go to price feed address go to etherium network click show more details and find the ETH/USD the decimal output is 8)
        
        return ((uint256(price) * ADDITION_FEED_PRECISION)*amount) / PRECISION; // (1000*1e8*(1e10) * amount) / 1e18 // why multiple 1e10 and divide 1e18 at last,
        /*
            Example:
            - ETH is input as `3 * 1e18` (because all tokens in Solidity use 18 decimals)
            - Price from Chainlink is in 8 decimals (e.g., 1000 * 1e8)
            - To bring price up to 18 decimals, multiply by `ADDITION_FEED_PRECISION = 1e10` (to match solidity decimal)
            - So price becomes `1000 * 1e8 * 1e10 = 1000 * 1e18`

            Now multiply with amount:
            - (1000 * 1e18) * (3 * 1e18) = 3000 * 1e36

            Divide by `PRECISION = 1e18` to normalize back:
            - 3000 * 1e36 / 1e18 = 3000 * 1e18

            Final result: `3000 * 1e18` (i.e., $3000 with 18 decimals)
            
            This ensures no precision is lost, and the result can be used safely in further fixed-point math.

            Key point
            You don’t get the number 3000 as a plain integer, you get 3000e18.

            If you want to show this in a frontend as $3000.00, you'll divide it by 1e18 off-chain (in JavaScript, etc).
        */
    }
    function getAccountInformation(address user) external view returns(uint256 totaldscminted,uint256 collateralvalueinusd){ ///@dev tested
        (totaldscminted,collateralvalueinusd) = _getAccountInformation(user);
    }
    function calculateHealthFactor(uint256 totalDscMinted,uint256 Totalcollateral,address token) external view returns(uint256){ ///@dev tested
        return (getUsdValue(token,Totalcollateral) * PRECISION) / totalDscMinted;
    }
    function getMinHealthFactor() external pure returns(uint256){ ///@dev tested
        return MIN_HEALTH_FACTOR;
    }
    function getCollateralTokens() external view returns(address[]memory){
        return s_collateralTokens;
    }
    function getCollateralBalanceOfUser(address user,address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }
    function getCollateralTokenPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];      
    }

}