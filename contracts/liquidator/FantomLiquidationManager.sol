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

  event Repaid(address indexed target, address indexed liquidator, address indexed token, uint256 amount);
  event Seized(address indexed target, address indexed liquidator, address indexed token, uint256 amount);

  bytes32 private constant MOD_FANTOM_MINT = 'fantom_mint';
  bytes32 private constant MOD_TOKEN_REGISTRY = 'token_registry';

  // addressProvider represents the connection to other FMint related contracts.
  IFantomMintAddressProvider public addressProvider;

  address public fantomMintContract;

  // initialize initializes the contract properly before the first use.
  function initialize(address owner, address _addressProvider)
    public
    initializer
  {
    // initialize the Ownable
    Ownable.initialize(owner);

    // remember the address provider for the other protocol contracts connection
    addressProvider = IFantomMintAddressProvider(_addressProvider);
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

  // getCollateralPool returns the address of collateral pool.
  function getCollateralPool() public view returns (IFantomDeFiTokenStorage) {
    return addressProvider.getCollateralPool();
  }

  // getDebtPool returns the address of debt pool.
  function getDebtPool() public view returns (IFantomDeFiTokenStorage) {
    return addressProvider.getDebtPool();
  }

  // collateralIsEligible checks if the account is eligible to liquidate.
  function collateralIsEligible(address _account, address _token) public view returns (bool) {
    return
      FantomMint(addressProvider.getAddress(MOD_FANTOM_MINT))
        .checkCollateralCanDecrease(
          _account,
          _token,
          0
        );
  }

  function liquidate(address _targetAddress) external nonReentrant {
    IFantomDeFiTokenStorage collateralPool = getCollateralPool();
    IFantomDeFiTokenStorage debtPool = getDebtPool();

    require(
      collateralPool.totalOf(_targetAddress) > 0,
      'The value of the collateral is 0'
    );

    addressProvider.getRewardDistribution().rewardUpdate(_targetAddress);

    uint256 index;
    uint256 tokenCount;
    address tokenAddress;
    uint256 tokenBalance;

    tokenCount = collateralPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = collateralPool.getToken(index);
      if(FantomMintTokenRegistry(addressProvider.getAddress(MOD_TOKEN_REGISTRY)).canTrade(tokenAddress)) {
        tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
        if (tokenBalance > 0) {
          require(
            !collateralIsEligible(_targetAddress, tokenAddress),
            'Collateral is not eligible for liquidation'
          );
        }
      }
    }

    tokenCount = debtPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = debtPool.getToken(index);
      tokenBalance = debtPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        ERC20Burnable(tokenAddress).burnFrom(msg.sender, tokenBalance);
        debtPool.sub(_targetAddress, tokenAddress, tokenBalance);
        emit Repaid(_targetAddress, msg.sender, tokenAddress, tokenBalance);
      }
    }

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = collateralPool.getToken(index);
      tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        collateralPool.sub(_targetAddress, tokenAddress, tokenBalance);
        FantomMint(fantomMintContract).settleLiquidation(tokenAddress, msg.sender, tokenBalance);
        emit Seized(_targetAddress, msg.sender, tokenAddress, tokenBalance);
      }
    }
  }
}
