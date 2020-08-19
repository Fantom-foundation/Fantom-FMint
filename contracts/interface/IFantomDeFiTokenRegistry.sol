pragma solidity ^0.5.0;

// IFantomDeFiTokenRegistry defines an interface of the Fantom DeFi tokens
// registry contract used to identify ERC20 tokens available for Fantom
// DeFi platform with their important details.
interface IFantomDeFiTokenRegistry {
	// canMint informs if the given token can be minted in the fMint protocol.
    function canMint(address _token) external view returns (bool);

    // getToken returns address of a special token for the given token type.
    function getToken(uint _type) external view returns (address);
}
