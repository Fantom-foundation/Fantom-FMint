pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomMintBalanceGuard.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintCore implements a calculation of different rate steps
// between collateral and debt pools to ensure healthy accounts.
contract FantomMintBalanceGuard is Ownable, ReentrancyGuard, FantomMintErrorCodes, IFantomMintBalanceGuard
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Price and value calculation related constants
    // -------------------------------------------------------------

    // collateralLowestDebtRatio4dec represents the lowest ratio between
    // collateral value and debt value allowed for the user.
    // User can not withdraw his collateral if the active ratio would
    // drop below this value.
    // The value is returned in 4 decimals, e.g. value 30000 = 3.0
    uint256 public constant collateralLowestDebtRatio4dec = 30000;

    // collateralRatioDecimalsCorrection represents the value to be used
    // to adjust result decimals after applying ratio to a value calculation.
    uint256 public constant collateralRatioDecimalsCorrection = 10000;

    // rewardEligibilityRatio4dec represents the collateral to debt ratio user has to have
    // to be able to receive rewards.
    // The value is kept in 4 decimals, e.g. value 50000 = 5.0
    uint256 public constant rewardEligibilityRatio4dec = 50000;

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
    function debtValueOf(address _account) public view returns (uint256);

    // collateralValueOf (abstract) returns the value of account collateral.
    function collateralValueOf(address _account) public view returns (uint256);

    // tokenValue (abstract) calculates the value of the given amount of the token specified.
    function tokenValue(address _token, uint256 _amount) public view returns (uint256);

    // -------------------------------------------------------------
    // Collateral to debt ratio checks below
    // -------------------------------------------------------------

    // isCollateralSufficient checks if collateral value is sufficient
    // to cover the debt (collateral to debt ratio) after
    // predefined adjustments to the collateral and debt values.
    function isCollateralSufficient(address _account, uint256 subCollateral, uint256 addDebt, uint256 ratio) internal view returns (bool) {
        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts including
        // given adjustments to both values as requested.
        uint256 cDebtValue = debtValueOf(_account).add(addDebt);
        uint256 cCollateralValue = collateralValueOf(_account).sub(subCollateral);

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
        return isCollateralSufficient(_account, tokenValue(_token, _amount), 0, collateralLowestDebtRatio4dec);
    }

    // debtCanIncrease checks if the specified amount of debt can be added to the account
    // without breaking collateral to debt ratio rule.
    function debtCanIncrease(address _account, address _token, uint256 _amount) public view returns (bool) {
        // collateral to debt ratio must be valid after debt increase
        return isCollateralSufficient(_account, 0, tokenValue(_token, _amount), collateralLowestDebtRatio4dec);
    }

    // rewardCanClaim checks if the account can claim accumulated rewards
    // by being on a high enough collateral to debt ratio.
    // Implements abstract function of the <FantomMintRewardManager>.
    function rewardCanClaim(address _account) external view returns (bool) {
        return isCollateralSufficient(_account, 0, 0, collateralLowestDebtRatio4dec);
    }

    // rewardIsEligible checks if the account is eligible to receive any reward.
    function rewardIsEligible(address _account) external view returns (bool) {
        return isCollateralSufficient(_account, 0, 0, rewardEligibilityRatio4dec);
    }
}
