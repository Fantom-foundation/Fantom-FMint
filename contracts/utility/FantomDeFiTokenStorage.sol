pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "../interfaces/IFantomDeFiTokenStorage.sol";
import "../interfaces/IPriceOracleProxy.sol";
import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomMintTokenRegistry.sol";

// FantomDeFiTokenStorage implements a token pool used by the Fantom
// DeFi fMint protocol to track collateral and debt.
contract FantomDeFiTokenStorage is Initializable, IFantomDeFiTokenStorage
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

    // onlyMinter modifier controls access to sensitive functions
    // to allow only calls from fMint Minter contract.
    modifier onlyMinter() {
        require(msg.sender == address(addressProvider.getFantomMint()), "token storage access restricted");
        _;
    }

    // onlyMinterOrLiquidationManager modifier controls access to sensitive functions
    // to allow only calls from fMint Minter or fLiquidationManager contract.
    modifier onlyMinterOrLiquidationManager() {
        require(msg.sender == address(addressProvider.getFantomMint()) || msg.sender == address(addressProvider.getFantomLiquidationManager()), "token storage access restricted"); 
        _;       
    }

    // initialize initializes the instance of the module.
    function initialize(address _addressProvider, bool _dustAdt) public initializer {
        // keep the address provider connecting contracts together
        addressProvider = IFantomMintAddressProvider(_addressProvider);

        // keep the dust adjustment to value calculations
        valueDustAdjustment = _dustAdt;
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
        uint256 price = addressProvider.getPriceOracleProxy().getPrice(_token);
        uint256 priceDigitsCorrection = 10 ** uint256(addressProvider.getTokenRegistry().priceDecimals(_token));

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
    function totalOf(address _account, bool requireTradable) public view returns (uint256) {
        return _totalOf(_account, address(0x0), 0, 0, requireTradable);
    }

    // totalOfInc returns the value of current balance of an account
    // with specified token balance increased by given amount of tokens.
    function totalOfInc(address _account, address _token, uint256 _amount, bool requireTradable) external view returns (uint256 value) {
        // calculate the total with token balance adjusted up
        return _totalOf(_account, _token, _amount, 0,requireTradable);
    }

    // totalOfDec returns the value of current balance of an account
    // with specified token balance decreased by given amount of tokens.
    function totalOfDec(address _account, address _token, uint256 _amount, bool requireTradable) external view returns (uint256 value) {
        // calculate the total with token balance adjusted down
        return _totalOf(_account, _token, 0, _amount, requireTradable);
    }

    // balanceOf returns the balance of the given token on the given account.
    function balanceOf(address _account, address _token) public view returns (uint256) {
        return balance[_account][_token];
    }

    // _totalOf calculates the value of given account with specified token balance adjusted
    // either up, or down, based on given extra values
    function _totalOf(address _account, address _token, uint256 _add, uint256 _sub, bool requireTradable) internal view returns (uint256 value) {
        // loop all registered debt tokens
        for (uint i = 0; i < tokens.length; i++) {
            // advance the result by the value of current token balance of this token.
            // Make sure to stay on safe size with the _sub deduction, we don't
            // want to drop balance to sub-zero amount, that would freak out the SafeMath.
            if (_token == tokens[i]) {
                uint256 adjustedBalance = balance[_account][tokens[i]].add(_add).sub(_sub, "token sub exceeds balance");

                // add adjusted token balance converted to value
                // NOTE: this may revert on underflow if the _sub value exceeds balance,
                // but it should never happen on normal protocol operations.
                value = value.add(tokenValue(
                        tokens[i],
                        adjustedBalance
                    ));

                // we consumed the adjustment and can reset it
                _add = 0;
                _sub = 0;
            } else {
                // simply add the token balance converted to value as-is
                if (!requireTradable || addressProvider.getTokenRegistry().canTrade(tokens[i])){
                    value = value.add(tokenValue(tokens[i], balance[_account][tokens[i]]));
                }
            }
        }

        // apply increase adjustment if it still remains
        if (_add != 0) {
            value = value.add(tokenValue(_token, _add));
        }

        // apply subtraction adjustment if it still remains
        if (_sub != 0) {
            value = value.sub(tokenValue(_token, _sub));
        }

        return value;
    }

    // -------------------------------------------------------------
    // Debt state update functions
    // -------------------------------------------------------------

    // add adds specified amount of tokens to given account
    // and updates the total supply references.
    function add(address _account, address _token, uint256 _amount) public onlyMinterOrLiquidationManager {
        // update the token balance of the account
        balance[_account][_token] = balance[_account][_token].add(_amount);

        // update the total token balance
        totalBalance[_token] = totalBalance[_token].add(_amount);

        // make sure the token is registered
        _enroll(_token);
    }

    // sub removes specified amount of tokens from given account
    // and updates the total balance references.
    function sub(address _account, address _token, uint256 _amount) public onlyMinterOrLiquidationManager {
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

    // getToken returns the specific token from index.
    function getToken(uint256 _index) public view returns (address) {
        return tokens[_index];
    }
}