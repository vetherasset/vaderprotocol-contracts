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
var reserve; var vault; var pools; var anchor; var factory; var router;
var asset; var asset2; var asset3;
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

describe("Deploy Router", function() {
  it("Should deploy", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)

    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())

    asset = await Asset.new();
    asset2 = await Asset.new();
    asset3 = await Asset.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, BN2Str(7407))
    await anchor.transfer(acc1, BN2Str(2000))

    await vader.approve(usdv.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc1})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})
    await anchor.approve(router.address, max, {from:acc1})

    await vader.upgrade('7', {from:acc1})

    await asset.transfer(acc1, BN2Str(2000))
    await asset.approve(router.address, BN2Str(one), {from:acc1})
    await asset2.transfer(acc1, BN2Str(2000))
    await asset2.approve(router.address, BN2Str(one), {from:acc1})
    await asset3.transfer(acc1, BN2Str(2000))
    await asset3.approve(router.address, BN2Str(one), {from:acc1})

    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await vader.convertToUSDV(3000, {from:acc1})
    await usdv.transfer(acc0, '1', {from:acc1})
    await usdv.transfer(acc1, '1', {from:acc0})

    expect(await vader.DAO()).to.equal(dao.address);
    expect(await dao.UTILS()).to.equal(utils.address);
    expect(await router.VADER()).to.equal(vader.address);
    expect(await dao.USDV()).to.equal(usdv.address);

    // expect(Number(await vader.getDailyEmission())).to.be.greaterThan(0);
    // expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
    // expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
    // expect(Number(await reserve.reserveVADER())).to.be.greaterThan(0);
  });
});

describe("Add liquidity", function() {
  it("Should add anchor", async function() {
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
    expect(BN2Str(await pools.getUnits(anchor.address))).to.equal('1000');
    expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await pools.getTokenAmount(anchor.address))).to.equal('1000');
    expect(BN2Str(await pools.getMemberUnits(anchor.address, acc1))).to.equal('1000');
  });
  it("Should add asset", async function() {
    let tx = await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})
    expect(BN2Str(await pools.mapToken_Units(asset.address))).to.equal('1000');
    expect(BN2Str(await pools.mapToken_baseAmount(asset.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await pools.mapToken_tokenAmount(asset.address))).to.equal('1000');
    expect(BN2Str(await pools.mapTokenMember_Units(asset.address, acc1))).to.equal('1000');
  });
  it("Should add asset2", async function() {
    let tx = await router.addLiquidity(usdv.address, '999', asset2.address, '999', {from:acc1})
    expect(BN2Str(await pools.mapToken_Units(asset2.address))).to.equal('999');
    expect(BN2Str(await pools.mapToken_baseAmount(asset2.address))).to.equal('999');
    expect(BN2Str(await pools.mapToken_tokenAmount(asset2.address))).to.equal('999');
    expect(BN2Str(await pools.mapTokenMember_Units(asset2.address, acc1))).to.equal('999');
  });
  it("Should add asset3", async function() {
    await router.addLiquidity(usdv.address, '999', asset3.address, '999', {from:acc1})
    expect(BN2Str(await pools.mapToken_Units(asset3.address))).to.equal('999');
    expect(BN2Str(await pools.mapToken_baseAmount(asset3.address))).to.equal('999');
    expect(BN2Str(await pools.mapToken_tokenAmount(asset3.address))).to.equal('999');
    expect(BN2Str(await pools.mapTokenMember_Units(asset3.address, acc1))).to.equal('999');
  });
});

describe("Should Curate", function() {
  it("Curate first pool", async function() {
    expect(await pools.isAsset(asset.address)).to.equal(true);
    expect(await router.isCurated(asset.address)).to.equal(false);
    expect(BN2Str(await router.curatedPoolLimit())).to.equal('1');
    expect(BN2Str(await router.curatedPoolCount())).to.equal('0');
    await router.curatePool(asset.address, {from:acc1})
    expect(await router.isCurated(asset.address)).to.equal(true);
    expect(BN2Str(await router.curatedPoolCount())).to.equal('1');
  });
  it("Fail curate second", async function() {
    await router.curatePool(asset2.address, {from:acc1})
    expect(await router.isCurated(asset2.address)).to.equal(false);
    expect(BN2Str(await router.curatedPoolCount())).to.equal('1');
  });
  it("Increase limit", async function() {
    await dao.newParamProposal("ROUTER_PARAMS", '1', '1', '2', '0')
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    expect(BN2Str(await router.curatedPoolLimit())).to.equal('2');
    await router.curatePool(asset2.address, {from:acc1})
    expect(await router.isCurated(asset2.address)).to.equal(true);
    expect(BN2Str(await router.curatedPoolCount())).to.equal('2');

  });
  it("Replace 1-for-1", async function() {
    await router.replacePool(asset2.address, asset3.address, {from:acc1})
    expect(await router.isCurated(asset2.address)).to.equal(true);
    expect(await router.isCurated(asset3.address)).to.equal(false);

    await router.addLiquidity(usdv.address, '1', asset3.address, '1', {from:acc1})
    await router.replacePool(asset2.address, asset3.address, {from:acc1})
    expect(await router.isCurated(asset2.address)).to.equal(false);
    expect(await router.isCurated(asset3.address)).to.equal(true);
  });
});

describe("Should Do Rewards and Protection", function() {
  it("Not curated, No rewards", async function() {
    expect(await router.isCurated(asset2.address)).to.equal(false);
    // expect(await reserve.reserveUSDV()).to.be.greaterThan(getBN(1));
    expect(BN2Str(await utils.getRewardShare(asset2.address, '1'))).to.equal('0');
  });
  it("Curated, Rewards", async function() {
    await router.curatePool(asset.address, {from:acc1})
    expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
    // expect(BN2Str(await utils.getRewardShare(asset.address, '1'))).to.equal('2');
  });
  it("Not curated, No Protection", async function() {
    for(let i = 0; i<9; i++){
      await router.swap('100', asset2.address, usdv.address, {from:acc1})
    }
    let coverage = await utils.getCoverage(acc1, asset2.address)
    expect(BN2Str(await utils.getProtection(acc1, asset2.address, "10000", '1'))).to.equal('0');
  });
  it("Curated, Protection", async function() {
    for(let i = 0; i<9; i++){
      await router.swap('100', asset.address, usdv.address, {from:acc1})
    }
    let coverage = await utils.getCoverage(acc1, asset2.address)
    expect(BN2Str(await utils.getProtection(acc1, asset2.address, "10000", '1'))).to.equal('0');
  });
});
