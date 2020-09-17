pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Pausable.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
contract FantomFUSD is Initializable, ERC20, ERC20Detailed, ERC20Mintable, ERC20Burnable, ERC20Pausable {

    /**
     * @dev Sets the values for `name`, `symbol`, and `decimals`. All three of
     * these values are immutable: they can only be set once during
     * initialization.
     */
    function initialize(address owner) public initializer {
        // initialize the token
        ERC20Detailed.initialize("Fantom USD", "FUSD", 18);

        // initialize the ERC20Mintable, ERC20Pausable
        ERC20Mintable.initialize(owner);
        ERC20Pausable.initialize(owner);
    }
}
