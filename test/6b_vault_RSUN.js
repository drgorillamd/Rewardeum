const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const time = require('./helper/timeshift');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const vault = artifacts.require('Vault_01');
const nft = artifacts.require('REUM_ticket');
const Token = artifacts.require("Rewardeum");
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const IERC20 = artifacts.require('IERC20');

const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const RSUNAddress = "0x917841c010b3d86ED886F36F2C9807E07a2e3093";

let x;
let router;
let WETH;
let IRSUN;


contract("Vault.sol", accounts => {

  const amount_BNB = 98 * 10**18;
  const pool_balance = '98' + '0'.repeat(19);
  //98 BNB and 98*10**10 iBNB -> 10**10 iBNB/BNB
  const anon = accounts[5];

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
    await vault.new(x.address);
    v = await vault.deployed();
    const nft_address = await v.ticket_contract.call();
    n = await nft.at(nft_address);
    router = await routerContract.at(routerAddress);
    IRSUN = await IERC20.at(RSUNAddress);
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
      SPBal[0].should.be.a.bignumber.that.equals(BNB_bal);
    });

    it("Buy from anon", async () => {
      const route_buy = [await router.WETH(), x.address]
      const val_bnb = '5'+'0'.repeat(19);
      const res = await router.swapExactETHForTokensSupportingFeeOnTransferTokens(0, route_buy, anon, 1907352278, {from: anon, value: val_bnb});
      const init_token = await x.balanceOf.call(anon);
      init_token.should.be.a.bignumber.that.is.not.null;
    });
  });

  describe("Setting up vault", () => {
    it("set new vault", async () => {
      await x.setVault(v.address, {from: accounts[0]});
      const vault_adr = await x.main_vault.call();
      assert.equal(v.address, vault_adr);
    });
    
    it("excludeFromTaxes(vault)", async () => {
      await x.excludeFromTaxes(v.address, {from: accounts[0]});
      const excluded = await x.isExcluded.call(v.address);
      assert.isTrue(excluded);
    });

  });

  describe("Adding bonus to claim", () => {
    it("Adding rsun in bonus list", async () => {
      const rsun = web3.utils.asciiToHex("RSUN");
      await x.addCombinedOffer(RSUNAddress, rsun, 87, {from: accounts[0]});
      const new_adr = await x.available_tokens.call(rsun);
      const new_combined = await x.combined_offer.call(rsun);
      assert.equal(new_adr, v.address);
      assert.equal(new_combined, RSUNAddress);
    })

    it("Validate tickers", async () => {
      const res = await x.validateCustomTickers.call();
      assert.equal(res, "Validate: passed");
    })
  });

  describe("Claim from vault", () => {

    let claimable_reward;

    it("claim directly from vault -> revert ?", async () => {
      await time.advanceTimeAndBlock(87000);
      const rsun = web3.utils.asciiToHex("RSUN");
      await truffleAssert.reverts(v.claim('10000', anon, rsun, {from: anon}), "Vault: unauthorized access");
    })

    it("Claiming RSUN", async () => {
      await time.advanceTimeAndBlock(87000);
      const rsun = web3.utils.asciiToHex("RSUN");
      claimable_reward = await x.computeReward.call({from: anon});
      console.log("claimable : "+claimable_reward[0]);
      const get_quote = await x.getQuote.call(rsun);
      console.log("quote : "+get_quote[0].toString()+" decimals : "+get_quote[1].toString());
      const bal_before = await IRSUN.balanceOf(anon);
      await truffleCost.log(x.claimReward(rsun, {from: anon}));
      const bal_after =  await IRSUN.balanceOf(anon);
      bal_after.should.be.a.bignumber.that.is.greaterThan(bal_before);
    })
    it("NFT Received?", async () => {
      const owner = await n.ownerOf.call(1);
      assert.equal(owner, anon, "NFT Claim error");
    })
    it("Number of NFT ?", async () => {
      const nft_owned = await n.balanceOf.call(anon);
      const actual_price = claimable_reward[0] / nft_owned;
      const theo_price = await v.ticket_price.call();
      console.log("NFT owned "+nft_owned.toString());
      console.log("actual price "+actual_price.toString());
      console.log("theo price "+theo_price.toString());
      //actual_price.should.be.a.bignumber.that.equals(theo_price);
    })
    it("Control: Claim BNB at 87000 sec", async () => {
      const balance_before = new BN(await web3.eth.getBalance(anon));
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('WBNB'), {from: anon}));
      const balance_after = new BN(await web3.eth.getBalance(anon));
      balance_after.should.be.a.bignumber.that.is.greaterThan(balance_before);
    });
    it("Control: Claim BTCB after 87000", async () => { 
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('BTCB'), {from: anon}));
    });
  });

  describe("Removing bonus to claim", () => {
    it("Removing RSUN as non-combined -> revert ?", async () => {
      await time.advanceTimeAndBlock(87000);
      const reum = web3.utils.asciiToHex("RSUN");
      await truffleAssert.reverts(x.removeClaimable(reum, {from: accounts[0]}), "Combined Offer");
    });

    it("Removing RSUN as combined -> no more claim ?", async () => {
      await time.advanceTimeAndBlock(87000);
      const reum = web3.utils.asciiToHex("RSUN");
      await x.removeCombinedOffer(reum, {from: accounts[0]});
      await truffleAssert.reverts(x.claimReward(reum, {from: anon}), "Claim: invalid dest token");
    });
  });

});
