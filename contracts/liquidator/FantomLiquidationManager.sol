pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IFantomMintAddressProvider.sol";
import "../interfaces/IFantomDeFiTokenStorage.sol";
import "../modules/FantomMintErrorCodes.sol";
import "../FantomMint.sol";
import "../modules/FantomMintBalanceGuard.sol";

// FantomLiquidationManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomLiquidationManager is Initializable, Ownable, FantomMintErrorCodes, ReentrancyGuard
{
    // define used libs
    using SafeMath for uint;
    using Address for address;
    using SafeERC20 for ERC20;
    
    // increasing contract's collateral value.
    event Deposited(address indexed token, address indexed user, uint amount);

    // decreasing contract's collateral value.
    event Withdrawn(address indexed token, address indexed user, uint amount);
    
    event AuctionStarted(uint indexed nonce, address indexed user);
    event AuctionRestarted(uint indexed nonce, address indexed user);

    struct AuctionInformation {
        address owner;
        uint startTime;
        uint intervalTime;
        uint endTime;
        uint startPrice;
        uint intervalPrice;
        uint minPrice;
        uint round;
        uint remainingPercent;
        address[] collateralList;
        address[] debtList;
        mapping(address => uint) collateralValue;
        mapping(address => uint) debtValue;
        uint nonce;
    }

    bytes32 private constant MOD_FANTOM_MINT = "fantom_mint";
    bytes32 private constant MOD_COLLATERAL_POOL = "collateral_pool";
    bytes32 private constant MOD_DEBT_POOL = "debt_pool";
    bytes32 private constant MOD_PRICE_ORACLE = "price_oracle_proxy";
    bytes32 private constant MOD_REWARD_DISTRIBUTION = "reward_distribution";
    bytes32 private constant MOD_TOKEN_REGISTRY = "token_registry";
    bytes32 private constant MOD_ERC20_REWARD_TOKEN = "erc20_reward_token";

    mapping(address => mapping(address => uint)) public liquidatedVault;
    AuctionInformation[] public auctionList;
    mapping(uint => uint) public auctionIndexer;


    // mapping(address => AuctionInformation[]) public auctionList;
    
    // mapping(address => uint) public auctionIndex;

    // addressProvider represents the connection to other FMint related
    // contracts.
    IFantomMintAddressProvider public addressProvider;

    mapping(address => bool) public admins;

    address public fantomUSD;
    address public collateralContract;
    address public fantomMintContract;
    address public fantomFeeVault;

    uint internal totalNonce;
    uint internal intervalPriceDiff;
    uint internal intervalTimeDiff;
    uint internal auctionBeginPrice;
    uint internal defaultMinPrice;
    uint internal minDebtValue;
    uint internal pricePrecision;
    uint internal percentPrecision;

    bool public live;

    uint constant WAD = 10 ** 18;

    // initialize initializes the contract properly before the first use.
    function initialize(address owner, address _addressProvider) public initializer {
        // initialize the Ownable
        Ownable.initialize(owner);

        // remember the address provider for the other protocol contracts connection
        addressProvider = IFantomMintAddressProvider(_addressProvider);

        // initialize default values
        admins[owner] = true;
        live = true;
        auctionBeginPrice = 20000000;
        intervalPriceDiff = 1000;
        intervalTimeDiff = 1;
        defaultMinPrice = 10 ** 8;
        minDebtValue = 100;
        pricePrecision = 10 ** 8;
        percentPrecision = 10 ** 8;
        totalNonce = 0;
    }

    function addAdmin(address usr) external onlyOwner {
        admins[usr] = true;
    }

    function removeAdmin(address usr) external onlyOwner {
        admins[usr] = false;
    }

    function updateAuctionBeginPrice(uint _auctionBeginPrice) external onlyOwner {
        auctionBeginPrice = _auctionBeginPrice;
    }

    function updateIntervalPriceDiff(uint _intervalPriceDiff) external onlyOwner {
        intervalPriceDiff = _intervalPriceDiff;
    }

    function updateIntervalTimeDiff(uint _intervalTimeDiff) external onlyOwner {
        intervalTimeDiff = _intervalTimeDiff;
    }

    function updateAuctionMinPrice(uint _defaultMinPrice) external onlyOwner {
        defaultMinPrice = _defaultMinPrice;
    }

    function updateMinimumDebtValue(uint _minDebtValue) external onlyOwner {
        minDebtValue = _minDebtValue;
    }

    function updatePercentPrecision(uint _percentPrecision) external onlyOwner {
        percentPrecision = _percentPrecision;
    }

    function updatePricePrecision(uint _pricePrecision) external onlyOwner {
        pricePrecision = _pricePrecision;
    }

    function updateFantomFeeVault(address _fantomFeeVault) external onlyOwner {
        fantomFeeVault = _fantomFeeVault;
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
        require(admins[msg.sender], "Sender not authorized");
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
    function collateralIsEligible(address _account) public view returns (bool) {
        return FantomMint(addressProvider.getAddress(MOD_FANTOM_MINT)).checkCollateralCanDecrease(_account, getCollateralPool().tokens()[0], 0);
    }

    function getLiquidationList() external view returns (uint[] memory) {
        uint[] memory nonces;
        for (uint index = 0; index < auctionList.length; index++) {
            nonces.push(auctionList[index].nonce);
        }
        return nonces;
    }

    function getLiquidationDetails(uint _nonce) external view returns (
        uint, uint, address[] memory, uint[] memory, address[] memory, uint[] memory
    ) {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation memory _auction = auctionList[auctionIndexer[_nonce] - 1];
        uint timeDiff = block.timestamp - _auction.startTime;
        uint currentRound = timeDiff.div(_auction.intervalTime);
        uint currentPrice = _auction.startPrice.add(currentRound.mul(_auction.intervalPrice_));

        address[] memory collateralList;
        uint[] memory collateralValue;
        address[] memory debtList;
        uint[] memory debtValue;
        uint index;
        for (index = 0; index < _auction.collateralList.length; index++) {
            collateralList.push(_auction.collateralList[index]);
            collateralValue.push(_auction.collateralValue[_auction.collateralList[index]]
                .mul(pricePrecision).mul(percentPrecision)
                .div(currentPrice).div(_auction.remainingPercent));
        }
        for (index = 0; index < _auction.debtList.length; index++) {
            debtList.push(_auction.debtList[index]);
            debtValue.push(_auction.debtValue[_auction.debtList[index]]);
        }
        return (_auction.startTime, _auction.endTime, collateralList, collateralValue, debtList, debtValue);
    }

    function updateLiquidation(uint _nonce) public nonReentrant auth {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        require(_auction.round > 0, "Auction not found");
        uint timeDiff = block.timestamp.sub(_auction.startTime);
        uint currentRound = timeDiff.div(_auction.intervalTime);
        uint _nextPrice = _auction.startPrice.add(currentRound.mul(_auction.intervalPrice));
        if (_auction.endTime >= block.timestamp || _nextPrice >= _auction.minPrice) {
            // Restart the Auction
            _auction.round = _auction.round + 1;
            _auction.startPrice = auctionBeginPrice;
            _auction.intervalPrice = intervalPriceDiff;
            _auction.minPrice = defaultMinPrice;
            _auction.startTime = block.timestamp;
            _auction.intervalTime = intervalTimeDiff;
            _auction.endTime = block.timestamp.add(60000);
            emit AuctionRestarted(_nonce, _auction.owner);
        }
    }

    function balanceOfRemainingCollateral(uint _nonce) public view returns (uint) {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        require(_auction.round > 0, "Auction not found");
        
        uint totalValue = 0;
        for (uint i = 0; i < _auction.debtList.length; i++) {
            totalValue += _auction.debtValue[_auction.debtList[i]];
        }

        return totalValue;
    }

    function bidAuction(uint _nonce, uint _percentage) public nonReentrant returns (uint) {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        require(_auction.round > 0, "Auction not found");
        require(_auction.remainingPercent >= _percentage, "Collateral is not sufficient to buy.");

        uint timeDiff = block.timestamp.sub(_auction.startTime);
        uint currentRound = timeDiff.div(_auction.intervalTime);
        uint _nextPrice = _auction.startPrice.add(currentRound.mul(_auction.intervalPrice));

        
        // // make sure caller has enough fUSD to cover the collateral
        // if (debtValue >= ERC20(fantomUSD).balanceOf(msg.sender)) {
        //     return ERR_LOW_BALANCE;
        // }

        // // make sure we are allowed to transfer fUSD from the caller
        // // to the liqudation pool.
        // if (debtValue >= ERC20(fantomUSD).allowance(msg.sender, address(this))) {
        //     return ERR_LOW_ALLOWANCE;
        // }

        // // make sure the collateral is sufficient to buy
        // if (amount >= ERC20(_token).balanceOf(collateralContract)) {
        //     return ERR_LOW_BALANCE;
        // }

        // // make sure we are allowed to transfer the collateral from the collateral contract
        // // to the buyer
        // if (amount >= ERC20(_token).allowance(collateralContract, msg.sender)) {
        //     return ERR_LOW_ALLOWANCE;
        // }

        // ERC20(fantomUSD).safeTransferFrom(msg.sender, address(this), debtValue);

        // ERC20(_token).safeTransferFrom(collateralContract, msg.sender, amount);

        // liquidatedVault[_collateralOwner][_token] -= amount;

        // emit Withdrawn(_token, msg.sender, amount);

        // // Check if auction is finished or not
        // bool auctionEnded = false;

        // if (liquidatedVault[_collateralOwner][_token] == 0) {
        //     auctionEnded = balanceOfRemainingCollateral(_collateralOwner) > 0;
        // }

        // if (auctionEnded) {
        //     uint indexOfArray = auctionIndex[_collateralOwner];
        //     if (indexOfArray == collateralOwners.length) {
        //         auctionIndex[_collateralOwner] = 0;
        //         collateralOwners.pop();
        //     } else {
        //         collateralOwners[indexOfArray - 1] = collateralOwners[collateralOwners.length - 1];
        //         collateralOwners.pop();
        //         auctionIndex[collateralOwners[indexOfArray - 1]] = indexOfArray;
        //     }
        // }
        return ERR_NO_ERROR;
    }

    function startLiquidation(address _targetAddress) external nonReentrant auth {
        require(live, "Liquidation not live");
        // get the collateral pool
        IFantomDeFiTokenStorage collateralPool = getCollateralPool();
        // get the debt pool
        IFantomDeFiTokenStorage debtPool = getDebtPool();

        require(!collateralIsEligible(_targetAddress), "Collateral is not eligible for liquidation");

        require(collateralPool.totalOf(_targetAddress) > 0, "The value of the collateral is 0");

        addressProvider.getRewardDistribution().rewardUpdate(_targetAddress);

        uint debtValue = getDebtPool().totalOf(_targetAddress);

        require(debtValue >= minDebtValue, "The value of the debt is less than the minimum debt value");

        AuctionInformation memory _auction;
        _auction.owner = _targetAddress;
        _auction.round = 1;
        _auction.startPrice = auctionBeginPrice;
        _auction.intervalPrice = intervalPriceDiff;
        _auction.minPrice = defaultMinPrice;
        _auction.startTime = block.timestamp;
        _auction.intervalTime = intervalTimeDiff;
        _auction.endTime = block.timestamp + 60000;
        _auction.remainingPercent = percentPrecision;

        address[] memory debtTokenList;
        address[] memory debtValueList;
        address[] memory collateralTokenList;
        address[] memory collateralValueList;

        uint index;
        uint tokenCount;
        address tokenAddress;
        uint tokenBalance;
        tokenCount = collateralPool.tokensCount();
        for (index = 0; index < tokenCount; index++) {
            tokenAddress = collateralPool.getToken(index);
            tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
            if (tokenBalance > 0) {
                liquidatedVault[_targetAddress][tokenAddress] += tokenBalance;
                collateralPool.sub(_targetAddress, tokenAddress, tokenBalance);
                collateralTokenList.push(tokenAddress);
                collateralValueList.push(tokenBalance);
            }
        }
        
        tokenCount = debtPool.tokensCount();
        for (index = 0; index < tokenCount; index++) {
            tokenAddress = debtPool.getToken(index);
            tokenBalance = debtPool.balanceOf(_targetAddress, tokenAddress);
            if (tokenBalance > 0) {
                debtPool.sub(_targetAddress, tokenAddress, tokenBalance);
                debtTokenList.push(tokenAddress);
                debtValueList.push(tokenBalance);
            }
        }

        _auction.debtList = debtTokenList;
        _auction.debtValue = debtValueList;
        _auction.collateralList = collateralTokenList;
        _auction.collateralValue = collateralValueList;
        totalNonce += 1;
        _auction.nonce = totalNonce;

        auctionList.push(_auction);
        auctionIndexer[totalNonce] = auctionList.length;

        emit AuctionStarted(totalNonce, _targetAddress);
    }

    function updateLiquidationFlag(bool _live) external auth {
        live = _live;
    }
}
