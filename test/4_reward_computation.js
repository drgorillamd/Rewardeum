'use strict';
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const time = require('./helper/timeshift');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const Token = artifacts.require("Rewardeum");
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
let x;
let router;
let WETH;

contract("Smartpool", accounts => {

  const to_send = 10**7;
  const amount_BNB = 98 * 10**18;
  const pool_balance = '98' + '0'.repeat(19);
  //98 BNB and 98*10**10 iBNB -> 10**10 iBNB/BNB

  let reserve;

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
    router = await routerContract.at(routerAddress);
    WETH = await router.WETH();
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
      const BNB_bal = _BNB_bal.divn(3);
      await x.smartpoolOverride(BNB_bal, {from: accounts[0]}); //33% reward - 66% reserve
      const SPBal = await x.smart_pool_balances.call();
      reserve = SPBal[1];
      SPBal[0].should.be.a.bignumber.that.equals(BNB_bal);
    });
  });

  describe("Indiv claim", () => {
    const anon = accounts[5];
    let amount_claimed;

    it("Buy from anon", async () => {
      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '1'+'0'.repeat(19);
      const res = await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, anon, 1907352278, {from: anon, value: val_bnb});
      const init_token = await x.balanceOf.call(anon);
      init_token.should.be.a.bignumber.that.is.not.null;
    });
    
    it("Init buffer at 0", async () => {
      const last_tx_before = await x.lastTxStatus.call(anon);
      assert.equal(last_tx_before[2], 0, "wrong buffer");
    });

    it("Buffer update after buy", async () => {
      const init_token = await x.balanceOf.call(anon);

      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '1'+'0'.repeat(19);
      const res = await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, anon, 1907352278, {from: anon, value: val_bnb});
      const end_token = await x.balanceOf.call(anon);
      const last_tx = await x.lastTxStatus.call(anon);
      last_tx[2].should.be.a.bignumber.that.equals(end_token.sub(init_token));
    });

    it("SP: reserve", async () => {
      const SPBal = await x.smart_pool_balances.call();
      console.log("reward BNB : "+SPBal[0].toString());
      console.log("reserve BNB : "+SPBal[1].toString());
      console.log("prev reward BNB : "+SPBal[2].toString());
      console.log("reserve token : "+SPBal[3].toString());
    });

    it("Quote at +24h", async () => {
      await time.advanceTimeAndBlock(86401);
      const claimable = await x.computeReward.call({from: anon});
      console.log("claimable : " + claimable[0]);
      let ticker;
      let res;
      for(let i=0; i<7; i++){
        ticker = await x.tickers_claimable.call(i);
        res = await x.getQuote.call(claimable[0], ticker)
        console.log(ticker+" : "+res.toString());
      }
    })

    it("Claim at +24h", async () => {
      const bal_before = new BN(await web3.eth.getBalance(anon));
      const claimable = await x.computeReward.call({from: anon});
      await truffleCost.log(x.claimReward('WBNB', {from: anon}));
      reserve = reserve.add(claimable[1]);
      const bal_after = new BN(await web3.eth.getBalance(anon));
      amount_claimed = bal_after.sub(bal_before);
      bal_after.should.be.a.bignumber.greaterThan(bal_before);
    });

    it("SP: reserve", async () => {
      const SPBal = await x.smart_pool_balances.call();
      console.log("reward BNB : "+SPBal[0].toString());
      console.log("reserve BNB : "+SPBal[1].toString());
      console.log("prev reward BNB : "+SPBal[2].toString());
      console.log("reserve token : "+SPBal[3].toString());
    });

    it("Buffer after claim", async () => {
      const last_tx_before = await x.lastTxStatus.call(anon);
      assert.equal(last_tx_before[2], 0, "wrong buffer");
      console.log("cum sell "+last_tx_before[0]);
      console.log("last_sell "+last_tx_before[1]);
      console.log("reward_buffer "+last_tx_before[2]);
      console.log("last_claim "+last_tx_before[3]);
      console.log("balance token "+await x.balanceOf.call(anon));

    });

    it("Claim at +22+24h", async () => {
      await time.advanceTimeAndBlock(86410);
      const bal_before = new BN(await web3.eth.getBalance(anon));
      const claimable = await x.computeReward.call({from: anon});
      await x.claimReward('WBNB', {from: anon});
      const bal_after = new BN(await web3.eth.getBalance(anon));
      bal_after.should.be.a.bignumber.greaterThan(bal_before);
      const new_amount_claimed = bal_after.sub(bal_before);
      new_amount_claimed.should.be.a .bignumber.greaterThan(amount_claimed);
    });

    it("SP: reserve", async () => {
      const SPBal = await x.smart_pool_balances.call();
      console.log("reward BNB : "+SPBal[0].toString());
      console.log("reserve BNB : "+SPBal[1].toString());
      console.log("prev reward BNB : "+SPBal[2].toString());
      console.log("reserve token : "+SPBal[3].toString());
    });

  });

});
