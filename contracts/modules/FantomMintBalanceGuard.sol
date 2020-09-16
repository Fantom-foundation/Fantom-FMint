pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
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

    // minCollateralAmount calculates the minimal amount of given token collateral
    // which will satisfy the minimal collateral to debt ratio.
    // If the account is under-collateralized, it returns the required
    // amount of tokens to balance the account.
    function minCollateralAmount(address _account, address _token) public view returns (uint256) {
        // get token price, make sure not to divide by zero
        (uint256 _price, uint256 _digits) = getExtendedPrice(_token);
        require(_price != 0, "collateral token has no value");

        // calculate current collateral and debt situation
        uint256 cDebtValue = debtValueOf(_account, address(0x0), 0);
        uint256 cCollateralValue = collateralValueOf(_account, address(0x0), 0);

        // get the current balance of the tokens
        uint256 balance = getCollateralPool().balanceOf(_account, _token);

        // what is the minimal collateral value required?
        uint256 minCollateralValue = cDebtValue
        .mul(getCollateralLowestDebtRatio4dec())
        .div(collateralRatioDecimalsCorrection);

        // check if we are safely over the required collateral ratio
        if (minCollateralValue > cCollateralValue) {
            // under-collateralized! calculate how much of this token we need
            // to balance the account to required collateral ratio
            return balance.add(minCollateralValue.sub(cCollateralValue).mul(_digits).div(_price));
        }

        // calculate the excessive value, convert it to the amount of tokens using price
        // and reduce the balance by that amount to get the min amount of tokens allowed
        return balance.sub(cCollateralValue.sub(minCollateralValue).mul(_digits).div(_price));
    }

    // maxDebtAmount calculates the maximal amount of given token debt
    // which will satisfy the minimal collateral to debt ratio.
    function maxDebtAmount(address _account, address _token) public view returns (uint256) {
        // get token price, make sure not to divide by zero
        (uint256 _price, uint256 _digits) = getExtendedPrice(_token);
        require(_price != 0, "collateral token has no value");

        // calculate current collateral and debt situation
        uint256 cDebtValue = debtValueOf(_account, address(0x0), 0);
        uint256 cCollateralValue = collateralValueOf(_account, address(0x0), 0);

        // get the current balance of the tokens
        uint256 balance = getDebtPool().balanceOf(_account, _token);

        // what's the largest possible debt value allowed?
        uint256 maxDebtValue = cCollateralValue
        .mul(collateralRatioDecimalsCorrection)
        .div(getCollateralLowestDebtRatio4dec());

        // check if we are safely over the required collateral ratio
        if (maxDebtValue < cDebtValue) {
            // under-collateralized! calculate how much of this token we need
            // to repay to balance the account to required collateral ratio
            return balance.sub(cDebtValue.sub(maxDebtValue).mul(_digits).div(_price));
        }

        // calculate the excessive value, convert it to the amount of tokens using price
        // and increase the debt by that amount to get the max amount of tokens allowed
        return balance.add(maxDebtValue.sub(cDebtValue).mul(_digits).div(_price));
    }

    // -------------------------------------------------------------
    // Collateral to debt ratio checks below
    // -------------------------------------------------------------

    // isCollateralSufficient checks if collateral value is sufficient
    // to cover the debt (collateral to debt ratio) after
    // predefined adjustments to the collateral and debt values.
    function isCollateralSufficient(address _account, address _token, uint256 _subCollateral, uint256 _addDebt, uint256 ratio) internal view returns (bool) {
        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts including
        // given adjustments to both values as requested.
        uint256 cDebtValue = debtValueOf(_account, _token, _addDebt);
        uint256 cCollateralValue = collateralValueOf(_account, _token, _subCollateral);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue
        .mul(ratio)
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
