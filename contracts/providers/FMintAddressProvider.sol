pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../interfaces/IFMintAddressProvider.sol";

/**
* This provides addresses to deployed FMint modules
* and related contracts cooperating on the FMint protocol.
* It's used to connects different modules to make the whole
* FMint protocol live and work.
*
* version 0.1.0
* license MIT
* author Fantom Foundation, Jiri Malek
*/
contract FMintAddressProvider is Ownable, IFMintAddressProvider {

	// ----------------------------------------------
	// Module identifiers used by the address storage
	// ----------------------------------------------
	//
	bytes32 private constant MOD_FANTOM_MINT = "fantom_mint";
	bytes32 private constant MOD_PRICE_ORACLE = "price_oracle_aggregate";
	bytes32 private constant MOD_REWARD_DISTRIBUTION = "reward_distribution";
	bytes32 private constant MOD_TOKEN_REGISTRY = "token_registry";
	bytes32 private constant MOD_ERC20_FEE_TOKEN = "erc20_fee_token";
	bytes32 private constant MOD_ERC20_REWARD_POOL = "erc20_reward_pool";

	// -----------------------------------------
	// Address storage state and events
	// -----------------------------------------

	// _addressPool stores addresses to the different modules
	// identified their common names.
	mapping(bytes32 => address) private _addressPool;

	// PriceOracleChanged even is emitted when
	// a new Price Oracle address is set.
	event PriceOracleChanged(address newAddress);

	// RewardDistributionChanged even is emitted when
	// a new Reward Distribution address is set.
	event RewardDistributionChanged(address newAddress);

	// TokenRegistryChanged even is emitted when
	// a new Token Registry address is set.
	event TokenRegistryChanged(address newAddress);

	// FeeTokenChanged even is emitted when
	// a new Fee Token address is set.
	event FeeTokenChanged(address newAddress);

	// --------------------------------------------
	// General address storage management functions
	// --------------------------------------------

	/**
	* getAddress returns the address associated with the given
	* module identifier. If the identifier is not recognized,
	* the function returns zero address instead.
	*
	* @param _id The common name of the module contract.
	* @return The address of the deployed module.
	*/
	function getAddress(bytes32 _id) public view returns (address) {
		return _addressPool[_id];
	}

	/**
	* setAddress modifies the active address of the given module,
	* identified by it's common name, to the new address.
	*
	* @param _id The common name of the module contract.
	* @param _addr The new address to be used for the module.
	* @return {void}
	*/
	function setAddress(bytes32 _id, address _addr) internal {
		_addressPool[_id] = _addr;
	}

	// -----------------------------------------
	// Module specific getters and setters below
	// -----------------------------------------

	/**
	 * getPriceOracle returns the address of the Price Oracle
	 * aggregate contract used for the fLend DeFi functions.
	 */
	function getPriceOracle() external view returns (address) {
		return getAddress(MOD_PRICE_ORACLE);
	}

	/**
	 * setPriceOracle modifies the current current active price oracle aggregate
	 * to the address specified.
	 */
	function setPriceOracle(address _addr) external onlyOwner {
		// make the change
		setAddress(MOD_PRICE_ORACLE, _addr);

		// inform listeners and seekers about the change
		emit PriceOracleChanged(_addr);
	}

	/**
	 * getTokenRegistry returns the address of the token registry contract.
	 */
	function getTokenRegistry() external view returns (address) {
		return getAddress(MOD_TOKEN_REGISTRY);
	}

	/**
	 * setTokenRegistry modifies the address of the token registry contract.
	 */
	function setTokenRegistry(address _addr) external onlyOwner {
		// make the change
		setAddress(MOD_TOKEN_REGISTRY, _addr);

		// inform listeners and seekers about the change
		emit TokenRegistryChanged(_addr);
	}

	/**
	 * getFeeToken returns the address of the ERC20 token used for fees.
	 */
	function getFeeToken() external view returns (address) {
		return getAddress(MOD_ERC20_FEE_TOKEN);
	}

	/**
	 * setFeeToken modifies the address of the ERC20 token used for fees.
	 */
	function setFeeToken(address _addr) external onlyOwner {
		// make the change
		setAddress(MOD_ERC20_FEE_TOKEN, _addr);

		// inform listeners and seekers about the change
		emit FeeTokenChanged(_addr);
	}

	/**
	 * getRewardDistribution returns the address
	 * of the reward distribution contract.
	 */
	function getRewardDistribution() external view returns (address) {
		return getAddress(MOD_REWARD_DISTRIBUTION);
	}

	/**
	 * setRewardDistribution modifies the address
	 * of the reward distribution contract.
	 */
	function setRewardDistribution(address _addr) external onlyOwner {
		setAddress(MOD_REWARD_DISTRIBUTION, _addr);
	}

	/**
	 * getRewardPool returns the address of the reward pool contract.
	 */
	function getRewardPool() external view returns (address) {
		return getAddress(MOD_ERC20_REWARD_POOL);
	}

	/**
	 * setRewardPool modifies the address of the reward pool contract.
	 */
	function setRewardPool(address _addr) external onlyOwner {
		setAddress(MOD_ERC20_REWARD_POOL, _addr);
	}

	/**
	 * getFantomMint returns the address of the Fantom fMint contract.
	 */
	function getFantomMint() external view returns (address){
		return getAddress(MOD_FANTOM_MINT);
	}

	// setFantomMint modifies the address of the Fantom fMint contract.
	function setFantomMint(address _addr) external onlyOwner {
		setAddress(MOD_FANTOM_MINT, _addr);
	}
}