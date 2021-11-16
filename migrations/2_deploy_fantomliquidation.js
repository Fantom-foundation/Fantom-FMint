const {
  deployProxy,
  upgradeProxy,
  prepareUpgrade
} = require('@openzeppelin/truffle-upgrades');

const FantomLiquidationManager = artifacts.require('FantomLiquidationManager');
const FantomMintTokenRegistry = artifacts.require('FantomMintTokenRegistry');
const FantomDeFiTokenStorage = artifacts.require('FantomDeFiTokenStorage');
const FantomMint = artifacts.require('FantomMint');
const FantomMintAddressProvider = artifacts.require(
  'FantomMintAddressProvider'
);
const FantomMintRewardDistribution = artifacts.require(
  'FantomMintRewardDistribution'
);
const FantomFUSD = artifacts.require('FantomFUSD');
const MockToken = artifacts.require('MockToken');
const MockPriceOracleProxy = artifacts.require('MockPriceOracleProxy');

const etherToWei = (n) => {
  return new web3.utils.BN(web3.utils.toWei(n.toString(), 'ether'));
};

module.exports = async function(deployer, network, accounts) {
  console.log('network: ', network);
  if (network === 'ganache' || network === 'localhost') {
    // to be deployed to the local ganache

    //////////////////////////////////////
    // deploy and set like the beforeEach in FantomLiquidationManager.test.js
    const owner = accounts[0];
    const admin = accounts[1];
    const borrower = accounts[2];
    const bidder1 = accounts[3];
    const bidder2 = accounts[4];
    const fantomFeeVault = accounts[5];
    await deployer.deploy(FantomMintAddressProvider);
    const fantomMintAddressProvider = await FantomMintAddressProvider.deployed();
    await fantomMintAddressProvider.initialize(owner);

    await deployer.deploy(FantomLiquidationManager);
    const fantomLiquidationManager = await FantomLiquidationManager.deployed();
    await fantomLiquidationManager.initialize(
      owner,
      fantomMintAddressProvider.address
    );

    await deployer.deploy(FantomMint);
    const fantomMint = await FantomMint.deployed();
    await fantomMint.initialize(owner, fantomMintAddressProvider.address);

    await deployer.deploy(FantomMintTokenRegistry);
    const fantomMintTokenRegistry = await FantomMintTokenRegistry.deployed();
    await fantomMintTokenRegistry.initialize(owner);

    await deployer.deploy(FantomDeFiTokenStorage);
    const collateralPool = await FantomDeFiTokenStorage.deployed();
    await collateralPool.initialize(fantomMintAddressProvider.address, true);

    await deployer.deploy(FantomDeFiTokenStorage);
    const debtPool = await FantomDeFiTokenStorage.deployed();
    await debtPool.initialize(fantomMintAddressProvider.address, true);

    await deployer.deploy(FantomFUSD);
    const fantomFUSD = await FantomFUSD.deployed();
    await fantomFUSD.initialize(owner);

    await deployer.deploy(FantomMintRewardDistribution);
    const fantomMintRewardDistribution = await FantomMintRewardDistribution.deployed();
    await fantomMintRewardDistribution.initialize(
      owner,
      fantomMintAddressProvider.address
    );

    await deployer.deploy(MockToken);
    const mockToken = await MockToken.deployed();
    await mockToken.initialize('wFTM', 'wFTM', 18);

    await deployer.deploy(MockPriceOracleProxy);
    const mockPriceOracleProxy = await MockPriceOracleProxy.deployed();

    await fantomMintAddressProvider.setFantomMint(fantomMint.address);
    await fantomMintAddressProvider.setCollateralPool(collateralPool.address);
    await fantomMintAddressProvider.setDebtPool(debtPool.address);
    await fantomMintAddressProvider.setTokenRegistry(
      fantomMintTokenRegistry.address
    );
    await fantomMintAddressProvider.setRewardDistribution(
      fantomMintRewardDistribution.address
    );
    await fantomMintAddressProvider.setPriceOracleProxy(
      mockPriceOracleProxy.address
    );
    await fantomMintAddressProvider.setFantomLiquidationManager(
      fantomLiquidationManager.address
    );

    // set the initial value; 1 wFTM = 1 USD; 1 fUSD = 1 USD
    await mockPriceOracleProxy.setPrice(mockToken.address, etherToWei(1));
    await mockPriceOracleProxy.setPrice(fantomFUSD.address, etherToWei(1));

    await fantomMintTokenRegistry.addToken(
      mockToken.address,
      '',
      mockPriceOracleProxy.address,
      18,
      true,
      true,
      false
    );
    await fantomMintTokenRegistry.addToken(
      fantomFUSD.address,
      '',
      mockPriceOracleProxy.address,
      18,
      true,
      false,
      true
    );

    await fantomFUSD.addMinter(fantomMint.address);

    await fantomLiquidationManager.updateFantomMintContractAddress(
      fantomMint.address
    );
    await fantomLiquidationManager.updateFantomUSDAddress(fantomFUSD.address);

    await fantomLiquidationManager.addAdmin(admin);

    await fantomLiquidationManager.updateFantomFeeVault(fantomFeeVault);

    //////////////////////////////////////

    // set like part of scenario 1
    await mockToken.mint(borrower, etherToWei(9999));
    await fantomFUSD.mint(bidder1, etherToWei(10000));
    await mockToken.approve(fantomMint.address, etherToWei(9999), {
      from: borrower
    });
    await fantomMint.mustDeposit(mockToken.address, etherToWei(9999), {
      from: borrower
    });
    await fantomMint.mustMintMax(fantomFUSD.address, 32000, { from: borrower });

    // when testing the liquidation bot, on the truffle console set the price of wFTM to 0.5
    // the liquidation bot will start the liquidation of the borrower's collateral successfully
  } else {
    const fantomLiquidationManager = await deployProxy(
      FantomLiquidationManager,
      [
        '0xe8A06462628b49eb70DBF114EA510EB3BbBDf559',
        '0xcb20a1A22976764b882C2f03f0C8523F3df54b10'
      ],
      { deployer }
    );
  }
};
