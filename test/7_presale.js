'use strict';
const truffleCost = require('truffle-cost');
const truffleAssert = require('truffle-assertions');
const BN = require('bn.js');
require('chai').use(require('chai-bn')(BN)).should();
const timeHelper = require("./helper/timeshift");


const Token = artifacts.require("iBNB");
const Presale = artifacts.require("iBNB_presale");
const routerContract = artifacts.require('IUniswapV2Router02');
const pairContract = artifacts.require('IUniswapV2Pair');
const routerAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

contract("Presale-contract", accounts => {
    const deployer = accounts[0];
    const WLbuying1BNB = accounts[1];
    const WLbuying2BNB = accounts[2];
    const NWLbuying1BNB = accounts[3];
    const NWLbuyingLowBNB = accounts[4];

    before(async function() {
        const x = await Token.new(routerAddress);
    });

    describe("Setting the Scene", () => {

        it("Token to presale contract", async () => {
            const t = await Token.deployed();
            const sale = await Presale.deployed();
            const tot_supp = await t.totalSupply.call();
            await t.setCircuitBreaker(true, {from: accounts[0]});
            await t.transfer(sale.address, tot_supp, {from: accounts[0]});
            const new_bal = await t.balanceOf.call(sale.address);
            new_bal.should.be.a.bignumber.that.equals(tot_supp);
        });

        it("Add to whitelist", async() => { 
            const WL = [WLbuying1BNB, WLbuying2BNB];
            const sale = await Presale.deployed();
            await truffleCost.log(sale.addWhitelist(WL, {from: deployer}));
            const res = await sale.isWhitelisted.call({from: WLbuying1BNB});
            assert.equal(res, true, "WL error");
        });

        it("Start presale", async () => {
            const sale = await Presale.deployed();
            await sale.startSale({from: deployer});
            const res = await sale.saleStatus();
            assert.equal(res, 1, "sale status error");
        });
    });



    describe("Presale", () => {

        it("Buy for 1BNB WL", async () => {
            const sale = await Presale.deployed();
            await truffleCost.log(sale.buy({from: WLbuying1BNB, value: '1'+'0'.repeat(18)}));
            const left = await sale.allowanceLeftInBNB({from: WLbuying1BNB});
            const bought = await sale.amountTokenBought({from: WLbuying1BNB}); //500000000000
            left.should.be.a.bignumber.that.equals(new BN('1'+'0'.repeat(18)));
            bought.should.be.a.bignumber.that.equals(new BN('500'+'0'.repeat(18)));
        });

        it("Buy for 2BNB WL", async () => {
            const sale = await Presale.deployed();
            await truffleCost.log(sale.buy({from: WLbuying2BNB, value: '2'+'0'.repeat(18)}));
            const left = await sale.allowanceLeftInBNB({from: WLbuying2BNB});
            const bought = await sale.amountTokenBought({from: WLbuying2BNB}); //2*500000000000
            left.should.be.a.bignumber.that.equals(new BN(0));
            bought.should.be.a.bignumber.that.equals(new BN('100'+'0'.repeat(19)));
        });

        it("Buy for 2+1BNB -> revert ?", async () => {
            const sale = await Presale.deployed();
            await truffleAssert.reverts(sale.buy({from: WLbuying2BNB, value: '1'+'0'.repeat(18)}), "Sale: above max amount");
        });

        it("Buy for 0.01BNB -> revert ?", async () => {
            const sale = await Presale.deployed();
            await truffleAssert.reverts(sale.buy({from: NWLbuyingLowBNB, value: '1'+'0'.repeat(17)}), "Sale: Under min amount");
        });

        it("Buy from non whitelisted 1BNB", async () => {
            const sale = await Presale.deployed();
            await truffleCost.log(sale.buy({from: NWLbuying1BNB, value: '1'+'0'.repeat(18)}));
            const left = await sale.allowanceLeftInBNB({from: NWLbuying1BNB});
            const bought = await sale.amountTokenBought({from: NWLbuying1BNB}); //2*500000000000
            left.should.be.a.bignumber.that.equals(new BN('1'+'0'.repeat(18)));
            bought.should.be.a.bignumber.that.equals(new BN('500'+'0'.repeat(18)));
        });
    
    });

    describe("closing sale", () => {

        it("Liquidity + closing", async () => {
            const t = await Token.deployed();
            const sale = await Presale.deployed();
            await truffleCost.log(sale.concludeAndAddLiquidity({from:deployer})); 
            const pairAdr = await t.pair.call();
            const pair = await pairContract.at(pairAdr);
            const LPBalance = await pair.balanceOf.call(deployer);
            LPBalance.should.not.be.zero;
        });

        it("Claim for 1BNB WL", async () => { 
            const sale = await Presale.deployed();
            await truffleCost.log(sale.claim({from: WLbuying1BNB}));
            const t = await Token.deployed();
            const res = await t.balanceOf(WLbuying1BNB);
            res.should.be.a.bignumber.that.equals(new BN('500'+'0'.repeat(18)));
        });

        it("Claim for 1BNB non WL", async () => { 
            const sale = await Presale.deployed();
            await sale.claim({from: NWLbuying1BNB});
            const t = await Token.deployed();
            const res = await t.balanceOf(NWLbuying1BNB);
            res.should.be.a.bignumber.that.equals(new BN('500'+'0'.repeat(18)));
        });

        it("Claim non claimable -> revert ?", async () => {
            const sale = await Presale.deployed();
            await truffleAssert.reverts(sale.claim({from: NWLbuyingLowBNB}), "0 tokens to claim");
        });

        it("Double claim -> revert ?", async () => {
            const sale = await Presale.deployed();
            await truffleAssert.reverts(sale.claim({from: WLbuying1BNB}), "0 tokens to claim");
        });

        it("Final closure", async () => {
            await timeHelper.advanceTimeAndBlock(604800);
            const sale = await Presale.deployed();
            await truffleCost.log(sale.finalClosure());
        });

    })

});