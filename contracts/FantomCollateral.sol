pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./IPriceOracle.sol";

// FantomCollateral implements a collateral pool
// for the related Fantom DeFi contract. The collateral is used
// to manage tokens referenced on the balanced Defi functions.
contract FantomCollateral is Ownable, ReentrancyGuard {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

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
    // in ref. denomination (fUSD).
    // Please note this is a stored value from the last collateral calculation
    // and may not be accurate due to the ref. denomination exchange
    // rate change.
    mapping(address => uint256) public _collateralValue;

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
    // Emited events defition
    // -------------------------------------------------------------

    // Deposited is emitted on token received to deposit
    // increasing user's collateral value.
    event Deposited(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // Withdrawn is emitted on confirmed token withdraw
    // from the deposit decreasing user's collateral value.
    event Withdrawn(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // -------------------------------------------------------------
    // Price and value calculation related utility functions
    // -------------------------------------------------------------

    // collateralPriceOracle returns the address of the price
    // oracle aggregate used by the collateral to get
    // the price of a specific token.
    function collateralPriceOracle() public pure returns (address) {
        return address(0x03AFBD57cfbe0E964a1c4DBA03B7154A6391529b);
    }

    // collateralPriceDigitsCorrection returns the correction required
    // for FTM/ERC20 (18 digits) to another 18 digits number exchange
    // through an 8 digits USD (ChainLink compatible) price oracle
    // on any collateral price value calculation.
    function collateralPriceDigitsCorrection() public pure returns (uint256) {
        // 10 ^ (srcDigits - (dstDigits - priceDigits))
        // return 10 ** (18 - (18 - 8));
        return 100000000;
    }

    // collateralNativeToken returns the identification of native
    // tokens as recognized by the DeFi module.
    function collateralNativeToken() public pure returns (address) {
        return address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
    }

    // collateralLowestDebtRatio4dec represents the lowest ratio between
    // collateral value and debt value allowed for the user.
    // User can not withdraw his collateral if the active ratio would
    // drop below this value.
    // The value is returned in 4 decimals, e.g. value 30000 = 3.0
    function collateralLowestDebtRatio4dec() public pure returns (uint256) {
        return 30000;
    }

    // collateralRatioDecimalsCorrection represents the value to be used
    // to adjust result decimals after applying ratio to a value calculation.
    function collateralRatioDecimalsCorrection() public pure returns (uint256) {
        return 10000;
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

    // collateralListCount returns the number of tokens enroled
    // on the collateral list for the given user.
    function collateralListCount(address _owner) public view returns (uint256) {
        // any collateral at all?
        if (_collateralValue[_owner] == 0) {
            return 0;
        }

        // return the current collateral array length
        return _collateralList[_owner].length;
    }

    // collateralValue calculates the current value of all collateral assets
    // of a user in the ref. denomination (fUSD).
    function collateralValue(address _user) public view returns (uint256 cValue)
    {
        // loop all registered collateral tokens of the user
        for (uint i = 0; i < _collateralList[_user].length; i++) {
            // get the current exchange rate of the specific token
            uint256 rate = IPriceOracle(collateralPriceOracle())
                                .getPrice(_collateralList[_user][i]);

            // add the asset token value to the total;
            // the amount is corrected for the oracle price precision digits.
            // the asset amount is taken from the mapping
            // _collateralByTokens: token address => owner address => amount
            cValue = cValue.add(
                _collateralByTokens[_collateralList[_user][i]][_user]
                .mul(rate)
                .div(collateralPriceDigitsCorrection())
            );
        }

        return cValue;
    }

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

    // debtListCount returns the number of tokens enroled
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
            uint256 rate = IPriceOracle(collateralPriceOracle())
                                .getPrice(_debtList[_user][i]);

            // add the asset token value to the total;
            // the amount is corrected for the oracle price precision digits
            // the asset amount is taken from the mapping
            // _debtByTokens: token address => owner address => amount
            cValue = cValue.add(
                _debtByTokens[_debtList[_user][i]][_user]
                .mul(rate)
                .div(collateralPriceDigitsCorrection())
            );
        }

        return cValue;
    }

    // -------------------------------------------------------------
    // Collateral management functions below
    // -------------------------------------------------------------

    // deposit receives assets (any token including native FTM)
    // to build up the collateral value.
    // The collateral can be used later to mint tokens inside fMint module.
    // The call does not subtract any fee. No interest is granted on deposit.
    function deposit(address _token, uint256 _amount) external payable nonReentrant
    {
        // make sure a non-zero value is being deposited
        require(_amount > 0, "non-zero amount required");

        // if this is a non-native token, verify that the user
        // has enough balance of the ERC20 token to send
        // the specified amount to the deposit
        if (_token != collateralNativeToken()) {
            require(msg.value == 0, "native tokens not expected");
            require(_amount <= ERC20(_token).balanceOf(msg.sender), "not enough balance");
        } else {
            // on native tokens, the designated amount deposited must match
            // the native tokens attached to this transaction
            require(msg.value == _amount, "invalid native tokens amount received");
        }

        // update the collateral value storage
        _collateralByTokens[_token][msg.sender] = _collateralByTokens[_token][msg.sender].add(_amount);
        _collateralByUsers[msg.sender][_token] = _collateralByUsers[msg.sender][_token].add(_amount);

        // make sure the token is on the list
        // of collateral tokens for the sender
        enrolCollateral(_token, msg.sender);

        // re-calculate the current value of the whole collateral deposit
        // across all assets kept
        _collateralValue[msg.sender] = collateralValue(msg.sender);

        // native tokens were already received along with the trx
        // ERC20 tokens must be transferred from user to the local pool
        // NOTE: allowance must be granted by the owner of the token
        // to the contract first to enable this transfer.
        if (_token != collateralNativeToken()) {
            ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // emit the event signaling a successful deposit
        emit Deposited(_token, msg.sender, _amount, block.timestamp);
    }

    // withdraw subtracts any deposited collateral token, including native FTM,
    // that has a value, from the contract.
    // The remaining collateral value is compared to the minimal required
    // collateral to debt ratio and the transfer is rejected
    // if the ratio is lower than the enforced one.
    function withdraw(address _token, uint256 _amount) external nonReentrant {
        // make sure the requested withdraw amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // update collateral value of the token to a new value
        // we don't need to check the current balance against
        // the requested withdrawal; the SafeMath does that validation
        // for us inside the <sub> call.
        _collateralByTokens[_token][msg.sender] =
            _collateralByTokens[_token][msg.sender].sub(_amount, "withdraw exceeds balance");

        _collateralByUsers[msg.sender][_token] =
            _collateralByUsers[msg.sender][_token].sub(_amount, "withdraw amount exceeds balance");

        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts
        uint256 cDebtValue = debtValue(msg.sender);
        uint256 cCollateralValue = collateralValue(msg.sender);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue
                                        .mul(collateralLowestDebtRatio4dec())
                                        .div(collateralRatioDecimalsCorrection());

        // does the new state obey the enforced minimal collateral to debt ratio?
        // if the check fails, the collateral withdraw is rejected
        require(cCollateralValue >= minCollateralValue, "collateral value below allowed ratio");

        // the new collateral value is ok; update the stored collateral and debt values
        _collateralValue[msg.sender] = cCollateralValue;
        _debtValue[msg.sender] = cDebtValue;

        // is this a native token or ERC20 withdrawal?
        if (_token != collateralNativeToken()) {
            // transfer the requested amount of ERC20 tokens from the local pool to the caller
            ERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            // native tokens are being withdrawn; transfer the requested amount
            // we transfer control to the recipient here, so we have to mittigate re-entrancy
            // solhint-disable-next-line avoid-call-value
            (bool success,) = msg.sender.call.value(_amount)("");
            require(success, "unable to send withdraw");
        }

        // signal the successful asset withdrawal
        emit Withdrawn(_token, msg.sender, _amount, block.timestamp);
    }
}
