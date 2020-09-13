pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintCore implements a calculation of different rate steps
// between collateral and debt pools to ensure healthy accounts.
contract FantomMintDebt is FantomMintErrorCodes
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // feePool keeps information about the fee collected from
    // minter internal operations in fMin fee tokens. It's actually part
    // of the users' debt, not a received value.
    // NOTE: No idea what we shall do with the fee pool. Mint and distribute along with rewards maybe?
    uint256 public feePool;

    // fMintFee represents the current value of the minting fee used
    // for minter operations.
    // The value is kept in 4 decimals; 25 = 0.0025 = 0.25%
    uint256 public constant fMintFee = 25;

    // fMintFeeDigitsCorrection represents the value to be used
    // to adjust result decimals after applying fee to a value calculation.
    uint256 public constant fMintFeeDigitsCorrection = 10000;

    // fMintLowestAmountAllowed represents the minimal amount of tokens allowed to be minted.
    uint256 public constant fMintLowestAmountAllowed = 10*18;

    // -------------------------------------------------------------
    // Emitted events definition
    // -------------------------------------------------------------

    // Minted is emitted on confirmed token minting against user's collateral value.
    event Minted(address indexed token, address indexed user, uint256 amount);

    // Repaid is emitted on confirmed token repay of user's debt of the token.
    event Repaid(address indexed token, address indexed user, uint256 amount);

    // -------------------------------------------------------------
    // Abstract function required for the collateral manager
    // -------------------------------------------------------------

    // getDebtPool (abstract) returns the address of debt pool.
    function getDebtPool() public view returns (address);

    // checkDebtCanIncrease (abstract) checks if the specified
    // amount of debt can be added to the account
    // without breaking collateral to debt ratio rule.
    function checkDebtCanIncrease(address _account, address _token, uint256 _amount) public view returns (bool);

    // getPrice (abstract) returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256);

    // getPriceDigitsCorrection (abstract) returns the correction to the calculated
    // ERC20 token value to correct exchange rate digits correction.
    function getPriceDigitsCorrection(address _token) public view returns (uint256);

    // rewardUpdate (abstract) notifies the reward distribution to update state
    // of the given account.
    function rewardUpdate(address _account) public;

    // canMint informs if the given token can be minted in the fMint protocol.
    function canMint(address _token) public view returns (bool);

    // getFeeToken (abstract) returns the address of fee ERC20 token.
    function getFeeToken() public view returns (address);

    // -------------------------------------------------------------
    // Debt management functions below, the actual minter work
    // -------------------------------------------------------------

    // mustMint (wrapper) tries to mint specified amount of tokens
    // and reverts on failure.
    function mustMint (address _token, uint256 _amount) public {
        // make the attempt
        uint256 result = mint(_token, _amount);

        // check low amount condition
        require(result != ERR_LOW_AMOUNT, "amount too low");

        // check minting now enabled for the token condition
        require(result != ERR_MINTING_PROHIBITED, "minting of the token prohibited");

        // check no value condition
        require(result != ERR_NO_VALUE, "token has no value");

        // check low collateral ratio condition
        require(result != ERR_LOW_COLLATERAL_RATIO, "insufficient collateral value");
    }

    // mint allows user to create a specified token against already established
    // collateral. The value of the collateral must be in at least configured
    // ratio to the total user's debt value on minting.
    function mint(address _token, uint256 _amount) public returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount < fMintLowestAmountAllowed) {
            return ERR_LOW_AMOUNT;
        }

        // make sure the requested token can be minted
        if (!canMint(_token)) {
            return ERR_MINTING_PROHIBITED;
        }

        // what is the value of the borrowed token?
        uint256 tokenValue = getPrice(_token);
        if (tokenValue == 0) {
            return ERR_NO_VALUE;
        }

        // make sure the debt can be increased on the account
        if (!checkDebtCanIncrease(msg.sender, _token, _amount)) {
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // update the reward distribution for the account before the state changes
        rewardUpdate(msg.sender);

        // get the pool address
        IFantomDeFiTokenStorage pool = IFantomDeFiTokenStorage(getDebtPool());

        // get fee ERC20 token address
        address feeToken = getFeeToken();

        // add the minted amount to the debt
        pool.add(msg.sender, _token, _amount);

        // calculate the minting fee and store the value we gained by this operation
        // @NOTE: We don't check if the fee can be added to the account debt
        // assuming that if the debt could be increased for the minted account, it could
        // accommodate the fee as well (the collateral slippage is in play).
        uint256 fee = _amount
                        .mul(tokenValue)
                        .mul(fMintFee)
                        .div(fMintFeeDigitsCorrection)
                        .div(getPriceDigitsCorrection(feeToken));
        feePool = feePool.add(fee);

        // add the fee to debt
        pool.add(msg.sender, feeToken, fee);

        // mint the requested balance of the ERC20 token
        // @NOTE: the fMint contract must have the minter privilege on the ERC20 token!
        ERC20Mintable(_token).mint(msg.sender, _amount);

        // emit the minter notification event
        emit Minted(_token, msg.sender, _amount);

        // success
        return ERR_NO_ERROR;
    }

    // mustRepay (wrapper) tries to lower the debt on account by given amount
    // and reverts on failure.
    function mustRepay(address _token, uint256 _amount) public {
        // make the attempt
        uint256 result = repay(_token, _amount);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low balance condition
        require(result != ERR_LOW_BALANCE, "insufficient debt outstanding");

        // check low allowance condition
        require(result != ERR_LOW_ALLOWANCE, "insufficient allowance");
    }

    // repay allows user to return some of the debt of the specified token
    // the repay does not collect any fees and is not validating the user's total
    // collateral to debt position.
    function repay(address _token, uint256 _amount) public returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // get the pool address
        IFantomDeFiTokenStorage pool = IFantomDeFiTokenStorage(getDebtPool());

        // make sure there is enough debt on the token specified (if any at all)
        if (_amount > pool.balanceOf(msg.sender, _token)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint deposit pool
        if (_amount > ERC20(_token).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // burn the tokens returned by the user
        ERC20Burnable(_token).burnFrom(msg.sender, _amount);

        // update the reward distribution for the account before the state changes
        rewardUpdate(msg.sender);

        // clear the repaid amount from the account debt balance
        pool.sub(msg.sender, _token, _amount);

        // emit the repay notification
        emit Repaid(_token, msg.sender, _amount);

        // success
        return ERR_NO_ERROR;
    }
}
