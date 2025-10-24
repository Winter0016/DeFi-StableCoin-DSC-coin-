🏦 DeFi Stablecoin Protocol — Project Overview

This project consists of two main smart contracts:

1️⃣ DecentralizedStableCoin Contract (DSC Token Contract)

Acts as the stablecoin token contract.

Minting and burning can only be performed through the DSCEngine contract.

Represents a decentralized, over-collateralized stablecoin pegged to $1 USD.

Stores user-owned DSC token balances.

2️⃣ DSCEngine Contract (Core Logic Contract)

Handles all core protocol functionality:

Deposit collateral (WETH or WBTC)

Mint DSC tokens

Redeem collateral

Liquidate under-collateralized positions

Only accepts WETH and WBTC from pre-existing contracts deployed on the Sepolia testnet:

WETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81
WBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063


Integrates Chainlink Price Feeds for secure, reliable USD pricing of collateral assets.

Includes a Chainlink data freshness safeguard:

If price feeds have not been updated for more than 3 hours, liquidation operations become temporarily blocked.

This is currently implemented only for liquidation, but will be extended to minting, depositing, and redeeming collateral.