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

    struct AuctionInformation {
        address owner;
        uint256 startTime;
        uint256 intervalTime;
        uint256 endTime;
        uint256 startPrice;
        uint256 intervalPrice;
        uint256 minPrice;
        uint256 round;
    }

    mapping(address => mapping(address => uint256)) public liquidatedVault;
    mapping(address => AuctionInformation) public auctionList;
    
    address[] public collateralOwners;

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    mapping(address => uint256) public admins;

    uint256 public roundPriceDiff;
    uint256 public intervalPriceDiff;
    uint256 public intervalTimeDiff;

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
        roundPriceDiff = 2;
        intervalPriceDiff = 1;
        intervalTimeDiff = 60;
    }

    function addAdmin(address usr) external onlyOwner {
        admins[usr] = 1;
    }

    function removeAdmin(address usr) external onlyOwner {
        admins[usr] = 0;
    }

    function changeRoundPriceDiff(uint256 _roundPriceDiff) external onlyOwner {
        roundPriceDiff = _roundPriceDiff;
    }

    function changeIntervalPriceDiff(uint256 _intervalPriceDiff) external onlyOwner {
        intervalPriceDiff = _intervalPriceDiff;
    }

    function changeIntervalTimeDiff(uint256 _intervalTimeDiff) external onlyOwner {
        intervalTimeDiff = _intervalTimeDiff;
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

    function getLiquidationList() external view returns (address[]) {
        return collateralOwners;
    }

    function getLiquidationDetails(address _collateralOwner) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        AuctionInformation memory _auction = auctionList[_collateralOwner];
        return (
            _auction.startTime,
            _auction.intervalTime,
            _auction.endTime,
            _auction.startPrice,
            _auction.intervalPrice,
            _auction.minPrice,
            _auction.round
        );
    }

    function updateLiquidation(address _collateralOwner) public auth {
        AuctionInformation memory _auction = auctionList[_collateralOwner];
        require(_auction.round > 0, "Auction not found");
        if (_auction.endTime >= now) {
            // Restart the Auction
        } else {
            // Decrease the price
        }
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

        // loop the current list and try to find the user
        for (uint256 i = 0; i < collateralOwners.length; i++) {
            if (collateralOwners[i] == targetAddress) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            collateralOwners.push(targetAddress);
        }


    }

    function endLiquidation() external auth {
        live = 0;
    }
}
