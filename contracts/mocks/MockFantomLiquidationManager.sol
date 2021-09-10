pragma solidity ^0.5.0;

import "../liquidator/FantomLiquidationManager.sol";

contract MockFantomLiquidationManager is FantomLiquidationManager {

    uint256 public time;
    function setTime(uint256 t) public {
        time = t;
    }

    function increaseTime(uint256 t) public {
        time += t;
    }

    function _now() internal view returns (uint256) {
        return time;
    }


}