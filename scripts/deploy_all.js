// to deploy locally
// run: npx hardhat node on a terminal
// then run: npx hardhat run --network localhost scripts/deploy_all.js

async function main(network) {
  console.log('network: ', network.name);

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deployer's address: `, deployerAddress);

  const etherToWei = (n) => {
    return new web3.utils.BN(web3.utils.toWei(n.toString(), 'ether'));
  };

  ///
  const FantomMintAddressProvider = await ethers.getContractFactory(
    'FantomMintAddressProvider'
  );
  const fantomMintAddressProvider = await FantomMintAddressProvider.deploy();
  await fantomMintAddressProvider.deployed();
  await fantomMintAddressProvider.initialize(deployerAddress);
  console.log(
    'FantomMintAddressProvider deployed at',
    fantomMintAddressProvider.address
  );
  ///

  ///
  const FantomLiquidationManager = await ethers.getContractFactory(
    'FantomLiquidationManager'
  );
  const fantomLiquidationManager = await FantomLiquidationManager.deploy();
  await fantomLiquidationManager.deployed();
  console.log(
    'FantomLiquidationManager deployed at',
    fantomLiquidationManager.address
  );
  await fantomLiquidationManager.initialize(
    deployerAddress,
    fantomMintAddressProvider.address
  );
  ///

  /* ///  TODO:  needs ProxyAdmin
  const FantomLiquidationManager = await ethers.getContractFactory(
    'FantomLiquidationManager'
  );
  const fantomLiquidationManagerImpl = await FantomLiquidationManager.deploy();
  await fantomLiquidationManagerImpl.deployed();
  console.log(
    'FantomLiquidationManager Implemaentaion deployed at',
    fantomLiquidationManagerImpl.address
  );  
  ///

  ///
  const FantomLiquidationManagerProxy = await ethers.getContractFactory(
    'FantomUpgradeabilityProxy'
  );
  const fantomLiquidationManagerProxy = await FantomLiquidationManagerProxy.deploy(
    fantomLiquidationManagerImpl.address,
    deployerAddress,
    []
  );
  await fantomLiquidationManagerProxy.deployed();
  console.log(
    'FantomLiquidationManagerProxy deployed at',
    fantomLiquidationManagerProxy.address
  );
  const fantomLiquidationManager = await ethers.getContractAt(
    'FantomLiquidationManager',
    fantomLiquidationManagerProxy.address
  );
  await fantomLiquidationManager.initialize(
    PROXY_ADMIN_ADDRESS,
    fantomMintAddressProvider.address
  );
  /// */

  ///
  const FantomMint = await ethers.getContractFactory('FantomMint');
  const fantomMint = await FantomMint.deploy();
  await fantomMint.deployed();
  console.log('FantomMint deployed at', fantomMint.address);
  await fantomMint.initialize(
    deployerAddress,
    fantomMintAddressProvider.address
  );
  ///

  ///
  const FantomMintTokenRegistry = await ethers.getContractFactory(
    'FantomMintTokenRegistry'
  );
  const fantomMintTokenRegistry = await FantomMintTokenRegistry.deploy();
  await fantomMintTokenRegistry.deployed();
  console.log(
    'FantomMintTokenRegistry deployed at',
    fantomMintTokenRegistry.address
  );
  await fantomMintTokenRegistry.initialize(deployerAddress);
  ///

  ///
  const CollateralPool = await ethers.getContractFactory(
    'FantomDeFiTokenStorage'
  );
  const collateralPool = await CollateralPool.deploy();
  await collateralPool.deployed();
  console.log(
    'FantomDeFiTokenStorage (Collateral Pool) deployed at',
    collateralPool.address
  );
  await collateralPool.initialize(fantomMintAddressProvider.address, true);
  ///

  ///
  const DebtPool = await ethers.getContractFactory('FantomDeFiTokenStorage');
  const debtPool = await DebtPool.deploy();
  await debtPool.deployed();
  console.log(
    'FantomDeFiTokenStorage (Debt Pool) deployed at',
    debtPool.address
  );
  await debtPool.initialize(fantomMintAddressProvider.address, true);
  ///

  ///
  const FantomFUSD = await ethers.getContractFactory('FantomFUSD');
  const fantomFUSD = await FantomFUSD.deploy();
  await fantomFUSD.deployed();
  console.log('FantomFUSD deployed at', fantomFUSD.address);
  //await fantomFUSD.initialize(deployerAddress); //why not working??
  //await fantomFUSD.init(deployerAddress); // if initialize in FantomFUSD is renamed to another name such as init, it will work
  ///

  ///
  const FantomMintRewardDistribution = await ethers.getContractFactory(
    'FantomMintRewardDistribution'
  );
  const fantomMintRewardDistribution = await FantomMintRewardDistribution.deploy();
  fantomMintRewardDistribution.deployed();
  console.log(
    'FantomMintRewardDistribution deployed at',
    fantomMintRewardDistribution.address
  );
  await fantomMintRewardDistribution.initialize(
    deployerAddress,
    fantomMintAddressProvider.address
  );
  ///

  ///
  let wFTMAddress;
  let priceOracleProxyAddress;

  if (network.name === 'localhost') {
    const MockToken = await ethers.getContractFactory('MockToken');
    const mockToken = await MockToken.deploy();
    await mockToken.deployed();
    console.log('MockToken deployed at', mockToken.address);
    wFTMAddress = mockToken.address;
    await mockToken.initialize('wFTM', 'wFTM', 18);
  }

  switch (network.name) {
    case 'mainnet':
      wFTMAddress = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
      break;
    case 'testnet':
      wFTMAddress = '0xf1277d1ed8ad466beddf92ef448a132661956621';
      break;
    default:
      break;
  }

  if (network.name === 'localhost') {
    const MockPriceOracleProxy = await ethers.getContractFactory(
      'MockPriceOracleProxy'
    );
    const mockPriceOracleProxy = await MockPriceOracleProxy.deploy();
    await mockPriceOracleProxy.deployed();
    console.log(
      'MockPriceOracleProxy deployed at',
      mockPriceOracleProxy.address
    );
    priceOracleProxyAddress = mockPriceOracleProxy.address;

    // set the initial value; 1 wFTM = 1 USD; 1 fUSD = 1 USD
    await mockPriceOracleProxy.setPrice(wFTMAddress, etherToWei(1).toString());
    await mockPriceOracleProxy.setPrice(
      fantomFUSD.address,
      etherToWei(1).toString()
    );
  }
  switch (network.name) {
    case 'mainnet':
      priceOracleProxyAddress = '0x????'; //TODO: get the correct address
      break;
    case 'testnet':
      priceOracleProxyAddress = '0x????'; //TODO: get the correct address
      break;
    default:
      break;
  }

  ///

  ///
  await fantomMintAddressProvider.setFantomMint(fantomMint.address);
  await fantomMintAddressProvider.setCollateralPool(collateralPool.address);
  await fantomMintAddressProvider.setDebtPool(debtPool.address);
  await fantomMintAddressProvider.setTokenRegistry(
    fantomMintTokenRegistry.address
  );
  await fantomMintAddressProvider.setRewardDistribution(
    fantomMintRewardDistribution.address
  );
  await fantomMintAddressProvider.setPriceOracleProxy(priceOracleProxyAddress);
  await fantomMintAddressProvider.setFantomLiquidationManager(
    fantomLiquidationManager.address
  );
  await fantomMintTokenRegistry.addToken(
    wFTMAddress,
    '',
    priceOracleProxyAddress,
    18,
    true,
    true,
    false
  );
  // TODO: the FantomFUSD needs to run the initialize function first
  /* await fantomMintTokenRegistry.addToken(
    fantomFUSD.address,
    '',
    priceOracleProxyAddress,
    18,
    true,
    false,
    true
  ); */

  //await fantomFUSD.addMinter(fantomMint.address); //TODO: FantomFUSD needs to run the initialize function first

  await fantomLiquidationManager.updateFantomMintContractAddress(
    fantomMint.address
  );
  await fantomLiquidationManager.updateFantomUSDAddress(fantomFUSD.address);
  let fantomFeeVault;
  switch (network.name) {
    case 'mainnet':
      fantomFeeVault = '0x????'; //TODO get the correct address
      break;
    case 'testnet':
      fantomFeeVault = '0x????'; //TODO get the correct address
      break;
    default:
      fantomFeeVault = deployerAddress;
      break;
  }
  await fantomLiquidationManager.updateFantomFeeVault(fantomFeeVault);
  ///
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main(network)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
