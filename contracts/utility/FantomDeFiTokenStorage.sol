pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IPriceOracleProxy.sol";
import "./interfaces/IFantomMintAddressProvider.sol";
import "./interfaces/IFantomDeFiTokenRegistry.sol";

// FantomDeFiTokenStorage implements a token pool used by the Fantom
// DeFi fMint protocol to track collateral and debt.
contract FantomDeFiTokenStorage {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Contract control
    // -------------------------------------------------------------

    // addressProvider represents the connection to other fMint contracts.
    IFantomMintAddressProvider public addressProvider;

    // the lowest possible amount allowed to be added
    uint256 public addMinAllowed = 10**18;

    // the highest possible amount allowed to be added
    uint256 public addMaxAllowed = 10**26;

    // constructor initializes a new instance of the module.
    constructor(address _addressProvider) public {
        // remember the address provider connecting contracts together
        addressProvider = IFantomMintAddressProvider(_addressProvider);
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
    function tokenValue(address _token, uint256 _amount) public view returns (uint256) {
        // do not calculate anything on zero amount
        if (_amount == 0) {
            return 0;
        }

        // get the token price and
        uint256 price = IPriceOracleProxy(addressProvider.getPriceOracleProxy()).getPrice(_token);
        uint256 priceDigitsCorrection = 10**IFantomDeFiTokenRegistry(addressProvider.tokenRegistryAddress()).tokenPriceDecimals(_token);

        // calculate the value
        return _amount.mul(price).div(priceDigitsCorrection);
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

    // valueOf returns the value of current balance of specified account.
    function valueOf(address _account) public view returns (uint256 value) {
        // loop all registered debt tokens
        for (uint i = 0; i < debtTokens.length; i++) {
            // advance the result by the value of current token balance of this token
            value = value.add(tokenValue(debtTokens[i], debtBalance[_account][debtTokens[i]]));
        }

        return value;
    }

    // -------------------------------------------------------------
    // Debt state update functions
    // -------------------------------------------------------------

    // add adds specified amount of tokens to given account
    // debt (e.g. borrow/mint) and updates the total supply references.
    function add(address _account, address _token, uint256 _amount) internal {
        // make sure the amount is within the allowed range
        // this should mitigates the dust manipulation problems
        require(_amount >= addMinAllowed && _amount <= addMaxAllowed, "amount out of allowed range");

        // update the token balance of the account
        balance[_account][_token] = balance[_account][_token].add(_amount);

        // update the total token balance
        totalBalance[_token] = totalBalance[_token].add(_amount);

        // make sure the token is registered
        enroll(_token);
    }

    // sub removes specified amount of tokens from given account
    // and updates the total balance references.
    function sub(address _account, address _token, uint256 _amount) internal {
        // make sure the amount is within the allowed range
        require(_amount > 0, "non-zero amount required");

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
    function enroll(address _token) internal {
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