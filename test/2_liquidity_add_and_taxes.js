const Token = artifacts.require("Rewardeum");
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();
let x;

contract("LP and taxes", accounts => {

  const pool_balance = '1'+'0'.repeat(23); // 10%

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
  });

  describe("Adding Liq", () => {
    it("Circuit Breaker: Enabled", async () => {
      await x.setCircuitBreaker(true, {from: accounts[0]});
      const status_circ_break = await x.circuit_breaker.call();
      assert.equal(true, status_circ_break, "Circuit breaker not set");
    });

    it("Router testing", async () => {
      const router = await routerContract.at(routerAddress);
      assert.notEqual(0, await router.WETH.call(), "router down");
    });

    it("Adding liquidity: 10^8 token & 4BNB", async () => {
      const amount_BNB = '4'+'0'.repeat(18);
      const amount_token = pool_balance;
      const sender = accounts[0];

      const router = await routerContract.at(routerAddress);
      let _ = await x.approve(routerAddress, amount_token);
      await router.addLiquidityETH(x.address, amount_token, 0, 0, sender, 1907352278, {value: amount_BNB}); //9y from now. Are you from the future? Did we make it?

      const pairAdr = await x.pair.call();
      const pair = await pairContract.at(pairAdr);
      const token_bal = await x.balanceOf(pairAdr); //not bnb since it's wbnb and lazy to compile wbnb
      const LPBalance = await pair.balanceOf.call(sender);

      LPBalance.should.be.a.bignumber.that.is.not.null;
      token_bal.should.be.a.bignumber.that.equals(new BN(amount_token));
    });

    it("Circuit Breaker: Disabled", async () => {
      await x.setCircuitBreaker(false, {from: accounts[0]});
      const status_circ_break = await x.circuit_breaker.call();
      assert.equal(false, status_circ_break, "Circuit breaker not set");
    });
  });

  describe("Regular transfers", () => {

    it("Transfer standard: single -- 1m : 17% + triggers LP", async () => {
      const to_send = '1'+'0'.repeat(21); //0.1%pool
      const to_receive = '850000000000000000000'; // 15% taxes
      const sender = accounts[1];
      const receiver = accounts[2];
      await x.transfer(sender, to_send, { from: accounts[0] });
      await truffleCost.log(x.transfer(receiver, to_send, { from: sender }));
      const newBal = await x.balanceOf.call(receiver);
      newBal.should.be.a.bignumber.that.equals(to_receive);
    });

  });

  describe("swap - tax on selling", () => {

    it("Buy + Sell", async () => {
      const router = await routerContract.at(routerAddress);
      const seller = accounts[5];
      const route_sell = [x.address, await router.WETH()]
      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '1'+'0'.repeat(15);

      const res = await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, seller, 1907352278, {from: seller, value: val_bnb});
      const init_bal = await web3.eth.getBalance(seller);
      const init_token = await x.balanceOf.call(seller);

      let _ = await x.approve(routerAddress, init_token+1, {from: seller});
      const res2 = await truffleCost.log(router.swapExactTokensForETHSupportingFeeOnTransferTokens(init_token, 0, route_sell, seller, 1907352278, {from: seller}));
      const end_bal = await web3.eth.getBalance(seller);

      end_bal.should.be.a.bignumber.lessThan(init_bal);
    });

  });
});
