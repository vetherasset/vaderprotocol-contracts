const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var Vault = artifacts.require('./Vault')
var Asset = artifacts.require('./Token1')
var Anchor = artifacts.require('./Token2')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var usdv; var vault; var anchor; var asset;
var anchor0; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5; 
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
const one = 10**18

before(async function() {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()

  utils = await Utils.new();
  vether = await Vether.new();
  vader = await Vader.new(vether.address);
  usdv = await USDV.new(vader.address, utils.address);
  vault = await Vault.new(vader.address, usdv.address, utils.address);
  asset = await Asset.new();
  anchor0 = await Anchor.new();
  anchor1 = await Anchor.new();
  anchor2 = await Anchor.new();
  anchor3 = await Anchor.new();
  anchor4 = await Anchor.new();
  anchor5 = await Anchor.new();

  console.log('acc0:', acc0)
  console.log('acc1:', acc1)
  console.log('acc2:', acc2)
  console.log('utils:', utils.address)
  console.log('vether:', vether.address)
  console.log('vader:', vader.address)
  console.log('usdv:', usdv.address)
  console.log('vault:', vault.address)

  await usdv.setVault(vault.address)
  await utils.setVault(vault.address)
  await vader.setVSD(usdv.address)

  await vether.transfer(acc1, BN2Str(6006)) 
  await anchor0.transfer(acc1, BN2Str(2000))
  await anchor0.approve(vault.address, BN2Str(one), {from:acc1})
  await anchor1.transfer(acc1, BN2Str(2000))
  await anchor1.approve(vault.address, BN2Str(one), {from:acc1})
  await anchor2.transfer(acc1, BN2Str(2000))
  await anchor2.approve(vault.address, BN2Str(one), {from:acc1})
  await anchor3.transfer(acc1, BN2Str(2000))
  await anchor3.approve(vault.address, BN2Str(one), {from:acc1})
  await anchor4.transfer(acc1, BN2Str(2000))
  await anchor4.approve(vault.address, BN2Str(one), {from:acc1})
  await anchor5.transfer(acc1, BN2Str(2000))
  await anchor5.approve(vault.address, BN2Str(one), {from:acc1})

  await vether.approve(vader.address, '6000', {from:acc1})
  await vader.upgrade('6000', {from:acc1}) 
  await vault.addLiquidity(vader.address, '100', anchor0.address, '99', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor1.address, '100', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor2.address, '101', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor3.address, '102', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor4.address, '103', {from:acc1})

  // await vault.addLiquidity(usdv.address, '1000', vader.address, '1000', {from:acc1})
  // await vault.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})

})
// acc  | VTH | VADER  | USDV | Anr  |  Ass |
// vault|   0 | 2000 | 2000 | 1000 | 1000 |
// acc1 |   0 | 1000 | 1000 | 1000 | 1000 |

describe("Deploy right", function() {
  it("Should have right prices", async function() {
    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '100'))).to.equal('101');
    expect(BN2Str(await utils.calcValueInBase(anchor1.address, '100'))).to.equal('100');
    expect(BN2Str(await utils.calcValueInBase(anchor2.address, '100'))).to.equal('99');
    expect(BN2Str(await utils.calcValueInBase(anchor3.address, '100'))).to.equal('98');
    expect(BN2Str(await utils.calcValueInBase(anchor4.address, '100'))).to.equal('97');
    
  });
});

describe("Handle Anchors", function() {
  it("List Anchors", async function() {
    await vault.listAnchor(anchor0.address, {from:acc1})
    await vault.listAnchor(anchor1.address, {from:acc1})
    await vault.listAnchor(anchor2.address, {from:acc1})
    await vault.listAnchor(anchor3.address, {from:acc1})
    await vault.listAnchor(anchor4.address, {from:acc1})
    await truffleAssert.reverts(vault.listAnchor(anchor4.address, {from:acc1}))
  });
  it("Get prices", async function() {
    await vault.updateAnchorPrices()
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('990099009900990099')
    expect(BN2Str(await vault.getVADERAmount('100'))).to.equal('99')
    expect(BN2Str(await vault.getVSDAmount('100'))).to.equal('101')
  });
  it("Replace Median", async function() {
    await vault.swap(vader.address, '2', anchor4.address, {from:acc1})
    expect(BN2Str(await vault.mapToken_baseAmount(anchor4.address))).to.equal('102');
    expect(BN2Str(await vault.mapToken_tokenAmount(anchor4.address))).to.equal('102');
    expect(BN2Str(await utils.calcValueInBase(anchor4.address, '100'))).to.equal('100');
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await vault.getVADERAmount('100'))).to.equal('100')
    expect(BN2Str(await vault.getVSDAmount('100'))).to.equal('100')
  });
  it("Create outlier", async function() {
    await vault.swap(vader.address, '10', anchor0.address, {from:acc1})
    expect(BN2Str(await vault.mapToken_baseAmount(anchor0.address))).to.equal('110');
    expect(BN2Str(await vault.mapToken_tokenAmount(anchor0.address))).to.equal('91');
    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '100'))).to.equal('120');
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await vault.getVADERAmount('100'))).to.equal('100')
    expect(BN2Str(await vault.getVSDAmount('100'))).to.equal('100')
  });
  it("Replace Outlier", async function() {
    expect(await vault.arrayAnchors('0')).to.equal(anchor0.address)
    await vault.addLiquidity(vader.address, '111', anchor5.address, '111', {from:acc1})
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await utils.calcValueInBase(anchor0.address, '1000000000000000000'))).to.equal('1208791208791208791');
    expect(BN2Str(await utils.calcValueInBase(anchor5.address, '1000000000000000000'))).to.equal('1000000000000000000');
    
    await vault.replaceAnchor(anchor0.address, anchor5.address, {from:acc1})
    expect(await vault.arrayAnchors('0')).to.equal(anchor5.address)
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await vault.getVADERAmount('100'))).to.equal('100')
    expect(BN2Str(await vault.getVSDAmount('100'))).to.equal('100')
    
  });

});

