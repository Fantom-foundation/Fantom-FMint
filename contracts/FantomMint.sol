pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IPriceOracleProxy.sol";
import "./interfaces/IFantomMintAddressProvider.sol";
import "./interfaces/IFantomMintTokenRegistry.sol";
import "./interfaces/IFantomDeFiTokenStorage.sol";
import "./interfaces/IFantomMintRewardManager.sol";
import "./modules/FantomMintErrorCodes.sol";
import "./modules/FantomMintBalanceGuard.sol";
import "./modules/FantomMintCollateral.sol";
import "./modules/FantomMintDebt.sol";
import "./modules/FantomMintConfig.sol";

// FantomMint implements the contract of core DeFi function
// for minting tokens against a deposited collateral. The collateral
// management is linked from the Fantom Collateral implementation.
// Minting is burdened with a minting fee defined as the amount
// of percent of the minted tokens value in fUSD. Burning is free
// of any fee.
contract FantomMint is FantomMintBalanceGuard, FantomMintCollateral, FantomMintDebt, FantomMintConfig {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // ----------------------------
    // Fantom minter configuration
    // ----------------------------

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    // constructor initializes a new instance of the fMint module.
    constructor(address _addressProvider) public {
        // remember the address provider connecting satellite contracts to the minter
        addressProvider = IFantomMintAddressProvider(_addressProvider);
    }

    // -------------------------------------------------------------
    // Minter parameters resolved from the Config contract
    // -------------------------------------------------------------

    // getCollateralLowestDebtRatio4dec represents the lowest ratio between
    // collateral value and debt value allowed for the user.
    // User can not withdraw his collateral if the active ratio would
    // drop below this value.
    function getCollateralLowestDebtRatio4dec () public view returns (uint256) {
        return collateralLowestDebtRatio4dec;
    }

    // getRewardEligibilityRatio4dec represents the collateral to debt ratio user has to have
    // to be able to receive rewards.
    function getRewardEligibilityRatio4dec () public view returns (uint256) {
        return rewardEligibilityRatio4dec;
    }

    // getFMintFee4dec represents the current percentage of the created tokens
    // captured as a fee.
    function getFMintFee4dec () public view returns (uint256) {
        return fMintFee4dec;
    }

    // -------------------------------------------------------------
    // Pool balances and values
    // -------------------------------------------------------------

    // debtValueOf returns the value of account debt.
    function debtValueOf(address _account) public view returns (uint256) {
        return IFantomDeFiTokenStorage(addressProvider.getDebtPool()).totalOf(_account);
    }

    // collateralValueOf returns the value of account collateral.
    function collateralValueOf(address _account) public view returns (uint256) {
        return IFantomDeFiTokenStorage(addressProvider.getCollateralPool()).totalOf(_account);
    }

    // getCollateralPool returns the address of collateral pool.
    function getCollateralPool() public view returns (IFantomDeFiTokenStorage) {
        return addressProvider.getCollateralPool();
    }

    // getDebtPool returns the address of debt pool.
    function getDebtPool() public view returns (IFantomDeFiTokenStorage) {
        return addressProvider.getDebtPool();
    }

    // canDeposit checks if the given token can be deposited to the collateral pool.
    function canDeposit(address _token) public view returns (bool) {
        return addressProvider.getTokenRegistry().canDeposit(_token);
    }

    // canMint checks if the given token can be minted in the fMint protocol.
    function canMint(address _token) public view returns (bool) {
        return addressProvider.getTokenRegistry().canMint(_token);
    }

    // checkCollateralCanDecrease checks if the specified amount of collateral can be removed from account
    // without breaking collateral to debt ratio rule.
    function checkCollateralCanDecrease(address _account, address _token, uint256 _amount) public view returns (bool) {
        return collateralCanDecrease(_account, _token, _amount);
    }

    // checkDebtCanIncrease (abstract) checks if the specified
    // amount of debt can be added to the account
    // without breaking collateral to debt ratio rule.
    function checkDebtCanIncrease(address _account, address _token, uint256 _amount) public view returns (bool) {
        return debtCanIncrease(_account, _token, _amount);
    }

    // -------------------------------------------------------------
    // Reward update events routing
    // -------------------------------------------------------------

    // rewardUpdate notifies the reward distribution to update state
    // of the given account.
    function rewardUpdate(address _account) public {
        addressProvider.getRewardDistribution().rewardUpdate(_account);
    }

    // -------------------------------------------------------------
    // Token price calculation functions
    // -------------------------------------------------------------

    // getPrice returns the price of given ERC20 token using on-chain oracle
    // expression of an exchange rate between the token and base denomination.
    function getPrice(address _token) public view returns (uint256) {
        // use linked price oracle aggregate to get the token exchange price
        return addressProvider.getPriceOracleProxy().getPrice(_token);
    }

    // getPriceDigitsCorrection returns the correction to the calculated
    // ERC20 token value to correct exchange rate digits correction.
    function getPriceDigitsCorrection(address _token) public view returns (uint256) {
        // get the value from the token registry
        // consider caching it until future protoSync() to save some gas from external call
        return 10**uint256(addressProvider.getTokenRegistry().priceDecimals(_token));
    }

    // collateralTokenValue calculates the value of the given collateral amount of the token specified.
    function collateralTokenValue(address _token, uint256 _amount) public view returns (uint256) {
        return addressProvider.getCollateralPool().tokenValue(_token, _amount);
    }

    // debtTokenValue calculates the value of the given debt amount of the token specified.
    function debtTokenValue(address _token, uint256 _amount) public view returns (uint256) {
        return addressProvider.getDebtPool().tokenValue(_token, _amount);
    }
}
