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

import {ERC20,ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/// @title Decentralizedstablecoin
/// @author Chau Quang Phuc
/// Minting: Algorithmic
/// Relative stability : Pegged to USD
/// this is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.

contract DecentralizedStableCoin is ERC20Burnable , Ownable{
    error DecentralizedStableCoin_MustBemoreThanZero();
    error DecentralizedStableCoin_BurnAmountExceedsBalance(uint256 balanceofuser,uint256 amountToBurn);
    error DecentralizedStableCoin_ZeroAddress();

    event USER_BALANCE(address indexed user);
    event USER_LIQUIDATED( address indexed user);

    constructor()ERC20("Phuc stable coin","PH")Ownable(address(msg.sender)) {

    }
    function burn(address user,uint256 _ammount) public onlyOwner{
        uint256 balance = balanceOf(user);
        if(_ammount <=0){
            revert DecentralizedStableCoin_MustBemoreThanZero();
        }
        if(balance < _ammount){
            revert DecentralizedStableCoin_BurnAmountExceedsBalance(balance,_ammount);
        }
        _burn(user,_ammount);
    }
    function mint(address _to,uint256 _ammount) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert DecentralizedStableCoin_ZeroAddress();
        }
        if(_ammount<=0){
            revert DecentralizedStableCoin_MustBemoreThanZero();
        }
        _mint(_to,_ammount);
        return true;
    }
    function balanceofuser()external returns(uint256) {
        emit USER_BALANCE(msg.sender);
        return balanceOf(msg.sender);
    }
}