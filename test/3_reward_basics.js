'use strict';
const Token = artifacts.require("projectX");
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

//const chai = require('chai');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

let x;

const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

contract("Reward", accounts => {

  const to_send = 10**7;
  const amount_BNB = 98 * 10**18;
  const pool_balance = '98' + '0'.repeat(19);
  //98 BNB and 98*10**10 iBNB -> 10**10 iBNB/BNB

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
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

  });

  //tricking the balancer to trigger a swap
  describe("Balancer setting", () => {

    it("Transfer to contract > 2 * swap for reward threshold -100", async () => {
      await x.transfer(x.address, (2*10**9)-100, { from: accounts[0] });
      const newBal = await x.balanceOf.call(x.address);
      const expected = new BN((2*10**9)-100);
      newBal.should.be.a.bignumber.that.equals(expected);
    });

    it("Reset balancer", async () => {
      await truffleAssert.passes(x.resetBalancer({from: accounts[0]}), "balancer reset failed");
    });

  });

  describe("Reward Mechanics: Smartpool", () => {

    it("Smart pool balances", async () => {
      const SPBal = await x.smart_pool_balances.call();
      const BNB_bal = await web3.eth.getBalance(x.address); 
      assert.equal(SPBal[0], BNB_bal, "SP: non valid balances");
    });

    it("smartpoolOverride", async () => {
      const _BNB_bal = new BN(await web3.eth.getBalance(x.address));
      const BNB_bal = _BNB_bal.divn(3);
      await x.smartpoolOverride(BNB_bal, {from: accounts[0]}); //33% reward - 66% reserve
      const SPBal = await x.smart_pool_balances.call();
      SPBal[0].should.be.a.bignumber.that.equals(BNB_bal);
    });

  });

});
