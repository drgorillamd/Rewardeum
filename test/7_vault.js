const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const time = require('./helper/timeshift');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const vault = artifacts.require('Vault');
const nft = artifacts.require('vault_test_NFT');
const Token = artifacts.require("Rewardeum");
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const IERC20 = artifacts.require('IERC20');

const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

let x;
let router;
let WETH;
let IBUSD;


contract("LP and taxes", accounts => {

  const anon = accounts[5];

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
    await vault.new(x.address);
    v = await vault.deployed();
    n = await nft.deployed();
    router = await routerContract.at(routerAddress);
  });

  describe("Setting the Scene", () => {
    it("Adding Liq", async () => { //from 2_liqAdd & Taxes
      await x.setCircuitBreaker(true, {from: accounts[0]});
      const amount_token = '1'+'0'.repeat(23);
      const amount_BNB = '4'+'0'.repeat(18);

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
      SPBal[0].should.be.a.bignumber.that.equals(BNB_bal);
    });

    it("Buy from anon + move in time", async () => {
      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '1'+'0'.repeat(19);
      await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, anon, 1907352278, {from: anon, value: val_bnb});
      const init_token = await x.balanceOf.call(anon);
      await time.advanceTimeAndBlock(87000);
      init_token.should.be.a.bignumber.that.is.not.null;
    });
  });

  describe("Vault trsnfer in", () => {
    it("NFT transfer", async () => {
      await n.safeTransferFrom(accounts[0], v.address, 1, {from: accounts[0]});
      const new_owner = await n.ownerOf.call(1);
      assert.equal(new_owner, v.address, "transfer error");
    });

    it("reum transfer", async () => {
      const to_send = '1'+'0'.repeat(14);
      await x.transfer(v.address, to_send, { from: accounts[0] });
      const new_bal = await x.balanceOf.call(v.address);
      assert.equal(to_send, new_bal.toString(), "transfer error");
    })
  });

});
