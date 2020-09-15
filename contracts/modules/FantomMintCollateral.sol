pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomMintBalanceGuard.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintCore implements a calculation of different rate steps
// between collateral and debt pools to ensure healthy accounts.
contract FantomMintCollateral is ReentrancyGuard, FantomMintErrorCodes
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

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
    // Abstract function required for the collateral manager
    // -------------------------------------------------------------

    // getCollateralPool (abstract) returns the address of collateral pool.
    function getCollateralPool() public view returns (IFantomDeFiTokenStorage);

    // checkCollateralCanDecrease (abstract) checks if the specified
    // amount of collateral can be removed from account
    // without breaking collateral to debt ratio rule.
    function checkCollateralCanDecrease(address _account, address _token, uint256 _amount) public view returns (bool);

    // getPrice (abstract) returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256);

    // canDeposit (abstract) checks if the given token can be deposited to the collateral pool.
    function canDeposit(address _token) public view returns (bool);

    // rewardUpdate (abstract) notifies the reward distribution to update state
    // of the given account.
    function rewardUpdate(address _account) public;

    // -------------------------------------------------------------
    // Collateral management functions below
    // -------------------------------------------------------------

    // mustDeposit (wrapper) tries to deposit given amount of tokens
    // and reverts on failure.
    function mustDeposit(address _token, uint256 _amount) public nonReentrant {
        // make the attempt
        uint256 result = _deposit(_token, _amount);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check deposit prohibited condition
        require(result != ERR_DEPOSIT_PROHIBITED, "deposit of the token prohibited");

        // check low balance condition
        require(result != ERR_LOW_BALANCE, "insufficient token balance");

        // check missing allowance condition
        require(result != ERR_LOW_ALLOWANCE, "insufficient allowance");

        // check no value condition
        require(result != ERR_NO_VALUE, "token has no value");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // deposit receives assets to build up the collateral value.
    // The collateral can be used later to mint tokens inside fMint module.
    // The call does not subtract any fee. No interest is granted on deposit.
    function deposit(address _token, uint256 _amount) public nonReentrant returns (uint256) {
        return _deposit(_token, _amount);
    }

    // _deposit (internal) does the collateral increase job.
    function _deposit(address _token, uint256 _amount) internal returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure the requested token can be deposited
        if (!canDeposit(_token)) {
            return ERR_DEPOSIT_PROHIBITED;
        }

        // make sure caller has enough balance to cover the deposit
        if (_amount > ERC20(_token).balanceOf(msg.sender)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint collateral pool
        if (_amount > ERC20(_token).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // make sure the token has a value before we accept it as a collateral
        if (getPrice(_token) == 0) {
            return ERR_NO_VALUE;
        }

        // update the reward distribution for the account before the state changes
        rewardUpdate(msg.sender);

        // transfer ERC20 tokens from account to the collateral
        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // add the collateral to the account
        getCollateralPool().add(msg.sender, _token, _amount);

        // emit the event signaling a successful deposit
        emit Deposited(_token, msg.sender, _amount);

        // deposit successful
        return ERR_NO_ERROR;
    }

    // mustWithdraw (wrapper) tries to subtracts any deposited collateral token from the contract
    // and reverts on failure.
    function mustWithdraw(address _token, uint256 _amount) public nonReentrant {
        // make the attempt
        uint256 result = _withdraw(_token, _amount);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low balance condition
        require(result != ERR_LOW_BALANCE, "insufficient collateral balance");

        // check no value condition
        require(result != ERR_NO_VALUE, "token has no value");

        // check low balance condition
        require(result != ERR_LOW_COLLATERAL_RATIO, "insufficient collateral value remains");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // withdraw subtracts any deposited collateral token from the contract.
    // The remaining collateral value is compared to the minimal required
    // collateral to debt ratio and the transfer is rejected
    // if the ratio is lower than the enforced one.
    function withdraw(address _token, uint256 _amount) public nonReentrant returns (uint256) {
        return _withdraw(_token, _amount);
    }

    // _withdraw (internal) does the collateral decrease job.
    function _withdraw(address _token, uint256 _amount) internal returns (uint256) {
        // make sure a non-zero value is being withdrawn
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // get the collateral pool
        IFantomDeFiTokenStorage pool = IFantomDeFiTokenStorage(getCollateralPool());

        // make sure the withdraw does not exceed collateral balance
        if (_amount > pool.balanceOf(msg.sender, _token)) {
            return ERR_LOW_BALANCE;
        }

        // does the new state obey the enforced minimal collateral to debt ratio?
        // if the check fails, the collateral withdraw is rejected
        if (!checkCollateralCanDecrease(msg.sender, _token, _amount)) {
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // update the reward distribution for the account before state changes
        rewardUpdate(msg.sender);

        // remove the collateral from account
        pool.sub(msg.sender, _token, _amount);

        // transfer withdrawn ERC20 tokens to the caller
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // signal the successful asset withdrawal
        emit Withdrawn(_token, msg.sender, _amount);

        // withdraw successful
        return ERR_NO_ERROR;
    }
}
