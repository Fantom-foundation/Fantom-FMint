pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interface/IPriceOracle.sol";
import "./utils/FMintErrorCodes.sol";
import "./utils/RewardDistributionRecipient.sol";
import "./utils/FantomCollateralStorage.sol";
import "./utils/FantomDebtStorage.sol";

// FantomCollateral implements a collateral pool
// for the related Fantom DeFi contract. The collateral is used
// to manage tokens referenced on the balanced DeFi functions.
contract FantomCollateral is
            Ownable,
            ReentrancyGuard,
            FMintErrorCodes,
            FantomCollateralStorage,
            FantomDebtStorage,
            RewardDistributionRecipient
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
    // Rewards distribution related constants
    // -------------------------------------------------------------

    // collateralRewardsPool represents the address of the pool used to settle
    // collateral rewards to eligible accounts.
    address public constant collateralRewardsPool = "0xf1277d1ed8ad466beddf92ef448a132661956621";

    // rewardEpochLength represents the shortest possible length of the rewards
    // epoch where accounts can claim their accumulated rewards from staked collateral.
    uint256 public constant rewardEpochLength = 7 days;

    // -------------------------------------------------------------
    // Rewards distribution related state
    // -------------------------------------------------------------

    // TRewardEpoch represents the structure
    // holding details of the current rewards epoch.
    struct TRewardEpoch {
        uint256 rewardsRate;        // rate of the rewards distribution
        uint256 epochEnds;          // time stamp of the end of this epoch
        uint256 updated;            // time stamp of the last update of the accumulated rewards
        uint256 accumulatedRewards; // accumulated rewards on the epoch
    }

    // rewardEpoch represents the current reward epoch details.
    TRewardEpoch public rewardEpoch;

    // -------------------------------------------------------------
    // Emitted events definition
    // -------------------------------------------------------------

    // Deposited is emitted on token received to deposit
    // increasing user's collateral value.
    event Deposited(address indexed token, address indexed user, uint256 amount);

    // Withdrawn is emitted on confirmed token withdraw
    // from the deposit decreasing user's collateral value.
    event Withdrawn(address indexed token, address indexed user, uint256 amount);

    // RewardAdded is emitted on starting new rewards epoch with specified amount
    // of rewards, which correspond to a reward rate per second based on epoch length.
    event RewardAdded(uint256 reward);

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

        // transfer ERC20 tokens from user to the pool
        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // update the collateral value storage
        _collateralByTokens[_token][msg.sender] = _collateralByTokens[_token][msg.sender].add(_amount);
        _collateralByUsers[msg.sender][_token] = _collateralByUsers[msg.sender][_token].add(_amount);

        // make sure the token is on the list
        // of collateral tokens for the sender
        enrolCollateral(_token, msg.sender);

        // re-calculate the current value of the whole collateral deposit
        // across all assets kept
        updateCollateralValueOf(msg.sender);

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
        if (_amount > _collateralByTokens[_token][msg.sender]) {
            return ERR_LOW_BALANCE;
        }

        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts
        uint256 cDebtValue = debtValue(msg.sender);
        uint256 cCollateralValue = collateralValue(msg.sender);

        // lower the collateral value by the withdraw value
        cCollateralValue.sub(tokenValue(_token, _amount));

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue
                                        .mul(collateralLowestDebtRatio4dec)
                                        .div(collateralRatioDecimalsCorrection);

        // does the new state obey the enforced minimal collateral to debt ratio?
        // if the check fails, the collateral withdraw is rejected
        if (cCollateralValue < minCollateralValue) {
            // emit error
            return ERR_LOW_COLLATERAL_RATIO;
        }

        // update collateral value of the token to a new value
        _collateralByTokens[_token][msg.sender] = _collateralByTokens[_token][msg.sender].sub(_amount);
        _collateralByUsers[msg.sender][_token] = _collateralByUsers[msg.sender][_token].sub(_amount);

        // the new collateral value is all right; update the stored collateral and debt values
        updateCollateralValueOf(msg.sender);
        _debtValue[msg.sender] = cDebtValue;

        // transfer the requested amount of ERC20 tokens from the local pool to the caller
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // signal the successful asset withdrawal
        emit Withdrawn(_token, msg.sender, _amount);

        // withdraw successful
        return ERR_NO_ERROR;
    }

    // -------------------------------------------------------------
    // Rewards management functions below
    // -------------------------------------------------------------

    // notifyRewardAmount is called by contract management to start new rewards epoch
    // with a new reward added to the reward pool.
    function notifyRewardAmount(uint256 reward) external onlyRewardDistribution {
        // calculate remaining reward from the previous epoch
        // and add it to the notified reward if the epoch
        // is to end sooner than it's expected
        if (now < rewardEpoch.epochEnds) {
            uint256 leftover = rewardEpoch.epochEnds.sub(now).mul(rewardRate);
            reward = reward.add(leftover);
        }

        // start new rewards epoch with the new reward rate
        rewardEpoch.rewardRate = reward.div(rewardEpochLength);
        rewardEpoch.epochEnds = now.add(rewardEpochLength);
        rewardEpoch.updated = now;

        // emit the events to notify new epoch with the updated rewards rate
        emit RewardAdded(reward);
    }

    // rewardApplicableUntil returns the time stamp of the latest applicable
    // time rewards can be calculated towards.
    function rewardApplicableUntil() public view returns (uint256) {
        return Math.min(now, rewardEpoch.epochEnds);
    }

    // rewardPerToken calculates the reward share per virtual collateral value
    // token.
    function rewardPerToken() public view returns (uint256) {
        // is there any collateral value? if not, return accumulated
        // rewards only
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }

        // return accumulated rewards plus the rewards
        // coming from the current reward rate
        return rewardPerTokenStored.add(
                rewardApplicableUntil().sub(rewardEpoch)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
        );
    }
}
