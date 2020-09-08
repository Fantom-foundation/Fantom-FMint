pragma solidity ^0.5.0;

// IPriceOracleProxy defines the interface of the price oracle proxy contract
// used to provide up-to-date information about the value
// of coins and synthetic tokens handled by the DeFi contract.
interface IPriceOracleProxy {
    // getPrice implements the oracle for getting a specified token value
    // compared to the underlying stable denomination.
    function getPrice(address _token) external view returns (uint256);
}
