pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";

// FantomLiquidationManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomLiquidationManager is Initializable, Ownable
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;

    mapping(address => mapping(address => uint256)) public liquidatedVault;
    
    address[] public collateralAddresses;

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    mapping(address => uint256) public admins;
    mapping(bytes32 => VaultData) public vaultDatas;

    uint256 public live;
    uint256 public maxAmt;
    uint256 public targetAmt;

    uint256 constant WAD = 10 ** 18;

    // initialize initializes the contract properly before the first use.
    function initialize(address owner, address _addressProvider) public initializer {
        // initialize the Ownable
        Ownable.initialize(owner);

        // remember the address provider for the other protocol contracts connection
        addressProvider = IFantomMintAddressProvider(_addressProvider);

        // initialize default values
        admins[owner] = 1;
        live = 1;
        
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

    function startLiquidation(address targetAddress, address _token) external returns (uint256 id) {
        require(live == 1, "Liquidation not live");

        require(!collateralIsEligible(targetAddress, _token, 0), "Collateral is not eligible for liquidation");

        require(getCollateralPool().totalOf(targetAddress) > 0, "Collateral is not eligible for liquidation");

        // get the collateral pool
        IFantomDeFiTokenStorage pool = IFantomDeFiTokenStorage(getCollateralPool());
        
        for (uint i = 0; i < getCollateralPool().tokens.length; i++) {
            uint256 collatBalance = getCollateralPool().balanceOf(targetAddress, getCollateralPool().tokens[i]);
            liquidatedVault[targetAddress][getCollateralPool().tokens[i]] = liquidatedVault[targetAddress][getCollateralPool().tokens[i]] + collatBalance;
            
            pool.sub(targetAddress, getCollateralPool().tokens[i], collatBalance);
        }

        bool found = false;

        // loop the current list and try to find the token
        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            if (collateralAddresses[i] == targetAddress) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            collateralAddresses.push(targetAddress);
        }

        FantomAuctionManager(targetAddress).startAuction();
    }

    function endLiquidation() external auth {
        live = 0;
    }
}
