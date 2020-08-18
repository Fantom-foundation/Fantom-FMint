pragma solidity ^0.5.0;

/**
* This interface defines available function
* of the FLand Address Provider contract.
*
* @version 0.1.0
* @license MIT
* @author Fantom Foundation, Jiri Malek
*/
interface IFMintAddressProvider {
	// getPriceOracle returns the address of the price oracle aggregate.
	function getPriceOracle() public view returns (address);

	// setPriceOracle modifies the address of the price oracle aggregate.
	function setPriceOracle(address _addr) public;
}
