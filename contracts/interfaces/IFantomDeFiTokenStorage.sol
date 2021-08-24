pragma solidity ^0.5.0;

// IFantomDeFiTokenStorage defines the interface to token storage contract
// used by the DeFi protocol to manage collateral and debt pools.
interface IFantomDeFiTokenStorage {
    // tokenValue returns the value of the given amount of the token specified.
    function tokenValue(address _token, uint256 _amount) external view returns (uint256);

    // total returns the total value of all the tokens registered inside the storage.
    function total() external view returns (uint256);

    // totalOf returns the value of current balance of specified account.
    function totalOf(address _account) external view returns (uint256);

    // totalOfInc returns the value of current balance of an account
    // with specified token balance increased by given amount of tokens.
    function totalOfInc(address _account, address _token, uint256 _amount) external view returns (uint256);

    // totalOfDec returns the value of current balance of an account
    // with specified token balance decreased by given amount of tokens.
    function totalOfDec(address _account, address _token, uint256 _amount) external view returns (uint256);

    // balanceOf returns the balance of the given token on the given account.
    function balanceOf(address _account, address _token) external view returns (uint256);

    // add adds specified amount of tokens to given account.
    function add(address _account, address _token, uint256 _amount) external;

    // sub removes specified amount of tokens from given account.
    function sub(address _account, address _token, uint256 _amount) external;

    function tokens() external view returns (address[] memory);

    function getToken(uint256 _index) external view returns (address);

    function tokensCount() external view returns (uint256);
}