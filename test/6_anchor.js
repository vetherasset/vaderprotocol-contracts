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
function approx(number){
  return BN2Str((getBN(number).div(10**16)).integerValue())
}

async function setNextBlockTimestamp(ts) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [ts])
  await ethers.provider.send('evm_mine')
}

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

var utils;
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var router; var lender; var factory;
var anchor0; var anchor1; var anchor2; var anchor3; var anchor4; var anchor5;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;

const one = 10**18
const ts0 = 1830297600 // Sat Jan 01 2028 00:00:00 GMT+0000

before(async function() {
  await setNextBlockTimestamp(ts0)

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

  asset = await Asset.new();
  anchor0 = await Anchor.new();
  anchor1 = await Anchor.new();
  anchor2 = await Anchor.new();
  anchor3 = await Anchor.new();
  anchor4 = await Anchor.new();
  anchor5 = await Anchor.new()
})

describe("Deploy Anchor", function() {
  it("Should deploy", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)

    await vether.transfer(acc1, BN2Str(6006))

    await vader.approve(usdv.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc1})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})

    await vader.upgrade('6', {from:acc1})

    await anchor0.transfer(acc1, BN2Str(2000))
    await anchor0.approve(router.address, BN2Str(one), {from:acc1})
    await anchor1.transfer(acc1, BN2Str(2000))
    await anchor1.approve(router.address, BN2Str(one), {from:acc1})
    await anchor2.transfer(acc1, BN2Str(2000))
    await anchor2.approve(router.address, BN2Str(one), {from:acc1})
    await anchor3.transfer(acc1, BN2Str(2000))
    await anchor3.approve(router.address, BN2Str(one), {from:acc1})
    await anchor4.transfer(acc1, BN2Str(2000))
    await anchor4.approve(router.address, BN2Str(one), {from:acc1})
    await anchor5.transfer(acc1, BN2Str(2000))
    await anchor5.approve(router.address, BN2Str(one), {from:acc1})

    await router.addLiquidity(vader.address, '100', anchor0.address, '99', {from:acc1})
    await router.addLiquidity(vader.address, '100', anchor1.address, '100', {from:acc1})
    await router.addLiquidity(vader.address, '100', anchor2.address, '101', {from:acc1})
    await router.addLiquidity(vader.address, '100', anchor3.address, '102', {from:acc1})
    await router.addLiquidity(vader.address, '100', anchor4.address, '103', {from:acc1})

    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '100'))).to.equal('101');
    expect(BN2Str(await utils.calcValueInBase(anchor1.address, '100'))).to.equal('100');
    expect(BN2Str(await utils.calcValueInBase(anchor2.address, '100'))).to.equal('99');
    expect(BN2Str(await utils.calcValueInBase(anchor3.address, '100'))).to.equal('98');
    expect(BN2Str(await utils.calcValueInBase(anchor4.address, '100'))).to.equal('97');
  });
});

describe("Handle Anchors", function() {
  it("List Anchors", async function() {
    await router.listAnchor(anchor0.address, {from:acc1})
    await router.listAnchor(anchor1.address, {from:acc1})
    await router.listAnchor(anchor2.address, {from:acc1})
    await router.listAnchor(anchor3.address, {from:acc1})
    await router.listAnchor(anchor4.address, {from:acc1})
    await truffleAssert.reverts(router.listAnchor(anchor4.address, {from:acc1}))
  });
  it("Get prices", async function() {
    expect(BN2Str(await router.getAnchorPrice())).to.equal('990099009900990099')
    // expect(BN2Str(await router.getVADERAmount('100'))).to.equal('99')
    // expect(BN2Str(await router.getUSDVAmount('100'))).to.equal('101')
  });
  it("Replace Median", async function() {
    await router.swap('2', vader.address, anchor4.address, {from:acc1})
    expect(BN2Str(await pools.mapToken_baseAmount(anchor4.address))).to.equal('102');
    expect(BN2Str(await pools.mapToken_tokenAmount(anchor4.address))).to.equal('102');
    expect(BN2Str(await utils.calcValueInBase(anchor4.address, '100'))).to.equal('100');
    expect(BN2Str(await router.getAnchorPrice())).to.equal('1000000000000000000')
    // expect(BN2Str(await router.getVADERAmount('100'))).to.equal('100')
    // expect(BN2Str(await router.getUSDVAmount('100'))).to.equal('100')
  });
  it("Create outlier", async function() {
    await router.swap('10', vader.address, anchor0.address, {from:acc1})
    expect(BN2Str(await pools.mapToken_baseAmount(anchor0.address))).to.equal('110');
    expect(BN2Str(await pools.mapToken_tokenAmount(anchor0.address))).to.equal('91');
    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '100'))).to.equal('120');
    expect(BN2Str(await router.getAnchorPrice())).to.equal('1000000000000000000')
    // expect(BN2Str(await router.getVADERAmount('100'))).to.equal('100')
    // expect(BN2Str(await router.getUSDVAmount('100'))).to.equal('100')
  });
  it("Replace Outlier", async function() {
    expect(await router.arrayAnchors('0')).to.equal(anchor0.address)
    await router.addLiquidity(vader.address, '111', anchor5.address, '111', {from:acc1})
    expect(BN2Str(await router.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '1000000000000000000'))).to.equal('1208791208791208791');
    expect(BN2Str(await utils.calcValueInBase(anchor5.address, '1000000000000000000'))).to.equal('1000000000000000000');
    await router.replaceAnchor(anchor0.address, anchor5.address, {from:acc1})
    expect(await router.arrayAnchors('0')).to.equal(anchor5.address)
    expect(BN2Str(await router.getAnchorPrice())).to.equal('1000000000000000000')
    // expect(BN2Str(await router.getVADERAmount('100'))).to.equal('100')
    // expect(BN2Str(await router.getUSDVAmount('100'))).to.equal('100')
  });

});

describe("Handle TWAP", function() {
  it("Get prices", async function() {
    const ts1 = ts0 + 2000
    await setNextBlockTimestamp(ts1)
    // expect(approx(await router.getTWAPPrice())).to.equal('1')
    await router.swap('10', vader.address, anchor0.address, {from:acc1})
    await router.swap('10', vader.address, anchor1.address, {from:acc1})
    await router.swap('10', vader.address, anchor2.address, {from:acc1})
    await router.swap('10', vader.address, anchor3.address, {from:acc1})
    await router.swap('10', vader.address, anchor4.address, {from:acc1})
    await setNextBlockTimestamp(ts1 + 1*15)
    expect(approx(await router.getTWAPPrice())).to.equal('31')
    await router.swap('10', anchor0.address, vader.address, {from:acc1})
    await router.swap('10', anchor1.address, vader.address, {from:acc1})
    await router.swap('10', anchor2.address, vader.address, {from:acc1})
    await router.swap('10', anchor3.address, vader.address, {from:acc1})
    await router.swap('10', anchor4.address, vader.address, {from:acc1})
    await setNextBlockTimestamp(ts1 + 2*15)
    expect(approx(await router.getTWAPPrice())).to.equal('32')
    await router.swap('10', anchor0.address, vader.address, {from:acc1})
    await router.swap('10', anchor1.address, vader.address, {from:acc1})
    await router.swap('10', anchor2.address, vader.address, {from:acc1})
    await router.swap('10', anchor3.address, vader.address, {from:acc1})
    await router.swap('10', anchor4.address, vader.address, {from:acc1})
    await setNextBlockTimestamp(ts1 + 3*15)
    expect(approx(await router.getTWAPPrice())).to.equal('27')
    expect(approx(await router.getAnchorPrice())).to.equal('83')
    expect(BN2Str(await router.getVADERAmount('100'))).to.equal('26')
    expect(BN2Str(await router.getUSDVAmount('100'))).to.equal('374')
  });
});
