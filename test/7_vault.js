const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();

const vault = artifacts.require('Vault');
const nft = artifacts.require('vault_test_NFT');
const Token = artifacts.require("Rewardeum");


const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

let x;

contract("LP and taxes", accounts => {

  const pool_balance = '1'+'0'.repeat(23); // 10%

  before(async function() {
    await Token.new(routerAddress);
    x = await Token.deployed();
    await vault.new(x.address);
    v = await vault.deployed();
    n = await nft.deployed();
  });

  describe("Vault trsnfer in", () => {
    it("NFT transfer", async () => {
      await n.safeTransferFrom(accounts[0], v.address, 1, {from: accounts[0]});
      const new_owner = await n.ownerOf.call(1);
      assert.equal(new_owner, v.address, "transfer error");
    });

  });

});
