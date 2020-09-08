pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
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
contract FantomDeFiTokenRegistry is Ownable, IFantomDeFiTokenRegistry {
    // TokenInformation represents a single token handled by the registry.
    // The DeFi API uses this reference to do on-chain tokens tracking.
    struct TokenInformation {
        uint256 id;          // Internal id of the token (index starting from 1)
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

    // tokens is the mapping between the token address and it's detailed information.
    mapping(address => TokenInformation) public tokens;

    // tokensList is the list of tokens handled by the registry.
    address[] public tokensList;

    // TokenAdded event is emitted when a new token information is added to the contract.
    event TokenAdded(address indexed token, string name, uint256 index);

    // TokenUpdated event is emitted when an existing token information is updated.
    event TokenUpdated(address indexed token, string name);

    // ---------------------------------
    // tokens registry view functions
    // ---------------------------------

    // tokensCount returns the total number of tokens in the registry.
    function tokensCount() public view returns (uint256) {
        return tokensList.length;
    }

    // tokenPriceDecimals returns the number of decimal places a price
    // returned for the given token will be encoded to.
    function tokenPriceDecimals(address _token) public view returns (uint8) {
        return tokens[_token].priceDecimals;
    }

    // isActive informs if the specified token is active and can be used in DeFi protocols.
    function isActive(address _token) external view returns (bool) {
        return tokens[_token].isActive;
    }

    // canDeposit informs if the specified token can be deposited to collateral pool.
	function canDeposit(address _token) external view returns (bool) {
        return tokens[_token].canDeposit;
	}

    // canMint informs if the specified token can be minted in Fantom DeFi.
    function canMint(address _token) external view returns (bool) {
        return tokens[_token].canMint;
    }

    // canBorrow informs if the specified token can be borrowed in Fantom DeFi.
    function canBorrow(address _token) external view returns (bool) {
        return tokens[_token].canBorrow;
    }

    // canTrade informs if the specified token can be traded directly in Fantom DeFi.
    function canTrade(address _token) external view returns (bool) {
        return tokens[_token].canTrade;
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
    ) external onlyOwner {
        // make sure the token does not exist yet
        require(0 == tokens[_token].id, "token already known");

        // pull decimals from the ERC20 token
        uint8 _decimals = IERC20Detailed(_token).decimals();
        require(_decimals > 0, "token decimals invalid");

        // add the token address to the list
        tokensList.push(_token);

        // get the token name
        string memory _name = IERC20Detailed(_token).name();

        // create and store the token information
        tokens[_token] = TokenInformation({
            id : tokensList.length,
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
        });

        // inform
        emit TokenAdded(_token, _name, tokensList.length - 1);
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
    ) external onlyOwner {
        // make sure the token exists
        require(0 != tokens[_token].id, "token unknown");

        // update token details in the contract
        tokens[_token].logo = _logo;
        tokens[_token].oracle = _oracle;
        tokens[_token].priceDecimals = _priceDecimals;
        tokens[_token].isActive = _isActive;
        tokens[_token].canDeposit = _canDeposit;
        tokens[_token].canDeposit = _canMint;
        tokens[_token].canBorrow = _canBorrow;
        tokens[_token].canTrade = _canTrade;

        // inform
        emit TokenUpdated(_token, tokens[_token].name);
    }
}
