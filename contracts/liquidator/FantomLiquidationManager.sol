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


interface ISFC {
    function getValidatorID(address) external returns (uint256);

    function liquidateSFTM(
        address delegator,
        uint256 toValidatorID,
        uint256 amount
    ) external;
}

interface IStakeTokenizer {
  function outstandingSFTM(address, uint256) external returns (uint256);
  
  function sFTMTokenAddress() external returns (address);
}


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
  ISFC public sfc;
  IStakeTokenizer public stakeTokenizer;

  address public fantomMintContract;

  // initialize initializes the contract properly before the first use.
  function initialize(address owner, address _addressProvider, address _sfc, address _stakeTokenizer)
    public
    initializer
  {
    // initialize the Ownable
    Ownable.initialize(owner);

    // remember the address provider for the other protocol contracts connection
    addressProvider = IFantomMintAddressProvider(_addressProvider);
    sfc = ISFC(_sfc);
    stakeTokenizer = IStakeTokenizer(_stakeTokenizer);
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

  function() payable external {
    require(msg.sender == address(sfc), "transfers not allowed");
  }

  function _handleSFTM(address _targetAddress, uint256 tokenBalance, uint256 validatorID) internal {
    ERC20(stakeTokenizer.sFTMTokenAddress()).approve(
        address(stakeTokenizer),
        tokenBalance
    );

    sfc.liquidateSFTM(_targetAddress, validatorID, tokenBalance);

    (bool sent,) = msg.sender.call.value(tokenBalance)("");
    require(sent, "Failed to send FTM");
  }

  function liquidate(address _targetAddress, uint256[] calldata validatorIDs) external nonReentrant {
    IFantomDeFiTokenStorage collateralPool = getCollateralPool();
    IFantomDeFiTokenStorage debtPool = getDebtPool();

    require(
      collateralPool.totalOf(_targetAddress) > 0,
      'The value of the collateral is 0'
    );

    addressProvider.getRewardDistribution().rewardUpdate(_targetAddress);

    uint256 index;
    uint subIndex;
    uint256 tokenCount;
    address tokenAddress;
    uint256 tokenBalance;
    uint256 remainingBalance;

    tokenCount = collateralPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = collateralPool.getToken(index);

      tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        require(
          !collateralIsEligible(_targetAddress, tokenAddress),
          'Collateral is not eligible for liquidation'
        );
      }
    }

    tokenCount = debtPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = debtPool.getToken(index);
      tokenBalance = debtPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        require(tokenBalance <= ERC20(tokenAddress).allowance(msg.sender, address(this)), 'Low allowance of debt token.');

        ERC20Burnable(tokenAddress).burnFrom(msg.sender, tokenBalance);
        debtPool.sub(_targetAddress, tokenAddress, tokenBalance);

        emit Repaid(_targetAddress, msg.sender, tokenAddress, tokenBalance);
      }
    }

    tokenCount = collateralPool.tokensCount();

    for (index = 0; index < tokenCount; index++) {
      tokenAddress = collateralPool.getToken(index);
      tokenBalance = collateralPool.balanceOf(_targetAddress, tokenAddress);
      if (tokenBalance > 0) {
        collateralPool.sub(_targetAddress, tokenAddress, tokenBalance);

        remainingBalance = tokenBalance; 

        if (tokenAddress == stakeTokenizer.sFTMTokenAddress()) {
          for (subIndex = 0; subIndex < validatorIDs.length; subIndex++) {
            uint256 stakedsFTM = stakeTokenizer.outstandingSFTM(
                _targetAddress,
                validatorIDs[subIndex]
            );

            if (stakedsFTM > 0 && remainingBalance != 0) {
                if (stakedsFTM <= remainingBalance) {
                    FantomMint(fantomMintContract).settleLiquidation(tokenAddress, address(this), stakedsFTM);
                    _handleSFTM(_targetAddress, stakedsFTM, validatorIDs[subIndex]);
                    remainingBalance = remainingBalance - stakedsFTM; 
                } 
                else {
                    FantomMint(fantomMintContract).settleLiquidation(tokenAddress, address(this), remainingBalance);
                    _handleSFTM(_targetAddress, remainingBalance, validatorIDs[subIndex]);
                    remainingBalance = 0;
                }
            }
          }
        } else {
          FantomMint(fantomMintContract).settleLiquidation(tokenAddress, msg.sender, tokenBalance);
        }

        emit Seized(_targetAddress, msg.sender, tokenAddress, tokenBalance);
      }
    }
  }
}
