pragma solidity ^0.5.0;

/**
 * FMintErrorCodes defines set of soft error codes
 * returned from fMint contract calls.
 */
contract FMintErrorCodes {
	// Error Code: No error.
	uint256 public constant ERR_NO_ERROR = 0x0;

	// Error Code: Zero value is not valid for the call.
	uint256 public constant ERR_ZERO_AMOUNT = 0x1001;

	// Error Code: Account balance too low to continue.
	uint256 public constant ERR_LOW_BALANCE = 0x1002;

	// Error Code: ERC20 allowance for the fMint too low.
	uint256 public constant ERR_LOW_ALLOWANCE = 0x1003;

	// Error Code: Collateral is missing or has no value.
	uint256 public constant ERR_NO_COLLATERAL = 0x1004;

	// Error Code: Collateral is below enforced limit.
	uint256 public constant ERR_LOW_COLLATERAL_RATIO = 0x1005;

	// Error Code: Requested token not available for minting.
	uint256 public constant ERR_MINTING_PROHIBITED = 0x1006;

	// Error Code: Requested token has no known value.
	uint256 public constant ERR_NO_VALUE = 0x1007;

	// Error Code: Requested token has no known value.
	uint256 public constant ERR_DEBT_EXCEEDED = 0x1008;

	// Error Code: No reward available on the account.
	uint256 public constant ERR_NO_REWARD = 0x1009;

	// Error Code: Reward can not be claimed, collateral to debt ration too low.
	uint256 public constant ERR_REWARD_CLAIM_REJECTED = 0x100A;
}
