const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var VSD = artifacts.require('./VSD')
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

var utils; var vader; var vether; var vsd; var vault; var anchor; var asset;
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
  vsd = await VSD.new(vader.address, utils.address);
  vault = await Vault.new(vader.address, vsd.address, utils.address);
  asset = await Asset.new();
  anchor = await Anchor.new();

  console.log('acc0:', acc0)
  console.log('acc1:', acc1)
  console.log('acc2:', acc2)
  console.log('utils:', utils.address)
  console.log('vether:', vether.address)
  console.log('vader:', vader.address)
  console.log('vsd:', vsd.address)
  console.log('vault:', vault.address)

  await vsd.setVault(vault.address)
  await vader.setVSD(vsd.address)
  // await vader.changeEmissionCurve('1')
  await vader.startEmissions() 

  await vether.transfer(acc1, BN2Str(6006)) 
  await anchor.transfer(acc1, BN2Str(2000))
  await anchor.approve(vault.address, BN2Str(one), {from:acc1})
  await asset.transfer(acc1, BN2Str(2000))
  await asset.approve(vault.address, BN2Str(one), {from:acc1})
  await vether.approve(vader.address, '6000', {from:acc1})
  await vader.upgrade(BN2Str(6000), {from:acc1}) 
  await vsd.convert(BN2Str(3000), {from:acc1})
  await vsd.withdrawToVSD('10000', {from:acc1})
// acc  | VTH | VADER  | VSD | Anr  |  Ass |
// vault|   0 |    0 |    0 |    0 |    0 |
// acc1 |   0 | 3000 | 3000 | 2000 | 2000 |
  await vault.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
  await vault.addLiquidity(vsd.address, '1000', vader.address, '1000', {from:acc1})
  await vault.addLiquidity(vsd.address, '1000', asset.address, '1000', {from:acc1})



})
// acc  | VTH | VADER  | VSD | Anr  |  Ass |
// vault|   0 | 2000 | 2000 | 1000 | 1000 |
// acc1 |   0 | 1000 | 1000 | 1000 | 1000 |

describe("Deploy right", function() {
  it("Should have right reserves", async function() {
    expect(BN2Str(await vader.getDailyEmission())).to.equal('3');
    expect(BN2Str(await vsd.reserveVSD())).to.equal('13');
    expect(BN2Str(await vault.reserveVSD())).to.equal('6');
    expect(BN2Str(await vault.reserveVADER())).to.equal('7');
    
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
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal('994');
    for(let i = 0; i<9; i++){
      await vault.swap(vsd.address, '100', vader.address, {from:acc1})
    }
    // expect(BN2Str(await vault.mapToken_tokenAmount(vader.address))).to.equal('1080');
    // expect(BN2Str(await vault.mapToken_baseAmount(vader.address))).to.equal('931');
    // expect(BN2Str(await vsd.balanceOf(acc1))).to.equal('1053');
    expect(BN2Str(await vault.mapMemberToken_depositBase(acc1, vader.address))).to.equal('1000');
    expect(BN2Str(await vault.mapMemberToken_depositToken(acc1, vader.address))).to.equal('1000');

    // console.log("membe units", BN2Str(await vault.mapTokenMember_Units(vader.address, acc1)));
    // console.log("units", BN2Str(await vault.mapToken_Units(vader.address)));
    let coverage = await vault.getCoverage(acc1, vader.address)
    expect(BN2Str(coverage)).to.equal('629');
    expect(BN2Str(await vault.getProtection(acc1, vader.address, "10000", coverage))).to.equal('62');
    let reserveVSD = BN2Str(await vault.reserveVSD())
    expect(BN2Str(await vault.getILProtection(acc1, vsd.address, vader.address, '10000'))).to.equal(reserveVSD);


  });

});

