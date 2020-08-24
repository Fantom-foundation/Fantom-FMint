pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interface/IPriceOracle.sol";
import "./utils/FMintErrorCodes.sol";

// FantomCollateralStorage implements a collateral storage used
// by the Fantom Collateral contract to track collateral accounts
// balances and value.
contract FantomCollateralStorage {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Debt related state variables
    // -------------------------------------------------------------

    // _debt tracks token => user => debt amount relationship
    mapping(address => mapping(address => uint256)) public _debtByTokens;

    // _debtTokens tracks user => token => debt amount relationship
    mapping(address => mapping(address => uint256)) public _debtByUsers;

    // _debtList tracks user => debt tokens list
    mapping(address => address[]) public _debtList;

    // _debtValue tracks user => debt value in ref. denomination (fUSD)
    // please note this is a stored value from the last debt calculation
    // and may not be accurate due to the ref. denomination exchange
    // rate change.
    mapping(address => uint256) public _debtValue;

    // -------------------------------------------------------------
    // Debt related utility functions
    // -------------------------------------------------------------

    // enrolDebt ensures the specified token
    // is in user's list of debt tokens for future reference
    // and client side listing purposes.
    function enrolDebt(address _token, address _owner) internal {
        bool found = false;
        address[] memory list = _debtList[_owner];

        // loop the current list and try to find the token
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            _debtList[_owner].push(_token);
        }
    }

    // debtListCount returns the number of tokens enrolled
    // on the debt list for the given user.
    function debtListCount(address _owner) public view returns (uint256) {
        // any debt at all for the user?
        if (_debtValue[_owner] == 0) {
            return 0;
        }

        // return the current debt array length
        return _debtList[_owner].length;
    }

    // debtValue calculates the current value of all debt assets
    // of a user in the ref. denomination (fUSD).
    function debtValue(address _user) public view returns (uint256 cValue)
    {
        // loop all registered debt tokens of the user
        for (uint i = 0; i < _debtList[_user].length; i++) {
            // get the current exchange rate of the specific token
            uint256 rate = IPriceOracle(collateralPriceOracle)
                                .getPrice(_debtList[_user][i]);

            // add the asset token value to the total;
            // the amount is corrected for the oracle price precision digits
            // the asset amount is taken from the mapping
            // _debtByTokens: token address => owner address => amount
            cValue = cValue.add(
                _debtByTokens[_debtList[_user][i]][_user]
                .mul(rate)
                .div(collateralPriceDigitsCorrection)
            );
        }

        return cValue;
    }
}