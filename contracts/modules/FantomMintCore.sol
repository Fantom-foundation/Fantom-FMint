pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./FantomMintErrorCodes.sol";
import "./FantomCollateralStorage.sol";
import "./FantomDebtStorage.sol";
import "./FantomMintRewardManager.sol";

// FantomMintCore implements a balance pool of collateral and debt tokens
// for the related Fantom DeFi contract. The collateral part allows notified rewards
// distribution to eligible collateral accounts.
contract FantomMintCore is
            Ownable,
            ReentrancyGuard,
            FantomMintErrorCodes,
            FantomCollateralStorage,
            FantomDebtStorage,
            FantomMintRewardManager
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

    // getPrice (abstract) returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256);

    // getPriceDigitsCorrection (abstract) returns the correction to the calculated
    // ERC20 token value to correct exchange rate digits correction.
    function getPriceDigitsCorrection() public pure returns (uint256);

    // tokenValue calculates the value of the given amount of the token specified.
    // The value is returned in given referential tokens (fUSD).
    // Implements tokenValue() abstract function of the underlying storage contracts.
    function tokenValue(address _token, uint256 _amount) public view returns (uint256) {
        // calculate the value using price Oracle access
        return _amount.mul(getPrice(_token)).div(getPriceDigitsCorrection());
    }

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
    function rewardCanClaim(address _account) public view returns (bool) {
        return isCollateralSufficient(_account, 0, 0, collateralLowestDebtRatio4dec);
    }

    // rewardIsEligible checks if the account is eligible to receive any reward.
    function rewardIsEligible(address _account) internal view returns (bool) {
        return isCollateralSufficient(_account, 0, 0, rewardEligibilityRatio4dec);
    }

    // --------------------------------------------------------------------------
    // Principal balance calculations used by the reward manager to yield rewards
    // --------------------------------------------------------------------------

    // principalBalance returns the total balance of principal token
    // which yield a reward to entitled participants based
    // on their individual principal share.
    function principalBalance() public view returns (uint256) {
        return debtTotal();
    }

    // principalBalanceOf returns the balance of principal token
    // which yield a reward share for this account.
    function principalBalanceOf(address _account) public view returns (uint256) {
        return debtValueOf(_account);
    }

    // -------------------------------------------------------------
    // Collateral management functions below
    // -------------------------------------------------------------

    // deposit receives assets to build up the collateral value.
    // The collateral can be used later to mint tokens inside fMint module.
    // The call does not subtract any fee. No interest is granted on deposit.
    function deposit(address _token, uint256 _amount) public nonReentrant returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure caller has enough balance to cover the deposit
        if (_amount > ERC20(_token).balanceOf(msg.sender)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint deposit pool
        if (_amount > ERC20(_token).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // make sure the token has a value before we accept it as a collateral
        if (getPrice(_token) == 0) {
            return ERR_NO_VALUE;
        }

        // transfer ERC20 tokens from account to the collateral pool
        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // update the reward distribution for the account before the state changes
        rewardUpdate(msg.sender);

        // add the collateral to the account
        collateralAdd(msg.sender, _token, _amount);

        // emit the event signaling a successful deposit
        emit Deposited(_token, msg.sender, _amount);

        // deposit successful
        return ERR_NO_ERROR;
    }

    // withdraw subtracts any deposited collateral token from the contract.
    // The remaining collateral value is compared to the minimal required
    // collateral to debt ratio and the transfer is rejected
    // if the ratio is lower than the enforced one.
    function withdraw(address _token, uint256 _amount) public nonReentrant returns (uint256) {
        // make sure a non-zero value is being withdrawn
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure the withdraw does not exceed collateral balance
        if (_amount > collateralBalance[msg.sender][_token]) {
            return ERR_LOW_BALANCE;
        }

        // does the new state obey the enforced minimal collateral to debt ratio?
        // if the check fails, the collateral withdraw is rejected
        if (!collateralCanDecrease(msg.sender, _token, _amount)) {
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // update the reward distribution for the account before state changes
        rewardUpdate(msg.sender);

        // remove the collateral from account
        collateralSub(msg.sender, _token, _amount);

        // transfer withdrawn ERC20 tokens to the caller
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // signal the successful asset withdrawal
        emit Withdrawn(_token, msg.sender, _amount);

        // withdraw successful
        return ERR_NO_ERROR;
    }
}
