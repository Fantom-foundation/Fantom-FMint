pragma solidity ^0.5.0;

// IFantomMintRewardManager defines the interface of the rewards distribution manager.
interface IFantomMintRewardManager {
    // rewardUpdate updates the stored reward distribution state for the account.
    function rewardUpdate(address _account) external;
}
