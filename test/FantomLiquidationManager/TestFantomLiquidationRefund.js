const {
  BN,
  constants,
  expectEvent,
  expectRevert,
  time
} = require('@openzeppelin/test-helpers');

const { ethers } = require('hardhat');
const { expect } = require('chai');

const { weiToEther, etherToWei, amount18 } = require('../utils/index');

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

let debtValue;
let offeredRatio;
let totalSupply;
let finalInitiatorBalance;
let oldBidderTwoBalance;
let provider;
let startTime;

const PRICE_PRECISION = 1e18;

contract(
  'FantomLiquidationManager',
  function ([
    owner,
    admin,
    borrower,
    firstBidder,
    secondBidder,
    initiator
  ]) {
    before(async function () {
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

      this.fantomMintRewardDistribution =
        await FantomMintRewardDistribution.new({
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

      await this.fantomLiquidationManager.updateInitiatorBonus(
        etherToWei(0.05)
      );

      // mint firstBidder enough fUSD to bid for liquidated collateral
      await this.fantomFUSD.mint(firstBidder, etherToWei(10000), {
        from: owner
      });

      await this.fantomFUSD.mint(secondBidder, etherToWei(10000), {
        from: owner
      });

    });

    describe('Liquidation phase [Price goes down, two bidders take part in the auction]', function () {
      before(async function () {
        await this.mockToken.mint(borrower, etherToWei(9999));

        await this.mockToken.approve(
          this.fantomMint.address,
          etherToWei(9999),
          {
            from: borrower
          }
        );

        // borrower deposits all his/her 9999 wFTM
        await this.fantomMint.mustDeposit(
          this.mockToken.address,
          etherToWei(9999),
          { from: borrower }
        );

        await this.fantomMint.mustMintMax(this.fantomFUSD.address, 30000, {
          from: borrower
        });

        totalSupply = weiToEther(await this.fantomFUSD.totalSupply());
      });

      it('should get the new updated wFTM price ($1 -> $0.5)', async function () {
        // assume: the value of wFTM has changed to 0.5 USD !!
        await this.mockPriceOracleProxy.setPrice(
          this.mockToken.address,
          etherToWei(0.5)
        );

        const price = await this.mockPriceOracleProxy.getPrice(
          this.mockToken.address
        );

        expect(weiToEther(price).toString()).to.be.equal('0.5');
      });

      it('should find collateral not eligible anymore', async function () {

        // make sure the collateral isn't eligible any more
        const isEligible =
          await this.fantomLiquidationManager.collateralIsEligible(borrower);

        expect(isEligible).to.be.equal(false);
      });

      it('should show unused balance (10000) for initiator', async function () {
        let balance = await provider.getBalance(initiator);
        expect(Number(weiToEther(balance))).to.equal(10000);
      });

      it('should start liquidation', async function () {
        startTime = await time.latest();
        await this.fantomLiquidationManager.setTime(startTime);

        let _auctionStartEvent =
          await this.fantomLiquidationManager.liquidate(borrower, {
            from: initiator
          });

        expectEvent(_auctionStartEvent, 'AuctionStarted', {
          0: new BN('1'),
          1: borrower
        });
      });

      it('should get correct liquidation details', async function () {
        let newTime = Number(startTime) + 60; //passing a timestamp with 60 additional seconds

        let details = await this.fantomLiquidationManager.getAuctionPricing(
          new BN('1'),
          new BN(newTime)
        );

        const { 0: offeringRatio } = details;

        offeredRatio = offeringRatio;
        debtValue = 3366329999999999999998 / 1e18;;

        expect(offeringRatio.toString()).to.equal(amount18(0.3));
      });

      it('increase time by 1 minute', async function() {
        await this.fantomLiquidationManager.increaseTime(60);
      })

      it('should allow a bidder1 to bid (25%)', async function () {
        await this.fantomFUSD.approve(
          this.fantomLiquidationManager.address,
          etherToWei(1500),
          { from: firstBidder }
        );

        let _bidPlacedEvent = await this.fantomLiquidationManager.bid(1, etherToWei(0.25), {
          from: firstBidder,
          value: etherToWei(0.05)
        });
  
        expectEvent(_bidPlacedEvent, 'BidPlaced', {
          nonce: new BN('1'),
          percentage: etherToWei(0.25),
          bidder: firstBidder,
          offeredRatio: etherToWei(0.3)
        });
      });

      it('the initiator should get initiatorBonus', async function () {
        finalInitiatorBalance = await provider.getBalance(initiator);
        expect(
          Number(weiToEther(finalInitiatorBalance))
        ).to.be.greaterThanOrEqual(10000);
      });

      it('the bidder1 should have (10000 - (3366.33 * 0.25)) 9158.41 fUSD remaining', async function () {
        let remainingBalance = 10000 - debtValue * 0.25;
        let currentBalance = await this.fantomFUSD.balanceOf(firstBidder);

        expect(Number(weiToEther(currentBalance))).to.equal(remainingBalance);
      });

      it('the bidder1 should get 30% of the (1/4) wFTM collateral', async function () {
        let balance = await this.mockToken.balanceOf(firstBidder);

        let offeredCollateral = ((offeredRatio / PRICE_PRECISION) * (0.25 * 9999));
        expect(weiToEther(balance)).to.equal(offeredCollateral.toString());
      });

      it('should allow a bidder2 to bid on the remaining collateral', async function () {
        await this.fantomFUSD.approve(
          this.fantomLiquidationManager.address,
          etherToWei(3900),
          { from: secondBidder }
        );

        let _bidPlacedEvent = await this.fantomLiquidationManager.bid(1, etherToWei(1), {
          from: secondBidder,
          value: etherToWei(0.05)
        });
  
        expectEvent(_bidPlacedEvent, 'BidPlaced', {
          nonce: new BN('1'),
          percentage: etherToWei(0.75),
          bidder: secondBidder,
          offeredRatio: etherToWei(0.3)
        });
        
        oldBidderTwoBalance = await provider.getBalance(secondBidder);
      });

      it('the initiator should not get a bonus again', async function () {
        let balance = await provider.getBalance(initiator);

        expect(Number(weiToEther(balance))).to.be.lessThanOrEqual(
          Number(weiToEther(finalInitiatorBalance))
        );
      });

      it('should make sure bidder2 gets refunded', async function () {
        let balance = await provider.getBalance(secondBidder);

        expect(Number(weiToEther(balance))).to.be.lessThanOrEqual(
          Number(weiToEther(oldBidderTwoBalance))
        );
      });

      it('the bidder2 should have (10000 - (3366.33 * 0.75)) 7,475.25 fUSD remaining', async function () {
        let remainingBalance = 10000 - debtValue * 0.75;
        let currentBalance = await this.fantomFUSD.balanceOf(secondBidder);

        expect(weiToEther(currentBalance) * 1).to.equal(
          Number(remainingBalance.toFixed(4))
        );
      });

      it('the bidder2 should get 30% of the (3/4) wFTM collateral', async function () {
        let balance = await this.mockToken.balanceOf(secondBidder);
        
        let offeredCollateral = ((offeredRatio / PRICE_PRECISION) * (0.75 * 9999));
        expect(weiToEther(balance)).to.equal(offeredCollateral.toString());
      });

      it('the collateral pool should get the remaining 70% of the wFTM collateral back', async function () {
        let balance = await this.collateralPool.balanceOf(borrower, this.mockToken.address);

        let remainingCollateral = 9999 - (offeredRatio / PRICE_PRECISION * 9999);
        expect(weiToEther(balance)).to.equal(remainingCollateral.toString());
      });

      it('should show the new total supply (after burning tokens)', async function () {
        let burntAmount = await this.fantomLiquidationManager.getBurntAmount(this.fantomFUSD.address);
        let newTotalSupply = weiToEther(await this.fantomFUSD.totalSupply());

        expect(Number(newTotalSupply)).to.equal(
         Number((totalSupply - (weiToEther(burntAmount) * 1)).toFixed(3))
        );
      });
    });
  }
);
