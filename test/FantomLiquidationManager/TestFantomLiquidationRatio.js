const {
  BN,
  constants,
  expectEvent,
  expectRevert,
  time
} = require('@openzeppelin/test-helpers');

const { ethers } = require('hardhat');
const { expect } = require('chai');

const { weiToEther, etherToWei } = require('../utils/index');

const FantomLiquidationManager = artifacts.require(
  'MockFantomLiquidationManager'
);
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

let startTime;

contract('FantomLiquidationManager', function([
  owner,
  admin,
  borrower,
  firstBidder,
  secondBidder,
  initiator
]) {
  before(async function() {
    provider = ethers.provider;

    /** all the necessary setup  */
    this.fantomMintAddressProvider = await FantomMintAddressProvider.new({
      from: owner
    });
    await this.fantomMintAddressProvider.initialize(owner);

    this.fantomLiquidationManager = await FantomLiquidationManager.new({
      from: owner
    });
    await this.fantomLiquidationManager.initialize(
      owner,
      this.fantomMintAddressProvider.address
    );

    this.fantomMint = await FantomMint.new({ from: owner });
    await this.fantomMint.initialize(
      owner,
      this.fantomMintAddressProvider.address
    );

    this.fantomMintTokenRegistry = await FantomMintTokenRegistry.new();
    await this.fantomMintTokenRegistry.initialize(owner);

    this.collateralPool = await FantomDeFiTokenStorage.new({ from: owner });
    await this.collateralPool.initialize(
      this.fantomMintAddressProvider.address,
      true
    );

    this.debtPool = await FantomDeFiTokenStorage.new({ from: owner });
    await this.debtPool.initialize(
      this.fantomMintAddressProvider.address,
      true
    );

    this.fantomFUSD = await FantomFUSD.new({ from: owner });

    await this.fantomFUSD.initialize(owner);

    this.fantomMintRewardDistribution = await FantomMintRewardDistribution.new({
      from: owner
    });
    await this.fantomMintRewardDistribution.initialize(
      owner,
      this.fantomMintAddressProvider.address
    );

    this.mockToken = await MockToken.new({ from: owner });
    await this.mockToken.initialize('wFTM', 'wFTM', 18);

    this.mockPriceOracleProxy = await MockPriceOracleProxy.new({
      from: owner
    });

    await this.fantomMintAddressProvider.setFantomMint(
      this.fantomMint.address,
      { from: owner }
    );
    await this.fantomMintAddressProvider.setCollateralPool(
      this.collateralPool.address,
      { from: owner }
    );
    await this.fantomMintAddressProvider.setDebtPool(this.debtPool.address, {
      from: owner
    });
    await this.fantomMintAddressProvider.setTokenRegistry(
      this.fantomMintTokenRegistry.address,
      { from: owner }
    );
    await this.fantomMintAddressProvider.setRewardDistribution(
      this.fantomMintRewardDistribution.address,
      { from: owner }
    );
    await this.fantomMintAddressProvider.setPriceOracleProxy(
      this.mockPriceOracleProxy.address,
      { from: owner }
    );
    await this.fantomMintAddressProvider.setFantomLiquidationManager(
      this.fantomLiquidationManager.address,
      { from: owner }
    );

    // set the initial value; 1 wFTM = 1 USD; 1 xFTM = 1 USD; 1 fUSD = 1 USD
    await this.mockPriceOracleProxy.setPrice(
      this.mockToken.address,
      etherToWei(1)
    );
    await this.mockPriceOracleProxy.setPrice(
      this.fantomFUSD.address,
      etherToWei(1)
    );

    await this.fantomMintTokenRegistry.addToken(
      this.mockToken.address,
      '',
      this.mockPriceOracleProxy.address,
      18,
      true,
      true,
      false,
      true
    );
    await this.fantomMintTokenRegistry.addToken(
      this.fantomFUSD.address,
      '',
      this.mockPriceOracleProxy.address,
      18,
      true,
      false,
      true,
      false
    );

    await this.fantomFUSD.addMinter(this.fantomMint.address, { from: owner });

    await this.fantomLiquidationManager.updateFantomMintContractAddress(
      this.fantomMint.address,
      { from: owner }
    );

    await this.fantomLiquidationManager.updateInitiatorBonus(etherToWei(0.05));

    // mint firstBidder enough fUSD to bid for liquidated collateral
    await this.fantomFUSD.mint(firstBidder, etherToWei(10000), {
      from: owner
    });

    await this.fantomFUSD.mint(secondBidder, etherToWei(10000), {
      from: owner
    });
  });

  describe('Offering ratio provided according to time', function() {
    before(async function() {
      await this.mockToken.mint(borrower, etherToWei(9999));

      await this.mockToken.approve(this.fantomMint.address, etherToWei(9999), {
        from: borrower
      });

      // borrower deposits all his/her 9999 wFTM
      await this.fantomMint.mustDeposit(
        this.mockToken.address,
        etherToWei(9999),
        { from: borrower }
      );

      await this.fantomMint.mustMintMax(this.fantomFUSD.address, 30000, {
        from: borrower
      });

      await this.mockPriceOracleProxy.setPrice(
        this.mockToken.address,
        etherToWei(0.5)
      );

      startTime = await time.latest();
      await this.fantomLiquidationManager.setTime(startTime);

      await this.fantomLiquidationManager.liquidate(borrower, {
        from: initiator
      });
    });

    it('should show offering ratio -- 30% (after 1 minute)', async function() {
      startTime = Number(startTime) + 60; //passing a timestamp with additional 60 seconds
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('30000000');
    });

    it('should show offering ratio -- 32% (after 1 minute 20 seconds)', async function() {
      startTime = Number(startTime) + 20;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('32000000');
    });

    it('should show offering ratio -- 34% (after 2 minutes)', async function() {
      startTime = Number(startTime) + 40;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('34000000');
    });

    it('should show offering ratio -- 47% (after 30 minutes)', async function() {
      startTime = Number(startTime) + 1680;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('47068800');
    });

    it('should show offering ratio -- 60% (after 1 hour)', async function() {
      startTime = Number(startTime) + 1800;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('60000000');
    });

    it('should show offering ratio -- 84% (after 3 days)', async function() {
      startTime = Number(startTime) + 255600;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('84275200');
    });

    it('should show offering ratio -- 100% (after 5 days)', async function() {
      startTime = Number(startTime) + 172800;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('100000000');
    });

    it('should show offering ratio -- 100% (after 5 and 1 hour)', async function() {
      startTime = Number(startTime) + 428460;
      let details = await this.fantomLiquidationManager.getAuctionPricing(
        new BN('1'),
        new BN(startTime)
      );

      const { 0: offeringRatio } = details;
      expect(offeringRatio.toString()).to.be.equal('100000000');
    });
  });
});
