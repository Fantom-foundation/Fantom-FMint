pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";

// IRewardDistributionRecipient represents connection
// to reward distribution management address.
contract RewardDistributionRecipient is Ownable {
    // rewardDistribution is the address allowed to make changes
    // to the rewards distribution.
    address rewardDistribution;

    // onlyRewardDistribution decorator locks the underlying function
    // to be callable by the reward distribution address only.
    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    // notifyRewardAmount closes previous reward distribution epoch
    // and introduces new reward rate for the next epoch.
    function notifyRewardAmount(uint256 reward) external;

    // setRewardDistribution changes the reward distribution address allowed
    // to make rewards distribution management calls.
    function setRewardDistribution(address _rewardDistribution) external onlyOwner {
        rewardDistribution = _rewardDistribution;
    }
}