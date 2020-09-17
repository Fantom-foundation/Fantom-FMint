pragma solidity ^0.5.0;

import "@openzeppelin/upgrades/contracts/upgradeability/AdminUpgradeabilityProxy.sol";

// FantomUpgradeabilityProxy inherits fully from OpenZeppelin Upgradeability Proxy
// contract with admin access control.
contract FantomUpgradeabilityProxy is AdminUpgradeabilityProxy {
}