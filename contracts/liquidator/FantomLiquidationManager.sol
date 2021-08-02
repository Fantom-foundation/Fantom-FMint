pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "../modules/FantomMintErrorCodes.sol";
import "../FantomMint.sol";
import "../modules/FantomMintBalanceGuard.sol";

// FantomLiquidationManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomLiquidationManager is Initializable, Ownable, FantomMintErrorCodes
{
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;
    
    // increasing contract's collateral value.
    event Deposited(address indexed token, address indexed user, uint256 amount);

    // decreasing contract's collateral value.
    event Withdrawn(address indexed token, address indexed user, uint256 amount);
    
    event AuctionStarted(address indexed user);
    event AuctionRestarted(address indexed user);

    struct AuctionInformation {
        address owner;
        uint256 startTime;
        uint256 intervalTime;
        uint256 endTime;
        uint256 startPrice;
        uint256 currentPrice;
        uint256 intervalPrice;
        uint256 minPrice;
        uint256 round;
        uint256 remainingValue;
    }

    bytes32 private constant MOD_FANTOM_MINT = "fantom_mint";
    bytes32 private constant MOD_COLLATERAL_POOL = "collateral_pool";
    bytes32 private constant MOD_DEBT_POOL = "debt_pool";
    bytes32 private constant MOD_PRICE_ORACLE = "price_oracle_proxy";
    bytes32 private constant MOD_REWARD_DISTRIBUTION = "reward_distribution";
    bytes32 private constant MOD_TOKEN_REGISTRY = "token_registry";
    bytes32 private constant MOD_ERC20_REWARD_TOKEN = "erc20_reward_token";

    mapping(address => mapping(address => uint256)) public liquidatedVault;
    mapping(address => AuctionInformation) public auctionList;
    
    address[] public collateralOwners;

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    mapping(address => uint256) public admins;

    address public fantomUSD;
    address public collateralContract;
    address public fantomMintContract;

    uint256 internal intervalPriceDiff;
    uint256 internal intervalTimeDiff;
    uint256 internal auctionBeginPrice;
    uint256 internal defaultMinPrice;

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
        auctionBeginPrice = 300;
        intervalPriceDiff = 10;
        intervalTimeDiff = 60;
        defaultMinPrice = 200;
    }

    function addAdmin(address usr) external onlyOwner {
        admins[usr] = 1;
    }

    function removeAdmin(address usr) external onlyOwner {
        admins[usr] = 0;
    }

    function updateAuctionBeginPrice(uint256 _auctionBeginPrice) external onlyOwner {
        auctionBeginPrice = _auctionBeginPrice;
    }

    function updateIntervalPriceDiff(uint256 _intervalPriceDiff) external onlyOwner {
        intervalPriceDiff = _intervalPriceDiff;
    }

    function updateIntervalTimeDiff(uint256 _intervalTimeDiff) external onlyOwner {
        intervalTimeDiff = _intervalTimeDiff;
    }

    function updateAuctionMinPrice(uint256 _defaultMinPrice) external onlyOwner {
        defaultMinPrice = _defaultMinPrice;
    }

    function updateFantomUSDAddress(address _fantomUSD) external onlyOwner {
        fantomUSD = _fantomUSD;
    }

    function updateAddressProvider(address _addressProvider) external onlyOwner {
        addressProvider = IFantomMintAddressProvider(_addressProvider);
    }

    function updateCollateralContractAddress(address _collateralContract) external onlyOwner {
        collateralContract = _collateralContract;
    }

    function updateFantomMintContractAddress(address _fantomMintContract) external onlyOwner {
        fantomMintContract = _fantomMintContract;
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
        return FantomMint(addressProvider.getAddress(MOD_FANTOM_MINT)).checkCollateralCanDecrease(_account, _token, 0);
    }

    function getLiquidationList() external view returns (address[] memory) {
        return collateralOwners;
    }

    function getLiquidationDetails(address _collateralOwner) external view returns (uint256, uint256, uint256) {
        AuctionInformation memory _auction = auctionList[_collateralOwner];
        return (_auction.startTime, _auction.endTime, _auction.currentPrice);
    }

    function updateLiquidation(address _collateralOwner) public auth {
        AuctionInformation storage _auction = auctionList[_collateralOwner];
        require(_auction.round > 0, "Auction not found");
        uint256 timeDiff = now - _auction.startTime;
        uint256 currentRound = timeDiff / _auction.intervalTime;
        uint256 _nextPrice = _auction.startPrice - currentRound * _auction.intervalPrice;
        if (_auction.endTime >= now || _nextPrice < _auction.minPrice) {
            // Restart the Auction
            _auction.round = _auction.round + 1;
            _auction.startPrice = auctionBeginPrice;
            _auction.currentPrice = auctionBeginPrice;
            _auction.intervalPrice = intervalPriceDiff;
            _auction.minPrice = defaultMinPrice;
            _auction.startTime = now;
            _auction.intervalTime = intervalTimeDiff;
            _auction.endTime = now + 60000;
            emit AuctionRestarted(_collateralOwner);
        } else {
            // Decrease the price
            _auction.currentPrice = _nextPrice;
        }
    }

    function bidAuction(address _collateralOwner, address _token, uint256 amount) public returns (uint256) {
        AuctionInformation storage _auction = auctionList[_collateralOwner];
        
        require(liquidatedVault[_collateralOwner][_token] >= amount, "Collateral is not sufficient to buy.");

        uint256 buyValue = getCollateralPool().tokenValue(_token, amount);
        uint256 debtValue = buyValue
            .mul(10000)
            .div(_auction.currentPrice);
        
        // make sure caller has enough balance to cover the bid
        if (debtValue >= ERC20(fantomUSD).balanceOf(msg.sender)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint collateral pool
        if (debtValue >= ERC20(fantomUSD).allowance(msg.sender, address(this))) {
            return ERR_LOW_ALLOWANCE;
        }

        // make sure caller has enough balance to cover the bid
        if (amount >= ERC20(_token).balanceOf(collateralContract)) {
            return ERR_LOW_BALANCE;
        }

        // make sure we are allowed to transfer funds from the caller
        // to the fMint collateral pool
        if (amount >= ERC20(_token).allowance(collateralContract, msg.sender)) {
            return ERR_LOW_ALLOWANCE;
        }

        ERC20(fantomUSD).safeTransferFrom(msg.sender, address(this), debtValue);

        ERC20(_token).safeTransferFrom(collateralContract, msg.sender, amount);
        // transfer ERC20 tokens from account to the collateral

        emit Withdrawn(_token, msg.sender, amount);
    }

    function getAuctionResource(address _collateralOwner) public returns (address[] memory, uint256[] memory) {
        uint256[] memory amounts = new uint256[](getCollateralPool().tokensCount());
        for (uint i = 0; i < getCollateralPool().tokensCount(); i++) {
            address _token = getCollateralPool().tokens()[i];
            uint256 liqudatedValue = liquidatedVault[_collateralOwner][_token];
            amounts[i] = liqudatedValue;
        }
        return (getCollateralPool().tokens(), amounts);
    }

    function startLiquidation(address targetAddress, address _token) external auth {
        require(live == 1, "Liquidation not live");
        // get the collateral pool
        IFantomDeFiTokenStorage pool = getCollateralPool();

        require(!collateralIsEligible(targetAddress, _token), "Collateral is not eligible for liquidation");

        require(pool.totalOf(targetAddress) > 0, "Collateral is not eligible for liquidation");


        addressProvider.getRewardDistribution().rewardUpdate(targetAddress);
        
        uint256 debtValue = getDebtPool().totalOf(targetAddress);
        for (uint i = 0; i < pool.tokensCount(); i++) {
            uint256 collatBalance = pool.balanceOf(targetAddress, pool.tokens()[i]);
            liquidatedVault[targetAddress][pool.tokens()[i]] = liquidatedVault[targetAddress][pool.tokens()[i]] + collatBalance;
            
            pool.sub(targetAddress, pool.tokens()[i], collatBalance);
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

        startAuction(targetAddress, debtValue);
    }

    function startAuction(address _collateralOwner, uint256 _debtValue) internal {
        AuctionInformation memory _auction;
        _auction.owner = _collateralOwner;
        _auction.round = 1;
        _auction.startPrice = auctionBeginPrice;
        _auction.currentPrice = auctionBeginPrice;
        _auction.intervalPrice = intervalPriceDiff;
        _auction.minPrice = defaultMinPrice;
        _auction.startTime = now;
        _auction.intervalTime = intervalTimeDiff;
        _auction.endTime = now + 60000;
        _auction.remainingValue = _debtValue;
        
        auctionList[_collateralOwner] = _auction;

        emit AuctionStarted(_collateralOwner);
    }

    function endLiquidation() external auth {
        live = 0;
    }
}
