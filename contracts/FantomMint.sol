pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IFMintAddressProvider.sol";
import "./interfaces/IFantomDeFiTokenRegistry.sol";
import "./modules/FMintErrorCodes.sol";
import "./modules/FantomMintCore.sol";

// FantomMint implements the contract of core DeFi function
// for minting tokens against a deposited collateral. The collateral
// management is linked from the Fantom Collateral implementation.
// Minting is burdened with a minting fee defined as the amount
// of percent of the minted tokens value in fUSD. Burning is free
// of any fee.
contract FantomMint is Ownable, ReentrancyGuard, FantomMintCore {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // feePool keeps information about the fee collected from
    // minter internal operations in fMin fee tokens identified below (fUSD).
    uint256 public feePool;

    // Minted is emitted on confirmed token minting against user's collateral value.
    event Minted(address indexed token, address indexed user, uint256 amount);

    // Repaid is emitted on confirmed token repay of user's debt of the token.
    event Repaid(address indexed token, address indexed user, uint256 amount);

    // ----------------------------
    // Fantom minter configuration
    // ----------------------------

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFMintAddressProvider public addressProvider;

    // fMintPriceDigitsCorrection represents the correction required
    // for FTM/ERC20 (18 digits) to another 18 digits number exchange
    // through an 8 digits USD (ChainLink compatible) price oracle
    // on any minting price value calculation.
    uint256 public constant fMintPriceDigitsCorrection = 100000000;

    // fMintFee represents the current value of the minting fee used
    // for minter operations.
    // The value is kept in 4 decimals; 25 = 0.0025 = 0.25%
    uint256 public constant fMintFee = 25;

    // fMintFeeDigitsCorrection represents the value to be used
    // to adjust result decimals after applying fee to a value calculation.
    uint256 public constant fMintFeeDigitsCorrection = 10000;

    // constructor initializes a new instance of the fMint module.
    constructor(address _addressProvider) public {
        // remember the address provider connecting satellite contracts to the minter
        addressProvider = IFMintAddressProvider(_addressProvider);
    }

    // -------------------------------------------------------------
    // Utility contracts address resolvers
    // -------------------------------------------------------------

    // rewardPoolAddress returns address of the reward tokens pool.
    // The pool is used to settle rewards to eligible accounts.
    // Used in FantomMintRewardManager.
    function rewardPoolAddress() public view returns (address) {
        return addressProvider.getRewardPool();
    }

    // rewardDistributionAddress returns address of the reward distribution contract.
    function rewardDistributionAddress() public view returns (address) {
        return addressProvider.getRewardDistribution();
    }

    // tokenRegistryAddress returns address of the DeFi token registry.
    function tokenRegistryAddress() public view returns (address) {
        return addressProvider.getTokenRegistry();
    }

    // feeTokenAddress returns address of the ERC20 token used for the fee.
    function feeTokenAddress() public view returns (address) {
        return addressProvider.getFeeToken();
    }

    // -------------------------------------------------------------
    // Token price calculation functions
    // -------------------------------------------------------------

    // getPrice (abstract) returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256) {
        // use linked price oracle aggregate to get the token exchange price
        return IPriceOracle(addressProvider.getPriceOracle()).getPrice(_token);
    }

    // getPriceDigitsCorrection (abstract) returns the correction to the calculated
    // ERC20 token value to correct exchange rate digits correction.
    function getPriceDigitsCorrection() public pure returns (uint256) {
        // price oracles we use (ChainLink) use 8 digits exchange rate correction
        // NOTE: consider getting this value from the token registry (cleaner approach)
        return 100000000;
    }

    // -------------------------------------------------------------
    // Minter functions
    // -------------------------------------------------------------

    // mint allows user to create a specified token against already established
    // collateral. The value of the collateral must be in at least configured
    // ratio to the total user's debt value on minting.
    function mint(address _token, uint256 _amount) external nonReentrant returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure the requested token can be minted
        if (!IFantomDeFiTokenRegistry(tokenRegistryAddress()).canMint(_token)) {
            return ERR_MINTING_PROHIBITED;
        }

        // what is the value of the borrowed token?
        uint256 tokenValue = getPrice(_token);
        if (tokenValue == 0) {
            return ERR_NO_VALUE;
        }

        // make sure the debt can be increased on the account
        if (!debtCanIncrease(msg.sender, _token, _amount)) {
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // add the minted amount to the debt
        debtAdd(msg.sender, _token, _amount);

        // calculate the minting fee and store the value we gained by this operation
        // @NOTE: We don't check if the fee can be added to the account debt
        // assuming that if the debt could be increased for the minted account, it could
        // accommodate the fee as well (the collateral slippage is in play).
        uint256 fee = _amount
                        .mul(tokenValue)
                        .mul(fMintFee)
                        .div(fMintFeeDigitsCorrection)
                        .div(fMintPriceDigitsCorrection);
        feePool = feePool.add(fee);

        // add the fee to debt
        debtAdd(msg.sender, feeTokenAddress(), fee);

        // mint the requested balance of the ERC20 token
        // @NOTE: the fMint contract must have the minter privilege on the ERC20 token!
        ERC20Mintable(_token).mint(msg.sender, _amount);

        // emit the minter notification event
        emit Minted(_token, msg.sender, _amount);

        // success
        return ERR_NO_ERROR;
    }

    // repay allows user to return some of the debt of the specified token
    // the repay does not collect any fees and is not validating the user's total
    // collateral to debt position.
    function repay(address _token, uint256 _amount) external nonReentrant returns (uint256)
    {
        // make sure a non-zero value is being deposited
        if (_amount == 0) {
            return ERR_ZERO_AMOUNT;
        }

        // make sure there is enough debt on the token specified (if any at all)
        if (_amount > _debtBalance[msg.sender][_token]) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint deposit pool
        if (_amount > ERC20(_token).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // burn the tokens returned by the user
        ERC20Burnable(_token).burnFrom(msg.sender, _amount);

        // clear the repaid amount from the account debt balance
        debtSub(msg.sender, _token, _amount);

        // emit the repay notification
        emit Repaid(_token, msg.sender, _amount);

        // success
        return ERR_NO_ERROR;
    }
}
