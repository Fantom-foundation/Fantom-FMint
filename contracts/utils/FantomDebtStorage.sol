pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interface/IPriceOracle.sol";

// FantomDebtStorage implements a debt storage used
// by the Fantom DeFi contract to track debt accounts balances and value.
contract FantomDebtStorage {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Debt related state variables
    // -------------------------------------------------------------

    // _debtBalance tracks user => token => debt amount relationship
    mapping(address => mapping(address => uint256)) public _debtBalance;

    // _debtTotalBalance keeps track of the total debt balances
    // of all the debt tokens registered in the storage
    // mapping: token => debt amount
    mapping(address => uint256) public _debtTotalBalance;

    // _debtTokens represents the list of all collateral tokens
    // registered with the collateral storage.
    address[] public _debtTokens;

    // -------------------------------------------------------------
    // Debt value related calculations
    // -------------------------------------------------------------

    // tokenValue (abstract) returns the value of the given amount of the token specified.
    function tokenValue(address _token, uint256 _amount) public view returns (uint256);

    // debtBalance returns the total value of all the debt tokens
    // registered inside the storage.
    function debtBalance() public view returns (uint256 tBalance) {
        // loop all registered debt tokens
        for (uint i = 0; i < _debtTokens.length; i++) {
            // advance the total value by the current debt balance token value
            tBalance = tBalance.add(tokenValue(_debtTokens[i], _debtTotalBalance[_debtTokens[i]]));
        }

        return tBalance;
    }

    // debtBalanceOf returns the current debt balance of the specified account.
    function debtBalanceOf(address _account) public view returns (uint256 aBalance) {
        // loop all registered debt tokens
        for (uint i = 0; i < _debtTokens.length; i++) {
            // advance the value by the current debt balance tokens on the account token scanned
            if (0 < _debtBalance[_account][_debtTokens[i]]) {
                aBalance = aBalance.add(tokenValue(_debtTokens[i], _debtBalance[_account][_debtTokens[i]]));
            }
        }

        return aBalance;
    }

    // -------------------------------------------------------------
    // Debt state update functions
    // -------------------------------------------------------------

    // debtAdd adds specified amount of tokens to given account
    // debt (e.g. borrow/mint) and updates the total supply references.
    function debtAdd(address _account, address _token, uint256 _amount) internal {
        // update the collateral balance of the account
        _debtBalance[_account][_token] = _debtBalance[_account][_token].add(_amount);

        // update the total debt balance
        _debtTotalBalance[_token] = _debtTotalBalance[_token].add(_amount);

        // make sure the token is registered
        debtEnrollToken(_token);
    }

    // debtSub removes specified amount of tokens from given account
    // debt (e.g. repay) and updates the total supply references.
    function debtSub(address _account, address _token, uint256 _amount) internal {
        // update the debt balance of the account
        _debtBalance[_account][_token] = _debtBalance[_account][_token].sub(_amount);

        // update the total debt balance
        _debtTotalBalance[_token] = _debtTotalBalance[_token].sub(_amount);
    }

    // -------------------------------------------------------------
    // Debt related utility functions
    // -------------------------------------------------------------

    // debtEnrollToken ensures the specified token is in the list
    // of debt tokens registered with the protocol.
    function debtEnrollToken(address _token) internal {
        bool found = false;

        // loop the current list and try to find the token
        for (uint256 i = 0; i < _debtTokens.length; i++) {
            if (_debtTokens[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            _debtTokens.push(_token);
        }
    }

    // debtTokensCount returns the number of tokens enrolled
    // to the debt list.
    function debtTokensCount() public view returns (uint256) {
        // return the current collateral array length
        return _debtTokens.length;
    }
}