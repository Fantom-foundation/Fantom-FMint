pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "../interfaces/IPriceOracleProxy.sol";
import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomMintTokenRegistry.sol";

// FantomDeFiTokenStorage implements a token pool used by the Fantom
// DeFi fMint protocol to track collateral and debt.
contract FantomDeFiTokenStorage is IFantomDeFiTokenStorage
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Contract initialization, behavior and access control
    // -------------------------------------------------------------

    // addressProvider represents the connection to other fMint contracts.
    IFantomMintAddressProvider public addressProvider;

    // dustAdjustment represents the adjustment added to the value calculation
    // to round the dust
    bool public valueDustAdjustment;

    // constructor initializes a new instance of the module.
    constructor(address _addressProvider, bool _dustAdt) public {
        // keep the address provider connecting contracts together
        addressProvider = IFantomMintAddressProvider(_addressProvider);

        // keep the dust adjustment to value calculations
        valueDustAdjustment = _dustAdt;
    }

    // onlyMinter modifier controls access to sensitive functions
    // to allow only calls from fMint Minter contract.
    modifier onlyMinter() {
        require(msg.sender == address(addressProvider.getFantomMint()), "token storage access restricted");
        _;
    }

    // -------------------------------------------------------------
    // Storage state variables
    // -------------------------------------------------------------

    // balance tracks user => token => token amount relationship
    mapping(address => mapping(address => uint256)) public balance;

    // totalBalance keeps track of the total token balances inside the storage
    // mapping: token => token amount
    mapping(address => uint256) public totalBalance;

    // tokens represents the list of all tokens registered with the storage.
    address[] public tokens;

    // -------------------------------------------------------------
    // Value related calculations
    // -------------------------------------------------------------

    // tokenValue returns the value of the given amount of the token specified.
    function tokenValue(address _token, uint256 _amount) public view returns (uint256 value) {
        // do not calculate anything on zero amount
        if (_amount == 0) {
            return 0;
        }

        // get the token price and price digits correction
        // NOTE: We may want to cache price decimals to save some gas on subsequent calls.
        uint256 price = IPriceOracleProxy(addressProvider.getPriceOracleProxy()).getPrice(_token);
        uint256 priceDigitsCorrection = 10**uint256(IFantomMintTokenRegistry(addressProvider.getTokenRegistry()).priceDecimals(_token));

        // calculate the value and adjust for the dust
        value = _amount.mul(price).div(priceDigitsCorrection);

        // do the dust adjustment to the value calculation?
        if (valueDustAdjustment) {
            value = value.add(1);
        }

        return value;
    }

    // total returns the total value of all the tokens registered inside the storage.
    function total() public view returns (uint256 value) {
        // loop all registered debt tokens
        for (uint i = 0; i < tokens.length; i++) {
            // advance the total value by the current debt balance token value
            value = value.add(tokenValue(tokens[i], totalBalance[tokens[i]]));
        }

        // keep the value
        return value;
    }

    // totalOf returns the value of current balance of specified account.
    function totalOf(address _account) public view returns (uint256 value) {
        // loop all registered debt tokens
        for (uint i = 0; i < tokens.length; i++) {
            // advance the result by the value of current token balance of this token
            value = value.add(tokenValue(tokens[i], balance[_account][tokens[i]]));
        }

        return value;
    }

    // balanceOf returns the balance of the given token on the given account.
    function balanceOf(address _account, address _token) public view returns (uint256) {
        return balance[_account][_token];
    }

    // -------------------------------------------------------------
    // Debt state update functions
    // -------------------------------------------------------------

    // add adds specified amount of tokens to given account
    // and updates the total supply references.
    function add(address _account, address _token, uint256 _amount) public onlyMinter {
        // update the token balance of the account
        balance[_account][_token] = balance[_account][_token].add(_amount);

        // update the total token balance
        totalBalance[_token] = totalBalance[_token].add(_amount);

        // make sure the token is registered
        _enroll(_token);
    }

    // sub removes specified amount of tokens from given account
    // and updates the total balance references.
    function sub(address _account, address _token, uint256 _amount) public onlyMinter {
        // update the balance of the account
        balance[_account][_token] = balance[_account][_token].sub(_amount);

        // update the total
        totalBalance[_token] = totalBalance[_token].sub(_amount);
    }

    // -------------------------------------------------------------
    // Utility functions
    // -------------------------------------------------------------

    // enroll ensures the specified token is in the list
    // of tokens registered with the storage.
    function _enroll(address _token) internal {
        bool found = false;

        // loop the current list and try to find the token
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            tokens.push(_token);
        }
    }

    // tokensCount returns the number of tokens enrolled to the list.
    function tokensCount() public view returns (uint256) {
        return tokens.length;
    }
}