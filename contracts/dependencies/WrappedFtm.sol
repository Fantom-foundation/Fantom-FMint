// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";

/**
 * Implements Wrapped FTM as ERC20 token.
 *
 * The local FTM pool size will always match the total supply of wFTM tokens
 * since they are minted on deposit and burned on withdraw in 1:1 ratio.
 */
contract WrappedFtm is ERC20, ERC20Detailed, ERC20Mintable, ERC20Burnable, ERC20Pausable {
	// Error Code: No error.
	uint256 public constant ERR_NO_ERROR = 0x0;

	// Error Code: Non-zero value expected to perform the function.
	uint256 public constant ERR_INVALID_ZERO_VALUE = 0x01;

    // create instance of the Wrapped FTM token
    constructor () public ERC20Detailed("Wrapped Fantom", "WFTM", 18) {
    }

    // deposit wraps received FTM tokens as wFTM in 1:1 ratio by minting
    // the received amount of FTMs in wFTM on the sender's address.
    function deposit() public payable returns (uint256) {
    	// there has to be some value to be converted
    	if (msg.value == 0) {
    		return ERR_INVALID_ZERO_VALUE;
    	}

    	// we already received FTMs, mint the appropriate amount of wFTM
    	_mint(msg.sender, msg.value);

    	// all went well here
    	return ERR_NO_ERROR;
    }

    // withdraw unwraps FTM tokens by burning specified amount
    // of wFTM from the caller address and sending the same amount
    // of FTMs back in exchange.
    function withdraw(uint256 amount) public returns (uint256) {
    	// there has to be some value to be converted
    	if (amount == 0) {
    		return ERR_INVALID_ZERO_VALUE;
    	}

    	// burn wFTM from the sender first to prevent re-entrance issue
    	_burn(msg.sender, amount);

    	// if wFTM were burned, transfer native tokens back to the sender
    	msg.sender.transfer(amount);

    	// all went well here
    	return ERR_NO_ERROR;
    }
}
