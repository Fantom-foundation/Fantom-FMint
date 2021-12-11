pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";

contract MockToken is ERC20, ERC20Detailed {
    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
    function burnFrom(address account, uint256 amount) public {
        _burnFrom(account, amount);
    }
}