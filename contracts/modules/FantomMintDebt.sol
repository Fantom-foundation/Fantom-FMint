pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/math/Math.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "../interfaces/IFantomDeFiTokenStorage.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintCore implements a calculation of different rate steps
// between collateral and debt pools to ensure healthy accounts.
contract FantomMintDebt is Initializable, ReentrancyGuard, FantomMintErrorCodes
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // feePool keeps information about the fee collected from token created
    // in minted tokens denomination.
    // NOTE: No idea what we shall do with the fee pool. Mint and distribute along with rewards maybe?
    mapping(address => uint256) public feePool;

    // fMintFeeDigitsCorrection represents the value to be used
    // to adjust result decimals after applying fee to a value calculation.
    uint256 public constant fMintFeeDigitsCorrection = 10000;

    // initialize initializes the contract properly before the first use.
    function initialize() public initializer {
        ReentrancyGuard.initialize();
    }

    // -------------------------------------------------------------
    // Emitted events definition
    // -------------------------------------------------------------

    // Minted is emitted on confirmed token minting against user's collateral value.
    event Minted(address indexed token, address indexed user, uint256 amount, uint256 fee);

    // Repaid is emitted on confirmed token repay of user's debt of the token.
    event Repaid(address indexed token, address indexed user, uint256 amount);

    // -------------------------------------------------------------
    // Abstract function required for the collateral manager
    // -------------------------------------------------------------

    // getFMintFee4dec (abstract) represents the current percentage of the created tokens
    // captured as a fee.
    // The value is kept in 4 decimals; 50 = 0.005 = 0.5%
    function getFMintFee4dec() public view returns (uint256);

    // getDebtPool (abstract) returns the address of debt pool.
    function getDebtPool() public view returns (IFantomDeFiTokenStorage);

    // checkDebtCanIncrease (abstract) checks if the specified
    // amount of debt can be added to the account
    // without breaking collateral to debt ratio rule.
    function checkDebtCanIncrease(address _account, address _token, uint256 _amount) public view returns (bool);

    // getPrice (abstract) returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256);

    // rewardUpdate (abstract) notifies the reward distribution to update state
    // of the given account.
    function rewardUpdate(address _account) public;

    // canMint checks if the given token can be minted in the fMint protocol.
    function canMint(address _token) public view returns (bool);

    // getMaxToMint (abstract) calculates the maximum amount of given token
    // which will satisfy the given collateral to debt ratio, if added.
    function getMaxToMint(address _account, address _token, uint256 _ratio) public view returns (uint256);

    // -------------------------------------------------------------
    // Debt management functions below, the actual minter work
    // -------------------------------------------------------------

    // mustMint (wrapper) tries to mint specified amount of tokens
    // and reverts on failure.
    function mustMint(address _token, uint256 _amount) public nonReentrant {
        // make the attempt
        uint256 result = _mint(_token, _amount);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low amount condition (fee to amount check)
        require(result != ERR_LOW_AMOUNT, "amount too low");

        // check minting now enabled for the token condition
        require(result != ERR_MINTING_PROHIBITED, "minting of the token prohibited");

        // check no value condition
        require(result != ERR_NO_VALUE, "token has no value");

        // check low collateral ratio condition
        require(result != ERR_LOW_COLLATERAL_RATIO, "insufficient collateral value");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // mint allows user to create a specified token against already established
    // collateral. The value of the collateral must be in at least configured
    // ratio to the total user's debt value on minting.
    function mint(address _token, uint256 _amount) public nonReentrant returns (uint256) {
        return _mint(_token, _amount);
    }

    // _mint (internal) does the actual minting of tokens.
    function _mint(address _token, uint256 _amount) internal returns (uint256)
    {
        // make sure a non-zero value is being minted
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure the requested token can be minted
        if (!canMint(_token)) {
            return ERR_MINTING_PROHIBITED;
        }

        // what is the value of the borrowed token?
        if (0 == getPrice(_token)) {
            return ERR_NO_VALUE;
        }

        // make sure the debt can be increased on the account
        if (!checkDebtCanIncrease(msg.sender, _token, _amount)) {
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // calculate the minting fee; the fee is collected from the minted tokens
        // adjust the fee by adding +1 to round the fee up and prevent dust manipulations
        uint256 fee = _amount.mul(getFMintFee4dec()).div(fMintFeeDigitsCorrection).add(1);

        // make sure the fee does not consume the minted amount on dust operations
        if (fee >= _amount) {
            return ERR_LOW_AMOUNT;
        }

        // update the reward distribution for the account before the state changes
        rewardUpdate(msg.sender);

        // add the requested amount to the debt
        getDebtPool().add(msg.sender, _token, _amount);

        // update the fee pool
        feePool[_token] = feePool[_token].add(fee);

        // mint the requested balance of the ERC20 token minus the fee
        // @NOTE: the fMint contract must have the minter privilege on the ERC20 token!
        ERC20Mintable(_token).mint(msg.sender, _amount.sub(fee));

        // emit the minter notification event
        emit Minted(_token, msg.sender, _amount, fee);

        // success
        return ERR_NO_ERROR;
    }

    // mustMintMax tries to increase the debt by maxim allowed amount to stoll satisfy
    // the required debt to collateral ratio. It reverts the transaction if the fails.
    function mustMintMax(address _token, uint256 _ratio) public nonReentrant {
        // try to withdraw max amount of tokens allowed
        uint256 result = _mintMax(_token, _ratio);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low amount condition (fee to amount check)
        require(result != ERR_LOW_AMOUNT, "amount too low");

        // check minting now enabled for the token condition
        require(result != ERR_MINTING_PROHIBITED, "minting of the token prohibited");

        // check no value condition
        require(result != ERR_NO_VALUE, "token has no value");

        // check low collateral ratio condition
        require(result != ERR_LOW_COLLATERAL_RATIO, "insufficient collateral value");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // mintMax tries to increase the debt by maxim allowed amount to stoll satisfy
    // the required debt to collateral ratio.
    function mintMax(address _token, uint256 _ratio) public nonReentrant returns (uint256) {
        return _mintMax(_token, _ratio);
    }

    // _mintMax (internal) does the actual minting of tokens. It tries to mint as much
    // as possible and still obey the given collateral to debt ratio.
    function _mintMax(address _token, uint256 _ratio) internal returns (uint256) {
        return _mint(_token, getMaxToMint(msg.sender, _token, _ratio));
    }

    // mustRepay (wrapper) tries to lower the debt on account by given amount
    // and reverts on failure.
    function mustRepay(address _token, uint256 _amount) public nonReentrant {
        // make the attempt
        uint256 result = _repay(_token, _amount);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low balance condition
        require(result != ERR_LOW_BALANCE, "insufficient debt outstanding");

        // check low allowance condition
        require(result != ERR_LOW_ALLOWANCE, "insufficient allowance");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // repay allows user to return some of the debt of the specified token
    // the repay does not collect any fees and is not validating the user's total
    // collateral to debt position.
    function repay(address _token, uint256 _amount) public nonReentrant returns (uint256) {
        return _repay(_token, _amount);
    }

    // _repay (internal) does the token burning action.
    function _repay(address _token, uint256 _amount) internal returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // get the pool address
        IFantomDeFiTokenStorage pool = getDebtPool();

        // make sure there is enough debt on the token specified (if any at all)
        if (_amount > pool.balanceOf(msg.sender, _token)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint deposit pool
        if (_amount > ERC20(_token).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // burn the tokens returned by the user first
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

    // mustRepayMax allows user to return as much of the debt of the specified token
    // as possible. If the transaction fails, it reverts.
    function mustRepayMax(address _token) public nonReentrant {
        // try to repay
        uint256 result = _repayMax(_token);

        // check zero amount condition
        require(result != ERR_ZERO_AMOUNT, "non-zero amount expected");

        // check low balance condition
        require(result != ERR_LOW_BALANCE, "insufficient debt outstanding");

        // check low allowance condition
        require(result != ERR_LOW_ALLOWANCE, "insufficient allowance");

        // sanity check for any non-covered condition
        require(result == ERR_NO_ERROR, "unexpected failure");
    }

    // repayMax allows user to return as much of the debt of the specified token
    // as possible.
    function repayMax(address _token) public nonReentrant returns (uint256) {
        return _repayMax(_token);
    }

    // _repayMax (internal) reduces the token debt by maximal amount
    // possible under the given situation.
    // NOTE: Allowance for burning is still required to be high enough
    // to allow the operation.
    function _repayMax(address _token) internal returns (uint256)
    {
        // get the debt size, available tokens
        uint256 poolBalance = getDebtPool().balanceOf(msg.sender, _token);
        uint256 ercBalance = ERC20(_token).balanceOf(msg.sender);

        // success
        return _repay(_token, Math.min(poolBalance, ercBalance));
    }
}