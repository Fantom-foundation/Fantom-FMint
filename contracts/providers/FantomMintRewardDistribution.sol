pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomMintRewardManager.sol";
import "../modules/FantomMintErrorCodes.sol";

// FantomMintRewardDistribution implements an fMint reward distribution
// contract responsible for sending calculated amount of reward
// to the fMint Reward Manager module (part of the FantomMint contract)
// to be distributed.
contract FantomMintRewardDistribution is Ownable, FantomMintErrorCodes
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;

    // ---------------------------------------------------------------------
    // Reward distribution constants
    // ---------------------------------------------------------------------

    // MinRewardPushInterval represents the minimal amount of time between
    // two consecutive reward push calls.
    uint256 public constant minRewardPushInterval = 2 days;

    // ---------------------------------------------------------------------
    // State variables
    // ---------------------------------------------------------------------

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    // lastRewardPush represents the time stamp of the latest reward
    // distribution event.
    uint256 public lastRewardPush;

    // rewardPerSecond represents the rate of rewards being unlocked every
    // second from the reward pool.
    uint256 public rewardPerSecond;

    // ---------------------------------------------------------------------
    // Events emitted
    // ---------------------------------------------------------------------
    event RateUpdated(uint256 rewardPerYear);

    // ---------------------------------------------------------------------
    // Instance management and utility functions
    // ---------------------------------------------------------------------

    // create instance of the reward distribution
    constructor (address _addressProvider) public {
        // remember the address provider for the other protocol contracts connection
        addressProvider = IFantomMintAddressProvider(_addressProvider);
    }

    // ---------------------------------------------------------------------
    // Rewards control & rewards distribution functions
    // ---------------------------------------------------------------------

    // pushReward verifies the reward distribution conditions and calculates
    // available reward amount; if the call is legit, it will push the reward
    // to the Rewards Manager module to be distributed.
    // NOTE: We don't restrict the call source since it doesn't matter who makes
    // the call, all the calculations are done inside.
    function pushReward() external returns(uint256) {
    	// check if enough time passed from the last distribution
    	if (now < lastRewardPush.add(minRewardPushInterval)) {
    		return ERR_REWARDS_EARLY;
    	}

    	// how much is unlocked and waiting in the reward pool?
    	uint256 amount = now.sub(lastRewardPush).mul(rewardPerSecond);
    	if (amount == 0) {
    		return ERR_REWARDS_NONE;
    	}

    	// get the manager address
    	address manager = addressProvider.getFantomMint();

    	// check the manager account balance on the reward pool
    	// to make sure these rewards can be distributed
    	if (amount > IERC20(addressProvider.getRewardPool()).balanceOf(manager)) {
    		return ERR_REWARDS_DEPLETED;
    	}

    	// update the time stamp
    	lastRewardPush = now;

    	// notify the amount to the Reward Management
    	return IFantomMintRewardManager(manager).rewardNotifyAmount(amount);
    }

    // updateRate modifies the amount of reward unlocked per year
    function updateRate(uint256 amount) external onlyOwner {
    	// make sure the amount makes sense
    	require(amount > 0, "invalid reward amount");

    	// recalculate to rewards per second
    	// approximately since we don't take leap years and seconds into consideration
    	// but it's much more convenient to set the rate per year than per second
    	rewardPerSecond = amount.div(365 days);

    	// notify the change
    	emit RateUpdated(amount);
    }
}