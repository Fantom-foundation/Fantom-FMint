pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/math/Math.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomMintBalanceGuard.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintBalanceGuard implements a calculation of different rate steps
// between collateral and debt pools to ensure healthy accounts.
contract FantomMintBalanceGuard is FantomMintErrorCodes, IFantomMintBalanceGuard
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Price and value calculation related parameters
    // -------------------------------------------------------------

    // getCollateralLowestDebtRatio4dec (abstract) represents the lowest ratio between
    // collateral value and debt value allowed for the user.
    // User can not withdraw his collateral if the active ratio would
    // drop below this value.
    function getCollateralLowestDebtRatio4dec() public view returns (uint256);

    // getRewardEligibilityRatio4dec (abstract) represents the collateral to debt ratio user has to have
    // to be able to receive rewards.
    function getRewardEligibilityRatio4dec() public view returns (uint256);

    // collateralRatioDecimalsCorrection represents the value to be used
    // to adjust result decimals after applying ratio to a value calculation.
    uint256 public constant collateralRatioDecimalsCorrection = 10000;

    // -------------------------------------------------------------
    // Emitted events definition
    // -------------------------------------------------------------

    // Deposited is emitted on token received to deposit
    // increasing user's collateral value.
    event Deposited(address indexed token, address indexed user, uint256 amount);

    // Withdrawn is emitted on confirmed token withdraw
    // from the deposit decreasing user's collateral value.
    event Withdrawn(address indexed token, address indexed user, uint256 amount);

    // -------------------------------------------------------------
    // Token value related functions
    // -------------------------------------------------------------

    // debtValueOf (abstract) returns the value of account debt.
    function debtValueOf(address _account, address _token, uint256 _add) public view returns (uint256);

    // collateralValueOf (abstract) returns the value of account collateral.
    function collateralValueOf(address _account, address _token, uint256 _sub) public view returns (uint256);

    // getExtendedPrice returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination
    // and the number of digits of the price.
    function getExtendedPrice(address _token) public view returns (uint256, uint256);

    // getCollateralPool (abstract) returns the address of collateral pool.
    function getCollateralPool() public view returns (IFantomDeFiTokenStorage);

    // getDebtPool (abstract) returns the address of debt pool.
    function getDebtPool() public view returns (IFantomDeFiTokenStorage);

    // -------------------------------------------------------------
    // Limits of collateral and debt calculations
    // -------------------------------------------------------------

    // maxToWithdraw calculates the max amount of tokens account can withdraw
    // and still obey the given debt to collateral ratio.
    function maxToWithdraw(address _account, address _token, uint256 _ratio) public view returns (uint256) {
        // how many tokens the account has now
        uint256 balance = getCollateralPool().balanceOf(_account, _token);

        // what is the top withdraw amount
        uint256 max = _maxToWithdraw(_account, _token, _ratio);

        // can the account withdraw them all?
        if (balance < max) {
            return balance;
        }
        return max;
    }

    // _maxToWithdraw calculates the max amount of the given token the account can withdraw
    // safely and still obey given debt to collateral ratio.
    function _maxToWithdraw(address _account, address _token, uint256 _ratio) internal view returns (uint256) {
        // get token price, make sure not to divide by zero
        (uint256 _price, uint256 _digits) = getExtendedPrice(_token);
        require(_price != 0, "collateral token has no value");

        // calculate current collateral and debt situation
        uint256 cDebtValue = debtValueOf(_account, address(0x0), 0);
        uint256 cCollateralValue = collateralValueOf(_account, address(0x0), 0);

        // what is the minimal collateral value required?
        uint256 minCollateralValue = cDebtValue
        .mul(_ratio)
        .div(collateralRatioDecimalsCorrection);

        // check if we are safely over the required collateral ratio
        if (cCollateralValue < minCollateralValue) {
            return 0;
        }

        // calculate the excessive value and convert it
        // to the amount of tokens using price
        return cCollateralValue.sub(minCollateralValue).mul(_digits).div(_price);
    }

    // minToDeposit calculates the minimal amount of tokens the account needs to deposit
    // to get over the given collateral to debt ratio.
    function minToDeposit(address _account, address _token, uint256 _ratio) public view returns (uint256) {
        // get token price, make sure not to divide by zero
        (uint256 _price, uint256 _digits) = getExtendedPrice(_token);
        require(_price != 0, "collateral token has no value");

        // calculate current collateral and debt situation
        uint256 cDebtValue = debtValueOf(_account, address(0x0), 0);
        uint256 cCollateralValue = collateralValueOf(_account, address(0x0), 0);

        // what's the largest possible debt value allowed?
        // what is the minimal collateral value required?
        uint256 minCollateralValue = cDebtValue
        .mul(_ratio)
        .div(collateralRatioDecimalsCorrection);

        // check if we are safely over the required collateral ratio
        // if so, there is no need to add anything to get over
        if (minCollateralValue < cCollateralValue) {
            return 0;
        }

        // calculate the required extra tokens to be deposited to get
        // the ratio the call asked for; round all corners up
        return (minCollateralValue.sub(cCollateralValue).add(1)).mul(_digits).div(_price).add(1);
    }

    // maxToMint calculates the maximum amount of tokens the address can mint
    // and still stay safely within the requested collateral to debt ratio.
    function maxToMint(address _account, address _token, uint256 _ratio) public view returns (uint256) {
        // get token price, make sure not to divide by zero
        (uint256 _price, uint256 _digits) = getExtendedPrice(_token);
        require(_price != 0, "collateral token has no value");

        // calculate current collateral and debt situation\
        uint256 cDebtValue = debtValueOf(_account, address(0x0), 0);
        uint256 cCollateralValue = collateralValueOf(_account, address(0x0), 0);

        // what is the minimal collateral value required?
        uint256 minCollateralValue = cDebtValue
        .mul(_ratio)
        .div(collateralRatioDecimalsCorrection);

        // if the account is under-collateralized already,
        // no tokens can be added
        if (cCollateralValue < minCollateralValue) {
            return 0;
        }

        // what's the largest possible debt amount allowed?
        return cCollateralValue
        .sub(minCollateralValue)
        .mul(collateralRatioDecimalsCorrection)
        .div(getCollateralLowestDebtRatio4dec()).sub(1)
        .mul(_digits)
        .div(_price);
    }

    // -------------------------------------------------------------
    // Collateral to debt ratio checks below
    // -------------------------------------------------------------

    // isCollateralSufficient checks if collateral value is sufficient
    // to cover the debt (collateral to debt ratio) after
    // predefined adjustments to the collateral and debt values.
    function isCollateralSufficient(address _account, address _token, uint256 _subCollateral, uint256 _addDebt, uint256 _ratio) internal view returns (bool) {
        // make sure the call does not try to pull out more than the balance we have
        if (_subCollateral > getCollateralPool().balanceOf(_account, _token)) {
            return false;
        }

        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts including
        // given adjustments to both values as requested.
        uint256 cDebtValue = debtValueOf(_account, _token, _addDebt);
        uint256 cCollateralValue = collateralValueOf(_account, _token, _subCollateral);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue
        .mul(_ratio)
        .div(collateralRatioDecimalsCorrection);

        // final collateral value must match the minimal value or exceed it
        return (cCollateralValue >= minCollateralValue);
    }

    // collateralCanDecrease checks if the specified amount of collateral can be removed from account
    // without breaking collateral to debt ratio rule.
    function collateralCanDecrease(address _account, address _token, uint256 _amount) public view returns (bool) {
        // collateral to debt ratio must be valid after collateral decrease
        return isCollateralSufficient(_account, _token, _amount, 0, getCollateralLowestDebtRatio4dec());
    }

    // debtCanIncrease checks if the specified amount of debt can be added to the account
    // without breaking collateral to debt ratio rule.
    function debtCanIncrease(address _account, address _token, uint256 _amount) public view returns (bool) {
        // collateral to debt ratio must be valid after debt increase
        return isCollateralSufficient(_account, _token, 0, _amount, getCollateralLowestDebtRatio4dec());
    }

    // rewardCanClaim checks if the account can claim accumulated rewards
    // by being on a high enough collateral to debt ratio.
    // Implements abstract function of the <FantomMintRewardManager>.
    function rewardCanClaim(address _account) external view returns (bool) {
        return isCollateralSufficient(_account, address(0x0), 0, 0, getCollateralLowestDebtRatio4dec());
    }

    // rewardIsEligible checks if the account is eligible to receive any reward.
    function rewardIsEligible(address _account) external view returns (bool) {
        return isCollateralSufficient(_account, address(0x0), 0, 0, getRewardEligibilityRatio4dec());
    }
}
