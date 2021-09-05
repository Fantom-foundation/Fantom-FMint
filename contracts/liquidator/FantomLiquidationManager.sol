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

    AuctionInformation[] internal auctionList;
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
    uint internal pricePrecision;
    uint internal percentPrecision;
    uint internal auctionDuration;

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
        pricePrecision = 10 ** 8;
        percentPrecision = 10 ** 8;
        auctionDuration = 80000;
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

    function updatePercentPrecision(uint _percentPrecision) external onlyOwner {
        percentPrecision = _percentPrecision;
    }

    function updatePricePrecision(uint _pricePrecision) external onlyOwner {
        pricePrecision = _pricePrecision;
    }

    function updateAuctionDuration(uint _auctionDuration) external onlyOwner {
        auctionDuration = _auctionDuration;
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
        return FantomMint(addressProvider.getAddress(MOD_FANTOM_MINT)).checkCollateralCanDecrease(_account, getCollateralPool().getToken(0), 0);
    }

    function getLiquidationList() external view returns (uint[] memory) {
        uint[] memory nonces = new uint[](auctionList.length);
        for (uint index = 0; index < auctionList.length; index++) {
            nonces[index] = auctionList[index].nonce;
        }
        return nonces;
    }

    function getLiquidationDetails(uint _nonce) external view returns (
        uint, uint, uint, address[] memory, uint[] memory, address[] memory, uint[] memory
    ) {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        //uint timeDiff = block.timestamp - _auction.startTime;
        uint timeDiff = block.timestamp.sub(_auction.startTime);
        uint currentRound = timeDiff.div(_auction.intervalTime);
        uint offeringRatio = _auction.startPrice.add(currentRound.mul(_auction.intervalPrice));

        address[] memory collateralList = new address[](_auction.collateralList.length);
        uint[] memory collateralValue = new uint[](_auction.collateralList.length);
        address[] memory debtList = new address[](_auction.debtList.length);
        uint[] memory debtValue = new uint[](_auction.debtList.length);
        uint index;
        for (index = 0; index < _auction.collateralList.length; index++) {
            collateralList[index] = _auction.collateralList[index];
            collateralValue[index] = _auction.collateralValue[_auction.collateralList[index]]
                .mul(offeringRatio)
                .div(pricePrecision);
        }
        for (index = 0; index < _auction.debtList.length; index++) {
            debtList[index] = _auction.debtList[index];
            debtValue[index] = _auction.debtValue[_auction.debtList[index]];
        }
        return (offeringRatio, _auction.startTime, _auction.endTime, collateralList, collateralValue, debtList, debtValue);
    }

    function updateLiquidation(uint _nonce) public nonReentrant auth {
        require(live, "Liquidation not live");
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
            _auction.endTime = block.timestamp.add(auctionDuration);
            emit AuctionRestarted(_nonce, _auction.owner);
        }
    }

    function balanceOfRemainingDebt(uint _nonce) public view returns (uint) {
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        require(_auction.round > 0, "Auction not found");

        uint totalValue = 0;
        for (uint i = 0; i < _auction.debtList.length; i++) {
            totalValue += _auction.debtValue[_auction.debtList[i]];
        }

        return totalValue;
    }

    function bidAuction(uint _nonce, uint _percentage) public nonReentrant {
        require(live, "Liquidation not live");
        require(auctionIndexer[_nonce] > 0, "Auction not found");
        AuctionInformation storage _auction = auctionList[auctionIndexer[_nonce] - 1];
        require(_auction.round > 0, "Auction not found");
        require(percentPrecision >= _percentage, "Collateral is not sufficient to buy.");

        //uint offeringRatio = _auction.startPrice.add(block.timestamp.sub(_auction.startTime).mul(_auction.intervalPrice).div(_auction.intervalTime));
        uint timeDiff = block.timestamp.sub(_auction.startTime);
        uint currentRound = timeDiff.div(_auction.intervalTime);
        uint offeringRatio = _auction.startPrice.add(currentRound.mul(_auction.intervalPrice));

        uint index;
        for (index = 0; index < _auction.debtList.length; index++) {
            uint debtAmount = _auction.debtValue[_auction.debtList[index]].mul(_percentage).div(percentPrecision);
            require(debtAmount <= ERC20(_auction.debtList[index]).allowance(msg.sender, address(this)),
                "Low allowance of debt token."
            );
            ERC20(_auction.debtList[index]).safeTransferFrom(msg.sender, fantomFeeVault, debtAmount);
            _auction.debtValue[_auction.debtList[index]] = _auction.debtValue[_auction.debtList[index]].sub(debtAmount);
        }

        uint collateralPercent = _percentage.mul(offeringRatio).div(pricePrecision);

        for (index = 0; index < _auction.collateralList.length; index++) {
            uint collatAmount = _auction.collateralValue[_auction.collateralList[index]]
                .mul(collateralPercent).div(percentPrecision);
            uint processedCollatAmount = _auction.collateralValue[_auction.collateralList[index]]
                .mul(_percentage).div(percentPrecision);
            // require(collatAmount <= ERC20(_auction.collateralList[index]).allowance(collateralContract, address(this)),
            //     "Low allowance of collateral token."
            // );
            // ERC20(_auction.collateralList[index]).safeTransferFrom(collateralContract, msg.sender, collatAmount);
            // ERC20(_auction.collateralList[index]).safeTransferFrom(collateralContract, _auction.owner, processedCollatAmount.sub(collatAmount));
            FantomMint(fantomMintContract).settleLiquidationBid(_auction.collateralList[index],msg.sender, collatAmount);
            FantomMint(fantomMintContract).settleLiquidationBid(_auction.collateralList[index],_auction.owner, processedCollatAmount.sub(collatAmount));
            _auction.collateralValue[_auction.collateralList[index]] = _auction.collateralValue[_auction.collateralList[index]].sub(processedCollatAmount);
        }
        
        if (_percentage == percentPrecision) {
            // Auction ended
            for (index = 0; index < _auction.collateralList.length; index++) {
                uint collatAmount = _auction.collateralValue[_auction.collateralList[index]];
                require(collatAmount <= ERC20(_auction.collateralList[index]).allowance(collateralContract, address(this)),
                    "Low allowance of collateral token."
                );
                //ERC20(_auction.collateralList[index]).safeTransferFrom(collateralContract, _auction.owner, collatAmount);
                FantomMint(fantomMintContract).settleLiquidationBid(_auction.collateralList[index], _auction.owner, collatAmount);
                _auction.collateralValue[_auction.collateralList[index]] = 0;
            }
            uint replaceNonce = auctionList[auctionList.length - 1].nonce;
            auctionIndexer[replaceNonce] = auctionIndexer[_nonce];
            auctionList[auctionIndexer[_nonce] - 1] = auctionList[auctionList.length - 1];
            auctionList.pop();
            auctionIndexer[_nonce] = 0;
        }
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

        AuctionInformation memory _tempAuction;
        _tempAuction.owner = _targetAddress;
        _tempAuction.round = 1;
        _tempAuction.startPrice = auctionBeginPrice;
        _tempAuction.intervalPrice = intervalPriceDiff;
        _tempAuction.minPrice = defaultMinPrice;
        _tempAuction.startTime = block.timestamp;
        _tempAuction.intervalTime = intervalTimeDiff;
        _tempAuction.endTime = block.timestamp + auctionDuration;

        auctionList.push(_tempAuction);

        AuctionInformation storage _auction = auctionList[auctionList.length - 1];

        uint index;
        uint tokenCount;
        address tokenAddress;
        uint tokenBalance;
        tokenCount = collateralPool.tokensCount();
        for (index = 0; index < tokenCount; index++) {
            tokenAddress = collateralPool.getToken(index);
            tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
            if (tokenBalance > 0) {
                collateralPool.sub(_targetAddress, tokenAddress, tokenBalance);
                _auction.collateralList.push(tokenAddress);
                _auction.collateralValue[tokenAddress] = tokenBalance;
            }
        }

        tokenCount = debtPool.tokensCount();
        for (index = 0; index < tokenCount; index++) {
            tokenAddress = debtPool.getToken(index);
            tokenBalance = debtPool.balanceOf(_targetAddress, tokenAddress);
            if (tokenBalance > 0) {
                debtPool.sub(_targetAddress, tokenAddress, tokenBalance);
                _auction.debtList.push(tokenAddress);
                _auction.debtValue[tokenAddress] = tokenBalance.mul(101).div(100);
            }
        }

        totalNonce += 1;
        _auction.nonce = totalNonce;

        auctionIndexer[totalNonce] = auctionList.length;

        emit AuctionStarted(totalNonce, _targetAddress);
    }

    function updateLiquidationFlag(bool _live) external auth {
        live = _live;
    }
}
