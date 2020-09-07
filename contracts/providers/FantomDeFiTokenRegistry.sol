pragma solidity ^0.5.0;

import "../interfaces/IFantomDeFiTokenRegistry.sol";
import "../interfaces/IERC20Detailed.sol";

/**
* This utility contract implements an update aware list of
* DeFi tokens used across Fantom DeFi protocols.
*
* version 0.1.0
* license MIT
* author Fantom Foundation, Jiri Malek
*/
contract FantomDeFiTokenRegistry is IFantomDeFiTokenRegistry {
    // TokenInformation represents a single token handled by the registry.
    // The DeFi API uses this reference to do on-chain tokens tracking.
    struct TokenInformation {
        address token;       // address of the token (unique identifier, ERCDetailed expected)
        string name;         // Name of the token
        string symbol;       // symbol of the token
        uint8 decimals;      // number of decimals of the token
        string logo;         // URL address of the token logo
        address oracle;      // address of the token price oracle
        uint8 priceDecimals; // number of decimals the token's price oracle uses
        bool isActive;       // is this token active in DeFi?
        bool canDeposit;     // is this token available for deposit?
        bool canMint;        // is this token available for minting?
        bool canBorrow;      // is this token available for fLend?
        bool canTrade;       // is this token available for direct fTrade?
    }

    // owner represents the manager address of the registry.
    address public owner;

    // tokens is the list of tokens handled by the registry.
    TokenInformation[] public tokens;

    // TokenAdded event is emitted when a new token information is added to the contract.
    event TokenAdded(address indexed token, string name, uint index);

    // TokenUpdated event is emitted when an existing token information is updated.
    event TokenUpdated(address indexed token, uint index);

    // install new registry instance
    constructor() public {
        owner = msg.sender;
    }

    // ---------------------------------
    // tokens registry view functions
    // ---------------------------------

    // tokensCount returns the total number of tokens in the registry.
    function tokensCount() public view returns (uint256) {
        return tokens.length;
    }

    // tokenIndex finds an index of a token in the tokens list by address; returns -1 if not found.
    function tokenIndex(address _token) public view returns (int256) {
        // loop the list and try to find the token
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].token == _token) {
                return int256(i);
            }
        }
        return - 1;
    }

    // tokenPriceDecimals returns the number of decimal places a price
    // returned for the given token will be encoded to.
    function tokenPriceDecimals(address _token) public view returns (uint8) {
        // try to find the token address in the tokens list
        int256 ix = tokenIndex(_token);
        if (0 > ix) {
        	return 0;
        }

        // return the decimals registered
        return tokens[uint256(ix)].priceDecimals;
    }

    // canMint informs is the specified token can be minted in Fantom DeFi.
	function canMint(address _token) external view returns (bool) {
        // try to find the token address in the tokens list
        int256 ix = tokenIndex(_token);
        if (0 > ix) {
        	return false;
        }

        // return the decimals registered
        return tokens[uint256(ix)].canMint;
	}

    // ---------------------------------
    // tokens management
    // ---------------------------------

    // addToken adds new token into the reference contract.
    function addToken(
        address _token,
        string calldata _logo,
        address _oracle,
        uint8 _priceDecimals,
        bool _isActive,
        bool _canDeposit,
        bool _canMint,
        bool _canBorrow,
        bool _canTrade
    ) external {
        // make sure only owner can do this
        require(msg.sender == owner, "access restricted");

        // try to find the address
        require(0 > tokenIndex(_token), "token already known");

        // pull decimals from the ERC20 token
        uint8 _decimals = IERC20Detailed(_token).decimals();
        require(_decimals > 0, "token decimals invalid");

        // get the token name
        string memory _name = IERC20Detailed(_token).name();

        // add the token to the list
        tokens.push(TokenInformation({
            token : _token,
            name : _name,
            symbol : IERC20Detailed(_token).symbol(),
            decimals : _decimals,
            logo: _logo,
            oracle : _oracle,
            priceDecimals : _priceDecimals,
            isActive : _isActive,
            canDeposit : _canDeposit,
            canMint : _canMint,
            canBorrow : _canBorrow,
            canTrade : _canTrade
            })
        );

        // inform
        emit TokenAdded(_token, _name, tokens.length - 1);
    }

    // updateToken modifies existing token in the reference contract.
    function updateToken(
        address _token,
        string calldata _logo,
        address _oracle,
        uint8 _priceDecimals,
        bool _isActive,
        bool _canDeposit,
        bool _canMint,
        bool _canBorrow,
        bool _canTrade
    ) external {
        // make sure only owner can do this
        require(msg.sender == owner, "access restricted");

        // try to find the address in the tokens list
        int256 ix = tokenIndex(_token);
        require(0 <= ix, "token not known");

        // update token details in the contract
        tokens[uint256(ix)].logo = _logo;
        tokens[uint256(ix)].oracle = _oracle;
        tokens[uint256(ix)].priceDecimals = _priceDecimals;
        tokens[uint256(ix)].isActive = _isActive;
        tokens[uint256(ix)].canDeposit = _canDeposit;
        tokens[uint256(ix)].canDeposit = _canMint;
        tokens[uint256(ix)].canBorrow = _canBorrow;
        tokens[uint256(ix)].canTrade = _canTrade;

        // inform
        emit TokenUpdated(_token, uint256(ix));
    }
}
