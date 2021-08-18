'use strict';
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const time = require('./helper/timeshift');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const Token = artifacts.require("Rewardeum");
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const IERC20 = artifacts.require('IERC20');
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const DOT = "0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402";


let x;
let router;
let WETH;
let IBUSD;
let ICAKE;
let IDOT;

contract("Reward Claim", accounts => {

  const amount_BNB = 98 * 10**18;
  const pool_balance = '98' + '0'.repeat(19);
  //98 BNB and 98*10**10 reum -> 10**10 reum/BNB
  const anon = accounts[5];


  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
    router = await routerContract.at(routerAddress);
    WETH = await router.WETH();
    IBUSD = await IERC20.at(BUSD);
    ICAKE = await IERC20.at(CAKE);
    IDOT = await IERC20.at(DOT);
  });

  describe("Setting the Scene", () => {
    it("Adding Liq", async () => { //from 2_liqAdd & Taxes
      await x.setCircuitBreaker(true, {from: accounts[0]});
      const status_circ_break = await x.circuit_breaker.call();
      const router = await routerContract.at(routerAddress);
      const amount_token = pool_balance;
      const sender = accounts[0];

      let _ = await x.approve(routerAddress, amount_token);
      await router.addLiquidityETH(x.address, amount_token, 0, 0, accounts[0], 1907352278, {value: amount_BNB}); //9y from now. Are you from the future? Did we make it?

      const pairAdr = await x.pair.call();
      const pair = await pairContract.at(pairAdr);
      const LPBalance = await pair.balanceOf.call(accounts[0]);

      await x.setCircuitBreaker(false, {from: accounts[0]});

      assert.notEqual(LPBalance, 0, "No LP token received / check Uni pool");
    });

    it("Sending BNB to contract", async () => { 
      await web3.eth.sendTransaction({from: accounts[9], to: x.address, value:'9'+'0'.repeat(19)})
      const bal = await web3.eth.getBalance(x.address);
      assert.equal(bal, '9'+'0'.repeat(19), "incorrect balance");
    });

    it("smartpool Override", async () => {
      const _BNB_bal = new BN(await web3.eth.getBalance(x.address));
      const BNB_bal = _BNB_bal.sub(new BN(10));
      await x.smartpoolOverride(BNB_bal, {from: accounts[0]}); //100% reward
      const SPBal = await x.smart_pool_balances.call();
      SPBal[0].should.be.a.bignumber.that.equals(BNB_bal);
    });

    it("Buy from anon", async () => {
      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '1'+'0'.repeat(19);
      const res = await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, anon, 1907352278, {from: anon, value: val_bnb});
      const init_token = await x.balanceOf.call(anon);
      console.log("Init balance : "+init_token.toString());
      init_token.should.be.a.bignumber.that.is.not.null;
    });
  });

  describe("Claim", () => {

    it("Claim BNB at 87000 sec", async () => {
      await time.advanceTimeAndBlock(87000);
      const balance_before = new BN(await web3.eth.getBalance(anon));
      const bal_contract = await web3.eth.getBalance(x.address);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('WBNB'), {from: anon}));
      const balance_after = new BN(await web3.eth.getBalance(anon));
      console.log("Effectively claimed (-gas) : "+(balance_after.sub(balance_before)).toString());
      balance_after.should.be.a.bignumber.that.is.greaterThan(balance_before);
    });

    it("Double claim: revert", async () => { //
      const balance_before = await web3.eth.getBalance(x.address);
      await truffleAssert.reverts(x.claimReward(web3.utils.asciiToHex('WBNB'), {from: anon}), "Claim: 0");
    });

  });

  describe("Custom claim", () => {
    it("Claim BUSD after 87000", async () => { 
      const balance_before = await IBUSD.balanceOf(anon);
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('BUSD'), {from: anon}));
      const balance_after = await IBUSD.balanceOf(anon);
      console.log("Effectively claimed : "+(balance_after.sub(balance_before)).toString());
      balance_after.should.be.a.bignumber.greaterThan(balance_before);
    });

    it("Claim REUM after 87000", async () => { 
      const balance_before = await x.balanceOf.call(anon);
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('REUM'), {from: anon}));
      const balance_after = await x.balanceOf.call(anon);
      console.log("Effectively claimed : "+(balance_after.sub(balance_before)).toString());
      balance_after.should.be.a.bignumber.greaterThan(balance_before);
    });

    it("Claim Cake after 87000", async () => { 
      const balance_before = await ICAKE.balanceOf(anon);
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('Cake'), {from: anon}));
      const balance_after = await ICAKE.balanceOf(anon);
      console.log("Effectively claimed : "+(balance_after.sub(balance_before)).toString());
      balance_after.should.be.a.bignumber.greaterThan(balance_before);
    });

    it("Claim DOT after 87000", async () => { 
      const balance_before = await IDOT.balanceOf(anon);
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('DOT'), {from: anon}));
      const balance_after = await IDOT.balanceOf(anon);
      console.log("Effectively claimed : "+(balance_after.sub(balance_before)).toString());
      balance_after.should.be.a.bignumber.greaterThan(balance_before);
    });

    it("Validate tickers", async () => {
      const res = await x.validateCustomTickers.call();
      assert.equal(res, "Validate: passed");
    })
  });
});
