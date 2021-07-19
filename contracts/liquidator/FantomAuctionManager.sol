pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";

// FantomAuctionManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomAuctionManager is Initializable, Ownable
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    mapping(address => uint256) public admins;
    mapping(address => uint256) public assets;

    address public liquidatedAddress;

    uint256 constant WAD = 10 ** 18;

    // initialize initializes the contract properly before the first use.
    function initialize(address owner, address _addressProvider, address _liquidatedAddress) public initializer {
        // initialize the Ownable
        Ownable.initialize(owner);

        // remember the address provider for the other protocol contracts connection
        addressProvider = IFantomMintAddressProvider(_addressProvider);

        // initialize default values
        admins[owner] = 1;
        liquidatedAddress = _liquidatedAddress;
    }

    function addAdmin(address usr) external onlyOwner {
        admins[usr] = 1;
    }

    function removeAdmin(address usr) external onlyOwner {
        admins[usr] = 0;
    }

    modifier auth {
        require(admins[msg.sender] == 1, "Sender not authorized");
        _;
    }

    // getCollateralPool returns the address of collateral pool.
    function getCollateralPool() public view returns (IFantomDeFiTokenStorage) {
        return addressProvider.getCollateralPool();
    }

    // getDebtPool returns the address of debt pool.
    function getDebtPool() public view returns (IFantomDeFiTokenStorage) {
        return addressProvider.getDebtPool();
    }

    // rewardIsEligible checks if the account is eligible to receive any reward.
    function collateralIsEligible(address _account, address _token) public view returns (bool) {
        return addressProvider.getFantomMint().collateralCanDecrease(_account, _token, _amount, 0, getCollateralLowestDebtRatio4dec());
    }

    function startAuction() external returns (uint256 id) {
        require(live == 1, "Liquidation not live");

        require(!collateralIsEligible(targetAddress, _token, 0), "Collateral is not eligible for liquidation");

        require(getCollateralPool().totalOf(targetAddress) > 0, "Collateral is not eligible for liquidation");

        // get the collateral pool
        IFantomDeFiTokenStorage pool = IFantomDeFiTokenStorage(getCollateralPool());
        
    }

    function endLiquidation() external auth {
        live = 0;
    }
}
