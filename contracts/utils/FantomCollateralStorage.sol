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
    // Price and value related constants
    // -------------------------------------------------------------

    // collateralPriceOracle represents the address of the price
    // oracle aggregate used by the collateral to get
    // the price of a specific token.
    address public constant collateralPriceOracle = address(0x03AFBD57cfbe0E964a1c4DBA03B7154A6391529b);

    // collateralPriceDigitsCorrection represents the correction required
    // for FTM/ERC20 (18 digits) to another 18 digits number exchange
    // through an 8 digits USD (ChainLink compatible) price oracle
    // on any collateral price value calculation.
    uint256 public constant collateralPriceDigitsCorrection = 100000000;

    // -------------------------------------------------------------
    // Collateral related state variables
    // -------------------------------------------------------------

    // _collateral tracks token => user => collateral amount relationship
    mapping(address => mapping(address => uint256)) public _collateralByTokens;

    // _collateralTokens tracks user => token => collateral amount relationship
    mapping(address => mapping(address => uint256)) public _collateralByUsers;

    // _collateralList tracks user => collateral tokens list
    mapping(address => address[]) public _collateralList;

    // _collateralValue tracks user => collateral value
    // in ref. denomination (fUSD). This effectively tokenized the collateral
    // to fUSD like tokens.
    //
    // Please note this is a stored value from the last collateral calculation
    // and may not be accurate due to the ref. denomination exchange
    // rate change. Each active collateral interaction updates this value as part
    // of the action.
    mapping(address => uint256) public _collateralValue;

	// _collateralTotalValue keeps track of the total collateral value
	// of balances of all the collateral accounts registered in the storage
	// based on the most recent collateral value update on each account.
	uint256 private _collateralTotalValue;

    // -------------------------------------------------------------
    // Collateral token management
    // We have to use value of the collateral as the virtual token
    // amount since we do not use single token for collateral only.
    // -------------------------------------------------------------

    // totalSupply returns the total value of all the collateral balanced
    // registered inside the storage based on the most recent update of each
    // account's collateral value.
    function totalSupply() public view returns (uint256) {
        return _collateralTotalValue;
    }

    // balanceOf returns the current stored collateral balance of the specified
    // account based on previous value update.
    function balanceOf(address account) public view returns (uint256) {
        return _collateralValue[account];
    }

    // updateCollateralValueOf updates the collateral value
    function updateCollateralValueOf(address _account) internal {
    	// get the current value
    	uint256 cValue = collateralValue(_account);

    	// update the total collateral value by the difference
    	// between previous and current value of the collateral
    	if (cValue > _collateralValue[_account]) {
    		// increase the collateral value total supply by the difference between
    		// the new and old collateral value
            _collateralTotalValue.add(cValue - _collateralValue[_account]);
    	} else {
    		// subtract lost collateral value from the total total supply balance
    		_collateralTotalValue.sub(_collateralValue[_account] - cValue);
    	}

    	// update account balance
    	_collateralValue[_account] = cValue;
    }

    // -------------------------------------------------------------
    // Collateral related utility functions
    // -------------------------------------------------------------

    // enrolCollateral ensures the specified token
    // is in user's list of collateral tokens for future reference
    // and client side listing purposes.
    function enrolCollateral(address _token, address _owner) internal {
        bool found = false;
        address[] memory list = _collateralList[_owner];

        // loop the current list and try to find the token
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            _collateralList[_owner].push(_token);
        }
    }

    // collateralListCount returns the number of tokens enrolled
    // on the collateral list for the given user.
    function collateralListCount(address _owner) public view returns (uint256) {
        // any collateral at all?
        if (_collateralValue[_owner] == 0) {
            return 0;
        }

        // return the current collateral array length
        return _collateralList[_owner].length;
    }

    // tokenValue calculates the value of the given amount of the token specified.
    // The value is returned in given referential tokens (fUSD).
    function tokenValue(address _token, uint256 _amount) internal view returns (uint256) {
        // get the current exchange rate of the specific token
        uint256 rate = IPriceOracle(collateralPriceOracle).getPrice(_token);

        // calculate the value
        return _amount.mul(rate).div(collateralPriceDigitsCorrection);
    }

    // collateralValue calculates the current value of all collateral assets
    // of a user in the ref. denomination (fUSD).
    function collateralValue(address _user) public view returns (uint256 cValue)
    {
        // loop all registered collateral tokens of the user
        for (uint i = 0; i < _collateralList[_user].length; i++) {
        	// advance the value by the current collateral balance tokens
        	// on the account token scanned
        	cValue.add(tokenValue(_collateralList[_user][i], _collateralByTokens[_collateralList[_user][i]][_user]));
        }

        return cValue;
    }
}