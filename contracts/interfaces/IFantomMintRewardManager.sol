pragma solidity ^0.5.0;

// IFantomMintRewardManager defines the interface of the rewards distribution manager.
interface IFantomMintRewardManager {
    // rewardNotifyAmount is called by reward distribution management
    // to start new reward epoch with a new reward amount added to the reward pool.
    // NOTE: We do all the reward validity checks on the RewardDistribution contract,
    // so we expect to receive only valid and correct reward data here.
    function rewardNotifyAmount(uint256 reward) external returns (uint256);
}
