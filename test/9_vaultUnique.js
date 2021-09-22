const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const time = require('./helper/timeshift');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const vault = artifacts.require('VaultLast');
const Token = artifacts.require("Rewardeum");
const GenTicket = artifacts.require('REUMGenericTicket');
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const IERC20 = artifacts.require('IERC20');

const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

let x;
let router;
let n;
let v;
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
      await web3.eth.sendTransaction({from: accounts[8], to: x.address, value:'9'+'0'.repeat(19)})
      const bal = await web3.eth.getBalance(x.address);
      assert.equal(bal, '18'+'0'.repeat(19), "incorrect balance");
    });

    it("smartpool Override", async () => {
      const _BNB_bal = new BN(await web3.eth.getBalance(x.address));
      const BNB_bal = _BNB_bal.divn(2);
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
  });

  describe("Adding new lottery", () => {
    it("Removing Reum from standard + add in combined offers", async () => {
      const reum = web3.utils.asciiToHex("REUM");
      await x.removeClaimable(reum, {from: accounts[0]});
      await x.addCombinedOffer(x.address, reum, 85, {from: accounts[0]});
      const new_adr = await x.available_tokens.call(reum);
      const new_combined = await x.combined_offer.call(reum);
      assert.equal(new_adr, v.address);
      assert.equal(new_combined, x.address);
    })

    it("Creating Reum ticket contract", async () => {
      await v.newLottery(web3.utils.asciiToHex("REUM"), 2, Date.now()+100, 10, "TEST");
      const child = await v.active_contracts.call(web3.utils.asciiToHex("REUM"));
      n = await GenTicket.at(child);
      console.log(await n.symbol.call());
      console.log(await n.name.call());
      assert.notEqual(child, '0');
    })

  });

  describe("Claim from vault", () => {

    it("claim directly from vault -> revert ?", async () => {
      await time.advanceTimeAndBlock(87000);
      const reum = web3.utils.asciiToHex("REUM");
      await truffleAssert.reverts(v.claim('10000', anon, reum, {from: anon}), "Vault: unauthorized access");
    })

    it("Claim Reum + ticket", async () => {
      const nft_test = web3.utils.asciiToHex("REUM");
      await time.advanceTimeAndBlock(87000);
      await truffleCost.log(x.claimReward(nft_test, {from: anon}));
      const new_owner = await n.ownerOf.call(1);
      console.log(await n.tokenURI.call(1));
      assert.equal(new_owner, anon, "NFT Claim error")
    })

  });

});
