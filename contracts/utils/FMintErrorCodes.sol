pragma solidity ^0.5.0;

/**
 * FMintErrorCodes defines set of soft error codes
 * returned from fMint contract calls.
 */
contract FMintErrorCodes {
	// Error Code: No error.
	uint256 public const ERR_NO_ERROR = 0x0;

	// Error Code: Zero value is not valid for the call.
	uint256 public const ERR_INVALID_ZERO_VALUE = 0x1001;

	// Error Code: ERC20 account balance too low to continue.
	uint256 public const ERR_LOW_BALANCE = 0x1002;

	// Error Code: ERC20 allowance for the fMint too low.
	uint256 public const ERR_LOW_ALLOWANCE = 0x1003;
}