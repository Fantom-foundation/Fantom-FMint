pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../interfaces/IFMintTokenRegistryProvider.sol";

/**
* This contract provides details to the tokens
* available in Fantom DeFi protocols.
*
* @version 0.1.0
* @license MIT
* @author Fantom Foundation, Jiri Malek
*/
contract FMintTokenRegistryProvider is Ownable, IFmintTokenRegistryProvider {
    // TokenInformation represents a single token handled by the provider.
    // The DeFi API uses this reference to do on-chain tokens tracking.
    struct TokenInformation {
        address token;      // address of the token (unique identifier)
        string name;        // Name of the token
        string symbol;      // symbol of the token
        string logo;        // URL address of the token logo
        uint8 decimals;     // number of decimals the token itself uses
        uint8 priceDecimals;// number of decimals the token's price oracle uses
        bool isActive;      // is this token active in DeFi?
        bool canDeposit;    // is this token available for pool deposit?
        bool canMint;       // is this token available for minting?
        bool canBorrow;     // is this token available for fLend?
        bool canTrade;      // is this token available for direct fTrade?
        uint volatility;    // what is the index of volatility of the token in 8 decimals
    }

}