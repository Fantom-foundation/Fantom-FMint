const {
  BN,
  constants,
  expectEvent,
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
var amountToMint;

contract(
  'FantomLiquidationManager',
  function ([
    owner,
    borrower,
    liquidator
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

      this.mockToken2 = await MockToken.new({ from: owner });
      await this.mockToken2.initialize('xFTM', 'xFTM', 18);

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
        this.mockToken2.address,
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
        this.mockToken2.address,
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

      // mint liquidator enough fUSD to bid for liquidated collateral
      await this.fantomFUSD.mint(liquidator, etherToWei(10000), {
        from: owner
      });
    });

    describe('Deposit Collateral', function () {
      it('should get the correct wFTM price ($1)', async function () {
        const price = await this.mockPriceOracleProxy.getPrice(
          this.mockToken.address
        );

        expect(weiToEther(price).toString()).to.be.equal('1');
      });

      it('should allow the borrower to deposit 9999 wFTM', async function () {
        await this.mockToken.mint(borrower, etherToWei(9999));

        await this.mockToken.approve(
          this.fantomMint.address,
          etherToWei(9999),
          {
            from: borrower
          }
        );

        // make sure the wFTM (test token) can be registered
        const canDeposit = await this.fantomMintTokenRegistry.canDeposit(
          this.mockToken.address
        );
        //console.log('canDeposit: ', canDeposit);
        expect(canDeposit).to.be.equal(true);

        // borrower deposits all his/her 9999 wFTM
        await this.fantomMint.mustDeposit(
          this.mockToken.address,
          etherToWei(9999),
          { from: borrower }
        );

        const balance1 = await this.mockToken.balanceOf(borrower);

        expect(balance1).to.be.bignumber.equal('0');
      });

      it('should show 9999 wFTM in Collateral Pool (for borrower)', async function () {
        // check the collateral balance of the borrower in the collateral pool
        const balance2 = await this.collateralPool.balanceOf(
          borrower,
          this.mockToken.address
        );
        expect(weiToEther(balance2)).to.be.equal('9999');

        // now FantomMint contract should get 9999 wFTM
        const balance3 = await this.mockToken.balanceOf(
          this.fantomMint.address
        );
        expect(weiToEther(balance3)).to.be.equal('9999');
      });
    });
    describe('Mint fUSD', function () {
      it('should give a maxToMint (fUSD) value around 3333', async function () {
        const maxToMint = await this.fantomMint.maxToMint(
          borrower,
          this.fantomFUSD.address,
          30000
        );
        amountToMint = maxToMint;

        expect(maxToMint).to.be.bignumber.greaterThan('0');
        expect(weiToEther(maxToMint) * 1).to.be.lessThanOrEqual(3333);
      });

      it('should mint maximium (3333) amount of fUSD', async function () {
        // mint maximum amount possible of fUSD for borrower
        await this.fantomMint.mustMintMax(this.fantomFUSD.address, 30000, {
          from: borrower
        });

        const fUSDBalance = await this.fantomFUSD.balanceOf(borrower);
        totalSupply = weiToEther(await this.fantomFUSD.totalSupply());

        expect(weiToEther(fUSDBalance) * 1).to.be.lessThanOrEqual(3333);
      });
    });

    describe('Liquidation phase [Price goes down, liquidator gets the collateral]', function () {
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
          await this.fantomLiquidationManager.collateralIsEligible(borrower, this.mockToken.address);

        expect(isEligible).to.be.equal(false);

        let balance = await this.mockToken.balanceOf(liquidator);
      });

      it('should start liquidation and emit Repaid and Seized', async function () {
        await this.fantomFUSD.approve(
          this.fantomLiquidationManager.address,
          etherToWei(5000),
          { from: liquidator }
        );
          var result = await this.fantomLiquidationManager.liquidate(borrower, {from: liquidator});
          expectEvent(result, 'Repaid', {
              target: borrower,
              liquidator: liquidator,
              token: this.fantomFUSD.address,
              amount: amountToMint
            });
            expectEvent(result, 'Seized', {
              target: borrower,
              liquidator: liquidator,
              token: this.mockToken.address,
              amount: etherToWei('9999')
            });
      });

      it('the liquidator should have (10000 - 3333) 6667 fUSD remaining', async function () {
        let currentBalance = await this.fantomFUSD.balanceOf(liquidator);

        expect(weiToEther(currentBalance) * 1).to.lessThan(10000);
      });

      it('the liquidator should get the complete wFTM collateral (from the liquidation)', async function () {
        let balance = await this.mockToken.balanceOf(liquidator);
        expect(weiToEther(balance) * 1).to.equal(9999);
      });

      it('the collateral pool should have 0 balance remaining', async function () {
        let balance = await this.collateralPool.balanceOf(borrower, this.mockToken.address);
        expect(weiToEther(balance) * 1).to.equal(0);
      });
    });
  }
);