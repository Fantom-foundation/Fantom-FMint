pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFantomMintRewardManager.sol";
import "./FantomMintErrorCodes.sol";

// FantomMintCore implements a balance pool of collateral and debt tokens
// for the related Fantom DeFi contract. The collateral part allows notified rewards
// distribution to eligible collateral accounts.
contract FantomMintRewardManager is FantomMintErrorCodes, IFantomMintRewardManager
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Rewards distribution related constants
    // -------------------------------------------------------------

    // rewardEpochLength represents the shortest possible length of the rewards
    // epoch where accounts can claim their accumulated rewards from staked collateral.
    uint256 public constant rewardEpochLength = 7 days;

    // rewardPerTokenDecimalsCorrection represents the correction done on rewards per token
    // so the calculation does not loose precision on very low reward rates and high collateral
    // balance in the system.
    uint256 public constant rewardPerTokenDecimalsCorrection = 1e6;

    // rewardEligibilityRatio4dec represents the collateral to debt ratio user has to have
    // to be able to receive rewards.
    // The value is kept in 4 decimals, e.g. value 50000 = 5.0
    uint256 public constant rewardEligibilityRatio4dec = 50000;

    // -------------------------------------------------------------
    // Rewards distribution related state
    // -------------------------------------------------------------

    // rewardsRate represents the current rate of reward distribution;
    // e.g. the amount of reward tokens distributed per second of the current reward epoch
    uint256 public rewardRate;

    // rewardEpochEnds represents the time stamp of the expected end of this reward epoch;
    // the notified reward amount is spread across the epoch at its beginning and the distribution ends
    // on this time stamp; if a new epoch is started before this one ends, the remaining reward
    // is pushed to the new epoch; if the current epoch is past its end, no additional rewards
    // are distributed
    uint256 public rewardEpochEnds;

    // rewardUpdated represents the time stamp of the last reward distribution update; the update
    // is executed every time an account state changes and the purpose is to reflect the previous
    // state impact on the reward distribution
    uint256 public rewardUpdated;

    // rewardLastPerToken represents previous stored value of the rewards per token
    // and reflects rewards distribution before the latest collateral state change
    uint256 public rewardLastPerToken;

    // rewardPerTokenPaid represents the amount of reward tokens already settled for an account
    // per collateral token; it's updated each time the collateral amount changes to reflect
    // previous state impact on the rewards the account is eligible for.
    mapping(address => uint256) public rewardPerTokenPaid;

    // rewardStash represents the amount of reward tokens stashed
    // for an account address during the reward distribution update.
    mapping(address => uint256) public rewardStash;

    // -------------------------------------------------------------
    // Emitted events
    // -------------------------------------------------------------

    // RewardAdded is emitted on starting new rewards epoch with specified amount
    // of rewards, which correspond to a reward rate per second based on epoch length.
    event RewardAdded(uint256 reward);

    // RewardPaid event is emitted when an account claims their rewards from the system.
    event RewardPaid(address indexed user, uint256 reward);

    // -------------------------------------------------------------
    // Principal balance access (abstract)
    // -------------------------------------------------------------

    // principalBalance (abstract) returns the total balance of principal token
    // which yield a reward to entitled participants based
    // on their individual principal share.
    function principalBalance() public view returns (uint256);

    // principalBalanceOf (abstract) returns the balance of principal token
    // which yield a reward share for this account.
    function principalBalanceOf(address _account) public view returns (uint256);

    // -------------------------------------------------------------
    // Reward management functions
    // -------------------------------------------------------------

    // rewardPoolAddress returns address of the reward tokens pool.
    // The pool is used to settle rewards to eligible accounts.
    function rewardPoolAddress() public view returns (address);

    // rewardDistributionAddress returns address of the reward distribution contract.
    function rewardDistributionAddress() public view returns (address);

    // rewardCanClaim (abstract) checks if the account can claim accumulated reward.
    function rewardCanClaim(address _account) public view returns (bool);

    // rewardIsEligible (abstract) checks if the account is eligible to receive any reward.
    function rewardIsEligible(address _account) internal view returns (bool);

    // rewardNotifyAmount is called by reward distribution management
    // to start new reward epoch with a new reward amount added to the reward pool.
    // NOTE: We do all the reward validity checks on the RewardDistribution contract,
    // so we expect to receive only valid and correct reward data here.
    function rewardNotifyAmount(uint256 reward) external returns (uint256) {
        // make sure this is done by reward distribution contract
        if (msg.sender != rewardDistributionAddress()) {
            return ERR_NOT_AUTHORIZED;
        }

        // update the global reward distribution state before closing
        // the current epoch
        rewardUpdate(address(0));

        // if the previous reward epoch is about to end sooner than it's expected,
        // calculate remaining reward amount from the previous epoch
        // and add it to the notified reward pushing the leftover to the new epoch
        if (now < rewardEpochEnds) {
            uint256 leftover = rewardEpochEnds.sub(now).mul(rewardRate);
            reward = reward.add(leftover);
        }

        // start new reward epoch with the new reward rate
        rewardRate = reward.div(rewardEpochLength);
        rewardEpochEnds = now.add(rewardEpochLength);
        rewardUpdated = now;

        // notify new epoch with the updated rewards rate
        emit RewardAdded(reward);

        // we are done
        return ERR_NO_ERROR;
    }

    // rewardUpdate updates the stored reward distribution state
    // and the accumulated reward tokens status per account;
    // it is called on each principal token state change to reflect
    // the impact on reward distribution.
    function rewardUpdate(address _account) internal {
        // calculate the current reward per token value globally
        rewardLastPerToken = rewardPerToken();
        rewardUpdated = rewardApplicableUntil();

        // if this is an account state update, calculate rewards earned
        // to this point (before the account collateral value changes)
        // and stash those rewards
        if (_account != address(0)) {
            // is the account eligible to receive this reward at all?
            if (rewardIsEligible(_account)) {
                rewardStash[_account] = rewardEarned(_account);
            }

            // adjust paid part of the accumulated reward
            // if the account is not eligible to receive reward up to this point
            // we just skip it and they will never get it
            rewardPerTokenPaid[_account] = rewardLastPerToken;
        }
    }

    // rewardApplicableUntil returns the time stamp of the latest time
    // the notified rewards can be distributed.
    // The notified reward is spread across the whole epoch period
    // using the reward rate (number of reward tokens per second).
    // No more reward tokens remained to be distributed past the
    // epoch duration, so the distribution has to stop.
    function rewardApplicableUntil() public view returns (uint256) {
        return Math.min(now, rewardEpochEnds);
    }

    // rewardPerToken calculates the reward share per virtual collateral value
    // token. It's based on the reward rate for the epoch (e.g. the total amount
    // of reward tokens per second)
    function rewardPerToken() public view returns (uint256) {
        // the reward distribution is normalized to the total amount of principal tokens
        // in the system; calculate the current principal value across all the tokens
        uint256 total = principalBalance();

        // no collateral? use just the reward per token stored
        if (total == 0) {
            return rewardLastPerToken;
        }

        // return accumulated stored rewards plus the rewards
        // coming from the current reward rate normalized to the total
        // collateral amount. The distribution stops at the epoch end.
        return rewardLastPerToken.add(
            rewardApplicableUntil().sub(rewardUpdated)
            .mul(rewardRate)
            .mul(rewardPerTokenDecimalsCorrection)
            .div(total)
            );
    }

    // rewardEarned calculates the amount of reward tokens the given account is eligible
    // for right now based on its collateral balance value and the total value
    // of all collateral tokens in the system
    function rewardEarned(address _account) public view returns (uint256) {
        // calculate earned rewards based on the account share on the total
        // principal balance expressed in the rewardPerToken() value
        return principalBalanceOf(_account)
                .mul(rewardPerToken().sub(rewardPerTokenPaid[_account]))
                .div(rewardPerTokenDecimalsCorrection)
                .add(rewardStash[_account]);
    }

    // rewardClaim transfers earned rewards to the caller account address
    function rewardClaim() public returns (uint256) {
        // update the reward distribution for the account
        rewardUpdate(msg.sender);

        // how many reward tokens were earned by the account?
        uint256 reward = rewardStash[msg.sender];

        // @NOTE: Pulling this from the rewardEarned() invokes system-wide
        // collateral balance calculation again (through rewardPerToken) burning gas;
        // All the earned tokens should be in the stash already after
        // the reward update call above.

        // are there any at all?
        if (0 == reward) {
            return ERR_NO_REWARD;
        }

        // check if the account can claim
        // @NOTE: We may not need this check if the actual amount of rewards will
        // be calculated from an excessive amount of collateral compared to debt
        // including certain ratio (e.g. debt value * 300% < collateral value)
        // @see rewardEarned() call above
        if (!rewardCanClaim(msg.sender)) {
            return ERR_REWARD_CLAIM_REJECTED;
        }

        // reset accumulated rewards on the account
        rewardStash[msg.sender] = 0;

        // transfer earned reward tokens to the caller
        ERC20(rewardPoolAddress()).safeTransfer(msg.sender, reward);

        // notify about the action
        emit RewardPaid(msg.sender, reward);

        // claim successful
        return ERR_NO_ERROR;
    }
}