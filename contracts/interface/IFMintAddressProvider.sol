pragma solidity ^0.5.0;

/**
* This interface defines available functions of the FMint Address Provider contract.
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

	// getTokenRegistry returns the address of the token registry contract.
	function getTokenRegistry() public view returns (address);

	// setTokenRegistry modifies the address of the token registry contract.
	function setTokenRegistry(address _addr) public;

	// getFeeToken returns the address of the ERC20 token used for fees.
	function getFeeToken() public view returns (address);

	// setFeeToken modifies the address of the ERC20 token used for fees.
	function setFeeToken(address _addr) public;

	// getRewardDistribution returns the address of the reward distribution contract.
	function getRewardDistribution() public view returns (address);

	// setRewardDistribution modifies the address of the reward distribution contract.
	function setRewardDistribution(address _addr) public;
}
