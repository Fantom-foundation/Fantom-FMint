pragma solidity ^0.5.0;

import '@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol';
import '@openzeppelin/upgrades/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol';

import '../interfaces/IFantomMintAddressProvider.sol';
import '../interfaces/IFantomDeFiTokenStorage.sol';
import '../modules/FantomMintErrorCodes.sol';
import '../FantomMint.sol';
import '../utility/FantomMintTokenRegistry.sol';
import '../modules/FantomMintBalanceGuard.sol';

// FantomLiquidationManager implements the liquidation model
// with the ability to fine tune settings by the contract owner.
contract FantomLiquidationManager is
  Initializable,
  Ownable,
  FantomMintErrorCodes,
  ReentrancyGuard
{
  // define used libs
  using SafeMath for uint256;
  using Address for address;
  using SafeERC20 for ERC20;

  event AuctionStarted(uint256 indexed nonce, address indexed user);
  event BidPlaced(uint256 indexed nonce, uint256 percentage, address indexed bidder, uint256 offeredRatio);

  struct AuctionInformation {
    address target;
    address payable initiator;
    uint256 startTime;
    uint256 remainingPercentage;
    address[] collateralList;
    address[] debtList;
    uint256[] collateralValue;
    uint256[] debtValue;
  }

  bytes32 private constant MOD_FANTOM_MINT = 'fantom_mint';
  bytes32 private constant MOD_COLLATERAL_POOL = 'collateral_pool';
  bytes32 private constant MOD_DEBT_POOL = 'debt_pool';
  bytes32 private constant MOD_PRICE_ORACLE = 'price_oracle_proxy';
  bytes32 private constant MOD_REWARD_DISTRIBUTION = 'reward_distribution';
  bytes32 private constant MOD_TOKEN_REGISTRY = 'token_registry';
  bytes32 private constant MOD_ERC20_REWARD_TOKEN = 'erc20_reward_token';

  mapping(uint256 => AuctionInformation) public getAuction;
  mapping(address => uint256) public getBurntAmount;

  // addressProvider represents the connection to other FMint related contracts.
  IFantomMintAddressProvider public addressProvider;

  address public fantomMintContract;

  uint256 internal currentNonce;

  uint256 public initiatorBonus;

  uint256 constant PRECISION = 1e18;
  uint256 constant STABILITY_RATIO = 101;

  // initialize initializes the contract properly before the first use.
  function initialize(address owner, address _addressProvider)
    public
    initializer
  {
    // initialize the Ownable
    Ownable.initialize(owner);

    // remember the address provider for the other protocol contracts connection
    addressProvider = IFantomMintAddressProvider(_addressProvider);
    currentNonce = 0;
  }

  function updateAddressProvider(address _addressProvider) external onlyOwner {
    addressProvider = IFantomMintAddressProvider(_addressProvider);
  }

  function updateFantomMintContractAddress(address _fantomMintContract)
    external
    onlyOwner
  {
    fantomMintContract = _fantomMintContract;
  }

  function updateInitiatorBonus(uint256 _initatorBonus) external onlyOwner {
    initiatorBonus = _initatorBonus;
  }

  modifier onlyNotContract() {
    require(_msgSender() == tx.origin);
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
    return
      FantomMint(addressProvider.getAddress(MOD_FANTOM_MINT))
        .checkCollateralCanDecrease(
          _account,
          getCollateralPool().getToken(0),
          0
        );
  }

    function getAuctionPricing(uint256 _nonce, uint256 currentTime)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      address[] memory,
      address[] memory
    )
  {
    require(
      getAuction[_nonce].remainingPercentage > 0,
      'Auction not found'
    );
    AuctionInformation storage _auction = getAuction[_nonce];
    uint256 timeDiff = currentTime.sub(_auction.startTime);

    uint256 offeringRatio = _getRatio(timeDiff);
    
    return (
      offeringRatio,
      initiatorBonus,
      getAuction[_nonce].remainingPercentage,
      _auction.startTime,
      _auction.collateralList,
      _auction.debtList
    );
  }

  function bid(uint256 _nonce, uint256 _percentage)
    public
    payable
    nonReentrant
  {
    require(msg.value == initiatorBonus, 'Insufficient funds to bid.');

    require(
      getAuction[_nonce].remainingPercentage > 0,
      'Auction not found'
    );

    require(_percentage > 0, 'Percent must be greater than 0');

    AuctionInformation storage _auction = getAuction[_nonce];
    if (_percentage > _auction.remainingPercentage) {
      _percentage = _auction.remainingPercentage;
    }

    if (_auction.remainingPercentage == PRECISION) {
      _auction.initiator.call.value(msg.value)('');
    } else {
      msg.sender.call.value(msg.value)('');
    }

    uint256 actualPercentage = _percentage.mul(PRECISION).div(
      _auction.remainingPercentage
    );

    uint256 timeDiff = _now().sub(_auction.startTime);
    uint256 offeringRatio = _getRatio(timeDiff);

    uint256 index;
    address debtTokenAddress;

    IFantomDeFiTokenStorage collateralPool = getCollateralPool();

    for (index = 0; index < _auction.debtList.length; index++) {
      debtTokenAddress = _auction.debtList[index];

      uint256 debtAmount = _auction
        .debtValue[index]
        .mul(actualPercentage)
        .div(PRECISION);

      if (actualPercentage < PRECISION){
        debtAmount = debtAmount.add(1);
      }

      require(
        debtAmount <=
          ERC20(debtTokenAddress).allowance(msg.sender, address(this)),
        'Low allowance of debt token.'
      );

      getBurntAmount[debtTokenAddress] = getBurntAmount[debtTokenAddress].add(debtAmount);

      ERC20Burnable(debtTokenAddress).burnFrom(msg.sender, debtAmount);
      _auction.debtValue[index] = _auction
        .debtValue[index]
        .sub(debtAmount);
    }

    uint256 collateralPercent = actualPercentage.mul(offeringRatio).div(
      PRECISION
    );

    for (index = 0; index < _auction.collateralList.length; index++) {
      uint256 collatAmount = _auction
        .collateralValue[index]
        .mul(collateralPercent)
        .div(PRECISION);
      
      uint256 processedCollatAmount = _auction
        .collateralValue[index]
        .mul(actualPercentage)
        .div(PRECISION);

      FantomMint(fantomMintContract).settleLiquidationBid(
        _auction.collateralList[index],
        msg.sender,
        collatAmount
      );

      collateralPool.add(_auction.target, _auction.collateralList[index], processedCollatAmount.sub(collatAmount));

      _auction.collateralValue[index] = _auction
        .collateralValue[index]
        .sub(processedCollatAmount);
    }

    _auction.remainingPercentage = _auction.remainingPercentage.sub(
      _percentage
    );

    emit BidPlaced(_nonce, _percentage, msg.sender, offeringRatio);

    if (actualPercentage == PRECISION) {
      // Auction ended
      for (index = 0; index < _auction.collateralList.length; index++) {
        uint256 collatAmount = _auction.collateralValue[index];
        collateralPool.add(_auction.target, _auction.collateralList[index], collatAmount);
        _auction.collateralValue[index] = 0;
      }
    }
  }

  function liquidate(address _targetAddress)
    external
    nonReentrant
    onlyNotContract
  {
    // get the collateral pool
    IFantomDeFiTokenStorage collateralPool = getCollateralPool();
    // get the debt pool
    IFantomDeFiTokenStorage debtPool = getDebtPool();

    require(
      !collateralIsEligible(_targetAddress),
      'Collateral is not eligible for liquidation'
    );

    require(
      collateralPool.totalOf(_targetAddress) > 0,
      'The value of the collateral is 0'
    );

    addressProvider.getRewardDistribution().rewardUpdate(_targetAddress);

    AuctionInformation memory _tempAuction;
    _tempAuction.target = _targetAddress;
    _tempAuction.initiator = msg.sender;
    _tempAuction.startTime = _now();

    currentNonce += 1;
    getAuction[currentNonce] = _tempAuction;

    AuctionInformation storage _auction = getAuction[currentNonce];

    uint256 index;
    uint256 tokenCount;
    address tokenAddress;
    uint256 tokenBalance;
    
    tokenCount = collateralPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = collateralPool.getToken(index);
      if(FantomMintTokenRegistry(addressProvider.getAddress(MOD_TOKEN_REGISTRY)).canTrade(tokenAddress)){
        tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
        if (tokenBalance > 0) {
          collateralPool.sub(_targetAddress, tokenAddress, tokenBalance);
          _auction.collateralList.push(tokenAddress);
          _auction.collateralValue.push(tokenBalance);
        }
      }
    }

    require(_auction.collateralList.length > 0, 'no tradable collateral found');

    tokenCount = debtPool.tokensCount();
    
    for (index = 0; index < tokenCount; index++) {
      tokenAddress = debtPool.getToken(index);
      tokenBalance = debtPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        debtPool.sub(_targetAddress, tokenAddress, tokenBalance);
        _auction.debtList.push(tokenAddress);
        _auction.debtValue.push(tokenBalance.mul(STABILITY_RATIO).div(100));
      }
    }

    _auction.remainingPercentage = PRECISION;

    emit AuctionStarted(currentNonce, _targetAddress);
  }

  function _getRatio(uint256 time) internal view returns (uint256) {
     uint256 m;
     uint256 c;
     uint256 ratio;

     if (time <= 60) { // up to 1 minute -> 1-30%
       m = 3389830508474578;
       c = 96610169491525320;
     } else if (time <= 120) { // up to 2 minutes -> 30-34%
       m = 666666666666667;
       c = 259999999999999960;
     } else if (time <= 3600) { // up to 1 hour -> 34-60%
       m = 74712643678160;
       c = 331034482758624000;
     } else if (time <= 432000) { // up to 5 days -> 60-100%
       m = 933706816059;
       c = 596638655462512000;
     } else { // beyond 5 days -> 100%
       ratio = 1e18;

       return ratio;
     }

     ratio = m.mul(time).add(c);

     return ratio;
   }

  function _now() internal view returns (uint256) {
    return now;
  }
}
