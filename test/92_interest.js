const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var DAO = artifacts.require('./DAO')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var RESERVE = artifacts.require('./Reserve')
var VAULT = artifacts.require('./Vault')
var Pools = artifacts.require('./Pools')
var Router = artifacts.require('./Router')
var Lender = artifacts.require('./Lender')
var Factory = artifacts.require('./Factory')
var Synth = artifacts.require('./Synth')

var Asset = artifacts.require('./Token1')
var Anchor = artifacts.require('./Token2')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

async function mine() {
  await ethers.provider.send('evm_mine')
}

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

var utils;
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var factory; var router; var lender;
var anchor0; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
const one = 10**18

before(async function() {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()

  dao = await DAO.new();
  vether = await Vether.new();
  vader = await Vader.new();
  utils = await Utils.new(vader.address);
  usdv = await USDV.new(vader.address);
  reserve = await RESERVE.new();
  vault = await VAULT.new(vader.address);
  router = await Router.new(vader.address);
  lender = await Lender.new(vader.address);
  pools = await Pools.new(vader.address);
  factory = await Factory.new(pools.address);
})

describe("Deploy Interest", function() {
  it("Should deploy", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)

    asset = await Asset.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, '9409')
    await anchor.transfer(acc1, '2000')

    await vader.approve(usdv.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc1})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})
    await anchor.approve(router.address, max, {from:acc1})
    await asset.approve(router.address, max, {from:acc1})

    await vader.upgrade('10', {from:acc1})
    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await vader.convertToUSDV('5000', {from:acc1})

    await asset.transfer(acc1, '2000')

    await vader.transfer(router.address, '1000', {from:acc1})
    await usdv.transfer(router.address, '1000', {from:acc1})
  });
});

describe("Add liquidity", function() {
  it("Should add anchor", async function() {
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})
  });
});

describe("Should Borrow Debt", function() {
  it("Borrow", async function() {
    await vader.approve(lender.address, max, {from:acc1})
    await usdv.approve(lender.address, max, {from:acc1})
    await lender.borrow('100', vader.address, anchor.address, {from:acc1})
    await lender.borrow('100', usdv.address, asset.address, {from:acc1})
    await pools.deploySynth(asset.address)
    await router.swapWithSynths('250', usdv.address, false, asset.address, true, {from:acc1})
    let synth = await Synth.at(await factory.getSynth(asset.address));
    await synth.approve(lender.address, max, {from:acc1})
    await lender.borrow('144', synth.address, asset.address, {from:acc1})
  });

});

describe("Should pay interest", function() {
    it("Pay VADER-ANCHOR interest", async function() {
      expect(BN2Str(await utils.getDebtLoading(vader.address, anchor.address))).to.equal('615');
      expect(BN2Str(await utils.getInterestPayment(vader.address, anchor.address))).to.equal('3');
      expect(BN2Str(await utils.calcValueInBase(anchor.address, '3'))).to.equal('3');
      expect(BN2Str(await utils.getInterestOwed(vader.address, anchor.address, '31536000'))).to.equal('3');

      expect(BN2Str(await lender.getSystemInterestPaid(vader.address, anchor.address))).to.equal('3');
      expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal('1069');
    });

});

