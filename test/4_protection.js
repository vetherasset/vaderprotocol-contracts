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
const truffleAssert = require('truffle-assertions');
const { VoidSigner } = require("@ethersproject/abstract-signer");

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var usdv; var vault; var anchor; var asset; var router;
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

  await vader.startEmissions()

  await vader.init(vether.address, usdv.address, utils.address)
  await usdv.init(vader.address, router.address)
  await router.init(vader.address, usdv.address, vault.address);
  await vault.init(vader.address, usdv.address, router.address);

  anchor = await Anchor.new();

  await vether.transfer(acc1, BN2Str(7407)) 
  await anchor.transfer(acc1, BN2Str(2000))
  await anchor.approve(router.address, BN2Str(one), {from:acc1})

  await vether.approve(vader.address, '7400', {from:acc1})
  await vader.upgrade(BN2Str(7400), {from:acc1}) 

  await usdv.convertToUSDVDirectly(BN2Str(1000), {from:acc1})
  // await usdv.withdrawToUSDV('10000', {from:acc1})

  await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
})
// acc  | VTH | VADER  | USDV | Anr  |  Ass |
// vault|   0 | 2000 | 2000 | 1000 | 1000 |
// acc1 |   0 | 1000 | 1000 | 1000 | 1000 |

describe("Deploy Protection", function() {
  it("Should have right reserves", async function() {
    await vader.transfer(acc0, '100', {from:acc1})
    await usdv.transfer(acc0, '100', {from:acc1})
    expect(BN2Str(await vader.getDailyEmission())).to.equal('7');
    expect(BN2Str(await usdv.reserveUSDV())).to.equal('7');
    expect(BN2Str(await router.reserveUSDV())).to.equal('7');
    expect(BN2Str(await router.reserveVADER())).to.equal('8');
    
  });
});

describe("Should do IL Protection", function() {
  it("Core math", async function() {
    expect(BN2Str(await utils.calcCoverage('1000', '1000', '1100', '918'))).to.equal('0');
    expect(BN2Str(await utils.calcCoverage('1000', '1000', '1200', '820'))).to.equal('63');

    expect(BN2Str(await utils.calcCoverage('100', '1000', '75', '2000'))).to.equal('0');
    expect(BN2Str(await utils.calcCoverage('100', '1000', '20', '2000'))).to.equal('70');
  });
  it("Small swap, need protection", async function() {
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('900');
    for(let i = 0; i<9; i++){
      await router.swap('100', anchor.address, vader.address, {from:acc1})
    }
    // expect(BN2Str(await vault.mapToken_tokenAmount(vader.address))).to.equal('1080');
    // expect(BN2Str(await vault.mapToken_baseAmount(vader.address))).to.equal('931');
    // expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('1053');
    expect(BN2Str(await router.mapMemberToken_depositBase(acc1, anchor.address))).to.equal('1000');
    expect(BN2Str(await router.mapMemberToken_depositToken(acc1, anchor.address))).to.equal('1000');

    // console.log("membe units", BN2Str(await vault.mapTokenMember_Units(vader.address, acc1)));
    // console.log("units", BN2Str(await vault.mapToken_Units(vader.address)));
    let coverage = await router.getCoverage(acc1, anchor.address)
    expect(BN2Str(coverage)).to.equal('173');
    expect(BN2Str(await router.getProtection(acc1, anchor.address, "10000", coverage))).to.equal('173');
    let reserveVADER = BN2Str(await router.reserveVADER())
    expect(BN2Str(await router.getILProtection(acc1, vader.address, anchor.address, '10000'))).to.equal(reserveVADER);


  });

});

