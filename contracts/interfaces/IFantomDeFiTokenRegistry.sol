pragma solidity ^0.5.0;

// IFantomDeFiTokenRegistry defines an interface of the Fantom DeFi tokens
// registry contract used to identify ERC20 tokens available for Fantom
// DeFi platform with their important details.
interface IFantomDeFiTokenRegistry {

    // priceDecimals returns the number of decimal places a price
    // returned for the given token will be encoded to.
	function priceDecimals(address _token) external view returns (uint8);

	// canMint informs if the given token can be minted in the fMint protocol.
    function canMint(address _token) external view returns (bool);
}
