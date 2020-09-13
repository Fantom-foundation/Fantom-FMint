pragma solidity ^0.5.0;

/**
 * This interface defines available functions of the FMint Address Provider contract.
 *
 * Note: We may want to create a cache for certain external contract access scenarios (like
 * for token price/value calculation, which needs the oracle and registry).
 * The contract which frequently connects with another one would use the cached address
 * from the address provider until a protoSync() is called. The protoSync() call would
 * re-load contract addresses from the address provider and cache them locally to save
 * gas on repeated access.
 */
interface IFantomMintAddressProvider {
	// getFantomMint returns the address of the Fantom fMint contract.
	function getFantomMint() external view returns (address);

	// setFantomMint modifies the address of the Fantom fMint contract.
	function setFantomMint(address _addr) external;

	// getTokenRegistry returns the address of the token registry contract.
	function getTokenRegistry() external view returns (address);

	// setTokenRegistry modifies the address of the token registry contract.
	function setTokenRegistry(address _addr) external;

	// getCollateralPool returns the address of the collateral pool contract.
	function getCollateralPool() external view returns (address);

	// setCollateralPool modifies the address of the collateral pool contract.
	function setCollateralPool(address _addr) external;

	// getDebtPool returns the address of the debt pool contract.
	function getDebtPool() external view returns (address);

	// setDebtPool modifies the address of the debt pool contract.
	function setDebtPool(address _addr) external;

	// getRewardDistribution returns the address of the reward distribution contract.
	function getRewardDistribution() external view returns (address);

	// setRewardDistribution modifies the address of the reward distribution contract.
	function setRewardDistribution(address _addr) external;

	// getPriceOracleProxy returns the address of the price oracle aggregate.
	function getPriceOracleProxy() external view returns (address);

	// setPriceOracleProxy modifies the address of the price oracle aggregate.
	function setPriceOracleProxy(address _addr) external;

	// getFeeToken returns the address of the ERC20 token used for fees.
	function getFeeToken() external view returns (address);

	// setFeeToken modifies the address of the ERC20 token used for fees.
	function setFeeToken(address _addr) external;

	// getRewardToken returns the address of the reward token ERC20 contract.
	function getRewardToken() external view returns (address);

	// setRewardToken modifies the address of the reward token ERC20 contract.
	function setRewardToken(address _addr) external;
}
