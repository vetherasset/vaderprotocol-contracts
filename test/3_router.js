const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var Vault = artifacts.require('./Vault')
var Router = artifacts.require('./Router')
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
  vader = await Vader.new();
  usdv = await USDV.new();
  router = await Router.new();
  vault = await Vault.new();

  // console.log('acc0:', acc0)
  // console.log('acc1:', acc1)
  // console.log('acc2:', acc2)
  // console.log('utils:', utils.address)
  // console.log('vether:', vether.address)
  // console.log('vader:', vader.address)
  // console.log('vsd:', usdv.address)
  // console.log('vault:', vault.address)

})


describe("Deploy Router", function() {
  it("Should deploy", async function() {
    await vader.init(vether.address, usdv.address, utils.address)
    await usdv.init(vader.address, router.address)
    await router.init(vader.address, usdv.address, vault.address);
    await vault.init(vader.address, usdv.address, router.address);

    asset = await Asset.new();
    asset2 = await Asset.new();
    anchor = await Anchor.new();
    anchor2 = await Anchor.new();

    await vether.transfer(acc1, BN2Str(7407)) 
    await anchor.transfer(acc1, BN2Str(2000))
    await anchor.approve(router.address, BN2Str(one), {from:acc1})
    await anchor2.transfer(acc1, BN2Str(2000))
    await anchor2.approve(router.address, BN2Str(one), {from:acc1})

    await vether.approve(vader.address, '7400', {from:acc1})
    await vader.upgrade(BN2Str(7400), {from:acc1}) 

    await asset.transfer(acc1, BN2Str(2000))
    await asset.approve(router.address, BN2Str(one), {from:acc1})
    await asset2.transfer(acc1, BN2Str(2000))
    await asset2.approve(router.address, BN2Str(one), {from:acc1})

    await usdv.convertToUSDV(BN2Str(3000), {from:acc1})
    // await usdv.withdrawToUSDV('10000', {from:acc1})

    expect(await router.DAO()).to.equal(acc0);
    expect(await router.UTILS()).to.equal(utils.address);
    expect(await router.VADER()).to.equal(vader.address);
    expect(await router.USDV()).to.equal(usdv.address);
  });
});


describe("Add liquidity", function() {
  it("Should add anchor", async function() {
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
    expect(BN2Str(await vault.getUnits(anchor.address))).to.equal('1000');
    expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('1000');
    expect(BN2Str(await vault.getMemberUnits(anchor.address, acc1))).to.equal('1000');
  });
  it("Should add anchor2", async function() {
    await router.addLiquidity(vader.address, '1000', anchor2.address, '1000', {from:acc1})
    expect(BN2Str(await vault.getUnits(anchor2.address))).to.equal('1000');
    expect(BN2Str(await vault.getBaseAmount(anchor2.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await vault.getTokenAmount(anchor2.address))).to.equal('1000');
    expect(BN2Str(await vault.getMemberUnits(anchor2.address, acc1))).to.equal('1000');
  });
  it("Should add asset", async function() {
    let tx = await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})
    expect(BN2Str(await vault.mapToken_Units(asset.address))).to.equal('1000');
    expect(BN2Str(await vault.mapToken_baseAmount(asset.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await vault.mapToken_tokenAmount(asset.address))).to.equal('1000');
    expect(BN2Str(await vault.mapTokenMember_Units(asset.address, acc1))).to.equal('1000');
  });
  it("Should add asset2", async function() {
    let tx = await router.addLiquidity(usdv.address, '1000', asset2.address, '1000', {from:acc1})
    expect(BN2Str(await vault.mapToken_Units(asset2.address))).to.equal('1000');
    expect(BN2Str(await vault.mapToken_baseAmount(asset2.address))).to.equal(BN2Str(1000));
    expect(BN2Str(await vault.mapToken_tokenAmount(asset2.address))).to.equal('1000');
    expect(BN2Str(await vault.mapTokenMember_Units(asset2.address, acc1))).to.equal('1000');
  });
});

describe("Should Swap VADER Pools", function() {
  it("Swap from Vader to Anchor", async function() {
    await router.swap('250', vader.address, anchor.address, {from:acc1})
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('2150');
    expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal('1250');
    expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('840');
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('1160');
  });
  it("Swap to Anchor", async function() {
    await router.swap('160', anchor.address, vader.address, {from:acc1})
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('1000');
    expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('1000');
    expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal('1082');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('2318');
  });

it("Swap to Other Anchor", async function() {
  await router.swap('250', anchor.address, anchor2.address, {from:acc1})
  expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('750');
  expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('1250');
  expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal('909');
  expect(BN2Str(await vault.getBaseAmount(anchor2.address))).to.equal('1173');
  expect(BN2Str(await vault.getTokenAmount(anchor2.address))).to.equal('875');
  expect(BN2Str(await anchor2.balanceOf(acc1))).to.equal('1125');
});

});

describe("Should Swap USDV Pools", function() {
  it("Swap from USDV to Anchor", async function() {
    await router.swap('250', usdv.address, asset.address, {from:acc1})
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('750');
    expect(BN2Str(await vault.getBaseAmount(asset.address))).to.equal('1250');
    expect(BN2Str(await vault.getTokenAmount(asset.address))).to.equal('840');
    expect(BN2Str(await asset.balanceOf(acc1))).to.equal('1160');
  });
  it("Swap to Anchor", async function() {
    await router.swap('160', asset.address, usdv.address, {from:acc1})
    expect(BN2Str(await asset.balanceOf(acc1))).to.equal('1000');
    expect(BN2Str(await vault.getTokenAmount(asset.address))).to.equal('1000');
    expect(BN2Str(await vault.getBaseAmount(asset.address))).to.equal('1082');
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('918');
  });

it("Swap to Other Anchor", async function() {
  await router.swap('250', asset.address, asset2.address, {from:acc1})
  expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('750');
  expect(BN2Str(await vault.getTokenAmount(asset.address))).to.equal('1250');
  expect(BN2Str(await vault.getBaseAmount(asset.address))).to.equal('909');
  expect(BN2Str(await vault.getBaseAmount(asset2.address))).to.equal('1173');
  expect(BN2Str(await vault.getTokenAmount(asset2.address))).to.equal('875');
  expect(BN2Str(await asset2.balanceOf(acc1))).to.equal('1125');
});

});

describe("Should Swap Above Limit", function() {
  it("Fail when swap above limit", async function() {
    await truffleAssert.reverts(router.swapWithLimit('250', usdv.address, asset.address, '1', {from:acc1}))
  });
  
});

describe("Should remove liquidity", function() {
  it("REmove Anchor", async function() {
    await router.removeLiquidity(vader.address, anchor.address, '5000', {from:acc1})
    expect(BN2Str(await vault.getUnits(anchor.address))).to.equal('500');
    expect(BN2Str(await vault.getMemberUnits(anchor.address, acc1))).to.equal('500');
    expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal('455');
    expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('625');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('2772');
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('1375');
  });
  it("REmove Anchor", async function() {
    await router.removeLiquidity(vader.address, anchor.address, '10000', {from:acc1})
    expect(BN2Str(await vault.getUnits(anchor.address))).to.equal('0');
    expect(BN2Str(await vault.getMemberUnits(anchor.address, acc1))).to.equal('0');
    expect(BN2Str(await vault.getBaseAmount(anchor.address))).to.equal('0');
    expect(BN2Str(await vault.getTokenAmount(anchor.address))).to.equal('0');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3227');
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('2000');
  });
});