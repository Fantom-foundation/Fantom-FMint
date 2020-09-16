pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";

// FantomMintConfig implements the fMint core contract configuration
// with the ability to fine tune settings by the contract owner.
contract FantomMintConfig is Ownable
{
    // collateralLowestDebtRatio4dec represents the lowest ratio between
    // collateral value and debt value allowed for the user.
    // User can not withdraw his collateral if the active ratio would
    // drop below this value.
    // The value is returned in 4 decimals, e.g. value 30000 = 3.0
    uint256 public collateralLowestDebtRatio4dec = 30000;

    // rewardEligibilityRatio4dec represents the collateral to debt ratio user has to have
    // to be able to receive rewards.
    // The value is kept in 4 decimals, e.g. value 50000 = 5.0
    uint256 public rewardEligibilityRatio4dec = 50000;

    // fMintFee represents the current percentage of the created tokens
    // captured as a fee.
    // The value is kept in 4 decimals; 50 = 0.005 = 0.5%
    uint256 public fMintFee4dec = 50;

    // fMintFeeDigitsCorrection represents the value to be used
    // to adjust result decimals after applying fee to a value calculation.
    uint256 public fMintFeeDigitsCorrection = 10000;

    // -------------------------------------------------------------
    // Events emitted on update
    // -------------------------------------------------------------

    // CollateralLowestDebtRatioChanged is emitted on change
    // of the lowest ratio between collateral value and debt value.
    event CollateralLowestDebtRatioChanged(uint256 ratio4dec);

    // RewardEligibilityRatioChanged is emitted on change
    // of the ratio between collateral value and debt value which
    // entitles users to earn rewards.
    event RewardEligibilityRatioChanged(uint256 ratio4dec);

    // MintFeeChanged is emitted on change of the fMint minting
    // fee percentage.
    event MintFeeChanged(uint256 fee4dec);

    // -------------------------------------------------------------
    // Update functions
    // -------------------------------------------------------------

    // cfgSetLowestCollateralRatio changes the lowest allowed ratio between collateral
    // and debt value for minting, repaying and collateral manipulation.
    function cfgSetLowestCollateralRatio(uint256 _ratio4dec) public onlyOwner {
        // update the value
        collateralLowestDebtRatio4dec = _ratio4dec;

        // emit event
        emit CollateralLowestDebtRatioChanged(_ratio4dec);
    }

    // cfgSetRewardEligibilityRatio changes the lowest ratio between collateral
    // and debt value users must have to earn rewards.
    function cfgSetRewardEligibilityRatio(uint256 _ratio4dec) public onlyOwner {
        // update the value
        rewardEligibilityRatio4dec = _ratio4dec;

        // emit event
        emit RewardEligibilityRatioChanged(_ratio4dec);
    }

    // cfgSetRewardEligibilityRatio changes the lowest ratio between collateral
    // and debt value users must have to earn rewards.
    function cfgSetMintFee(uint256 _fee4dec) public onlyOwner {
        // update the value
        fMintFee4dec = _fee4dec;

        // emit event
        emit MintFeeChanged(_fee4dec);
    }
}