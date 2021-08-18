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
    n = await nft.deployed();
    router = await routerContract.at(routerAddress);
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
      const val_bnb = '1'+'0'.repeat(19);
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

    it("NFT transfer", async () => {
      await n.safeTransferFrom(accounts[0], v.address, 1, {from: accounts[0]});
      const new_owner = await n.ownerOf.call(1);
      assert.equal(new_owner, v.address, "transfer error");
    });

    it("reum transfer", async () => {
      const to_send = '1'+'0'.repeat(14);
      await x.transfer(v.address, to_send, {from: accounts[0]});
      const new_bal = await x.balanceOf.call(v.address);
      assert.equal(to_send, new_bal.toString(), "transfer error");
    })
  });

  describe("Adding bonus to claim", () => {
    it("Adding reum in bonus list", async () => {
      const reum = web3.utils.asciiToHex("REUM");
      await x.addClaimable(v.address, reum, 85, {from: accounts[0]});
      await x.addCombinedOffer(x.address, reum, {from: accounts[0]});
      const new_adr = await x.available_tokens.call(reum);
      const new_combined = await x.combined_offer.call(reum);
      assert.equal(new_adr, v.address);
      assert.equal(new_combined, x.address);
    })

    it("Adding NFT_TEST in bonus list", async () => {
      const nft_test = web3.utils.asciiToHex("NFT_TEST") 
      await x.addClaimable(v.address, nft_test, 0, {from: accounts[0]});
      const new_adr = await x.available_tokens.call(nft_test);
      assert.equal(new_adr, v.address);
    })
  });

  describe("Claim from vault", () => {

    it("claim directly from vault -> revert ?", async () => {
      await time.advanceTimeAndBlock(87000);
      const reum = web3.utils.asciiToHex("REUM");
      await truffleAssert.reverts(v.claim('10000', anon, reum, {from: anon}), "Vault: unauthorized access");
    })

    it("Claiming Reum", async () => {
      await time.advanceTimeAndBlock(87000);
      const reum = web3.utils.asciiToHex("REUM");
      const claimable_reward = await x.computeReward.call({from: anon});
      console.log("claimable : "+claimable_reward[0]);

      //gas waiver!
      //const get_taxOnClaim = ( ((claimable_reward[0].pow(new BN('2'))).mul(new BN('2'))).add(claimable_reward[0].mul(new BN('3'))) ).divn(new BN('100'));

      const get_quote = await x.getQuote.call(claimable_reward[0], reum);
      const bal_before = await x.balanceOf.call(anon);
      const vault_bal = await x.balanceOf.call(v.address);
      await truffleCost.log(x.claimReward(reum, {from: anon}));
      const bal_after = await x.balanceOf.call(anon);
      bal_after.should.be.a.bignumber.that.is.closeTo(bal_before.add(vault_bal).add(get_quote), '1000000');
    })

    it("Claim NFT_TEST", async () => {
      const nft_test = web3.utils.asciiToHex("NFT_TEST");
      await v.addAsset(nft_test, n.address, {from: accounts[0]});
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(nft_test, {from: anon}));
      const new_owner = await n.ownerOf.call(1);
      assert.equal(new_owner, anon, "NFT Claim error")
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
      const quote = await x.getQuote.call('1'+'0'.repeat(18), web3.utils.asciiToHex("BTCB"));
      await truffleCost.log(x.claimReward(web3.utils.asciiToHex('BTCB'), {from: anon}));
    });
  
  });
});
