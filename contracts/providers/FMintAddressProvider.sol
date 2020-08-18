pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../interfaces/IFMintAddressProvider.sol";

/**
* This contract provides addresses to all the deployed
* FMint modules and related contracts, which cooperates
* in the FMint protocol. It's used to connects different
* modules to make the whole FMint protocol live and work.
*
* @version 0.1.0
* @license MIT
* @author Fantom Foundation, Jiri Malek
*/
contract FMintAddressProvider is Ownable, IFLendAddressProvider {
	// _addressPool stores addresses to the different modules
	// identified their common names.
	mapping(bytes32 => address) private _addressPool;

	// common names of the modules are defined below
	bytes32 private constant MOD_PRICE_ORACLE = "price_oracle_aggregate";

	// emitted evens are defined below
	event PriceOracleChanged(address indexed newAddress);

	/**
	* getAddress returns the address associated with the given
	* module identifier. If the identifier is not recognized,
	* the function returns zero address instead.
	*
	* @param _id The common name/identifier of the module.
	* @return The address of the deployed module.
	*/
	function getAddress(bytes32 _id) public view returns (address) {
		return _addressPool[_id];
	}

	/**
	* setAddress modifies the active address of the given module,
	* identified by it's common name, to the new address.
	*
	* @param _id The common name of the module.
	* @param _addr The new address to be used for the module.
	* @return {void}
	*/
	function setAddress(bytes32 _id, address _addr) internal {
		// just set the new value
		_addressPool[_id] = _addr;
	}

	/**
	* getPriceOracle returns the address of the Price Oracle
	* aggregate contract used for the fLend DeFi functions.
	*
	* @return The address of the price oracle aggregate.
	*/
	function getPriceOracle() public view returns (address) {
		return getAddress(MOD_PRICE_ORACLE);
	}

	/**
	* setPriceOracle modifies the current current active price oracle aggregate
	* to the address specified.
	*
	* @param _addr Address of the price oracle aggregate to be used.
	* @return {void}
	*/
	function setPriceOracle(address _addr) public onlyOwner {
		// set the new address
		setAddress(MOD_PRICE_ORACLE, _addr);

		// inform listeners and seekers about the change
		emit PriceOracleChanged(_addr);
	}
}