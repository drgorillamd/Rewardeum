const Token = artifacts.require("projectX");
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

let x;

contract("Basic tests", accounts => {

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
  });

  describe("Init state", () => {
    it("Initialized - return proper name()", async () => {
      const obs_name = await x.name();
      assert.equal(obs_name, "ProjectX", "incorrect name returned")
    });

    it("deployer = owner", async () => {
      const owned_by = await x.owner.call();
      assert.equal(accounts[0], owned_by, "Owner is not account[0]");
    });

    it("tot supply in owner", async () => {
      const bal = await x.balanceOf.call(accounts[0]);
      const theo = await x.totalSupply.call();
      bal.should.be.a.bignumber.that.equals(theo);
    });
  });

  describe("Circuit breaker test", () => {
    it("Circuit Breaker: Enabled", async () => {
      await truffleCost.log(x.setCircuitBreaker(true, {from: accounts[0]}), 'USD');
      const status_circ_break = await x.circuit_breaker.call();
      assert.equal(true, status_circ_break, "Circuit breaker not set");
    });

    it("Circuit breaker: transfer from owner/exempted", async () => {
      const to_send = 10**6;
      const to_receive = 10**6;
      const sender = accounts[0];
      const receiver = accounts[1];
      await truffleCost.log(x.transfer(receiver, to_send, { from: sender }), 'USD');
      const newBal = await x.balanceOf.call(receiver);
      assert.equal(newBal.toNumber(), to_receive, "incorrect amount transfered");
    });

    it("Circuit breaker: transfer standard", async () => {
      const to_send = 10**6;
      const to_receive = 10**6;
      const sender = accounts[1];
      const receiver = accounts[2];
      await truffleCost.log(x.transfer(receiver, to_send, { from: sender }), 'USD');
      const newBal = await x.balanceOf.call(receiver);
      assert.equal(newBal.toNumber(), to_receive, "incorrect amount transfered");
    });

    it("Circuit Breaker: Disabled", async () => {
      await x.setCircuitBreaker(false, {from: accounts[0]});
      const status_circ_break = await x.circuit_breaker.call();
      assert.equal(false, status_circ_break, "Circuit breaker not set");
    });

    it("Circuit Breaker: Unauthorized", async () => {
      await truffleAssert.reverts(x.setCircuitBreaker(true, {from: accounts[1]}), "Ownable: caller is not the owner.");
    });
  });
});
