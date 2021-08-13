'use strict';
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();
const timeHelper = require("./helper/timeshift");
const fs = require('fs');
const airdrops = require("../data/test_airdrop.json")


const Token = artifacts.require("Rewardeum");
const Airdrp = artifacts.require("Reum_airdrop");
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";



contract("Presale-contract", accounts => {
    const owner = accounts[0];

    var addresses = [];
    var balances = [];

    for(let i=0; i < airdrops.listing.length; i++) {
      addresses[i] = airdrops.listing[i].adr;
      balances[i] = airdrops.listing[i].bal;
    }
    

    before(async function() {
        const x = await Token.new(routerAddress);
        const y = await Airdrp.new(x.address);
    });

    describe("Airdrop", () => {

        it("Approve", async() => {
            const t = await Token.deployed();
            const a = await Airdrp.deployed();
            const result = await t.approve(a.address, '5'+'0'.repeat(26), {from: owner});

            truffleAssert.eventEmitted(result, 'Approval');
        })

        it("Send", async() => {
            const i = 5;
            const t = await Token.deployed();
            const a = await Airdrp.deployed();
            console.log("number of addresses: "+addresses.length);
            await truffleCost.log(a.send_airdrop(owner, addresses, balances, {from: owner}));
            const new_bal = await t.balanceOf.call(addresses[i]);
            
            new_bal.should.be.a.bignumber.not.null;
        });

    });

});