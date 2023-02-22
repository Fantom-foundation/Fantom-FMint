pragma solidity ^0.5.0;
import "hardhat/console.sol";

interface ISFC {
    function getValidatorID(address) external returns (uint256);

    function unlockStake(
        uint256 toValidatorID,
        uint256 amount,
        address _targetAddress
    ) external returns (uint256);
}

interface IStakeTokenizer {
    function outstandingSFTM(address, uint256) external returns (uint256);

    function redeemSFTM(address, uint256 validatorID, uint256 amount) external;
}

contract SFCToFMint {
    ISFC internal sfc;
    IStakeTokenizer internal stakeTokenizer;

    constructor(address _sfc, IStakeTokenizer _stakeTokenizer) public {
        sfc = ISFC(_sfc);
        stakeTokenizer = _stakeTokenizer;
    }

    function removeStake(address _targetAddress, uint256 amount) external {
        uint256 validatorID = sfc.getValidatorID(_targetAddress);
        uint256 stakedsFTM = stakeTokenizer.outstandingSFTM(
            _targetAddress,
            validatorID
        );
        if (stakedsFTM > 0) {
            stakeTokenizer.redeemSFTM(_targetAddress, validatorID, stakedsFTM);
        }

        sfc.unlockStake(validatorID, amount, _targetAddress);
    }
}
