pragma solidity ^0.5.0;

import "../interfaces/IPriceOracleProxy.sol";

contract MockPriceOracleProxy is IPriceOracleProxy {
    mapping(address => uint256) public prices;

    function getPrice(address _token) external view returns (uint256) {
        return prices[_token];
    }

    function setPrice(address _token, uint256 _price) external {
        prices[_token] = _price;
    }
}