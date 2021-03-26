const { expect } = require("chai");
var Token1 = artifacts.require('./Token1')
var Base = artifacts.require('./Base')
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var token1; var base;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
const one = 10**18

before(async function() {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()

  token1 = await Token1.new();
  base = await Base.new(token1.address);
  await token1.transfer(acc1, BN2Str(10000 * one))
  await token1.transfer(acc2, BN2Str(10000 * one))
})

describe("Deploy", function() {
  it("Should deploy", async function() {
    expect(await base.name()).to.equal("BASE PROTOCOL TOKEN");
    expect(await base.symbol()).to.equal("BASE");
    expect(BN2Str(await base.decimals())).to.equal('18');
    expect(BN2Str(await base.totalSupply())).to.equal('0');
    expect(BN2Str(await base.totalCap())).to.equal(BN2Str(3000000 * one));
    expect(BN2Str(await base.emissionCurve())).to.equal('2048');
    expect(await base.emitting()).to.equal(false);
    expect(BN2Str(await base.currentEra())).to.equal('1');
    expect(BN2Str(await base.secondsPerEra())).to.equal('1');
    // console.log(BN2Str(await base.nextEraTime()));
    expect(await base.DAO()).to.equal(acc0);
    expect(await base.burnAddress()).to.equal("0x0111011001100001011011000111010101100101");
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('0'));
  });
});

describe("Upgrade", function() {

  it("Should upgrade acc1", async function() {
      // first, upgrade 50m
    let balance = await token1.balanceOf(acc1)
    await token1.approve(base.address, balance, {from:acc1})
    expect(BN2Str(await token1.allowance(acc1, base.address))).to.equal(BN2Str(balance));
    await base.upgrade({from:acc1})
    expect(BN2Str(await base.totalSupply())).to.equal(BN2Str(10000 * one));
    expect(BN2Str(await token1.balanceOf(acc1))).to.equal(BN2Str(0));
    expect(BN2Str(await base.balanceOf(acc1))).to.equal(BN2Str(10000 * one));
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('9765625000000000000'));
  });

  it("Should upgrade acc2", async function() {
    // first, upgrade 50m
    let balance = await token1.balanceOf(acc2)
    await token1.approve(base.address, balance, {from:acc2})
    await base.upgrade({from:acc2})
    expect(BN2Str(await base.totalSupply())).to.equal(BN2Str(20000 * one));
    expect(BN2Str(await token1.balanceOf(acc2))).to.equal(BN2Str(0));
    expect(BN2Str(await base.balanceOf(acc2))).to.equal(BN2Str(10000 * one));
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('19531250000000000000'));
    });

});

describe("Be a valid ERC-20", function() {
  it("Should transfer From", async function() {
    await base.approve(acc0, "1000", {from:acc1}) 
    expect(BN2Str(await base.allowance(acc1, acc0))).to.equal('1000');
    await base.transferFrom(acc1, acc0, "1000", {from:acc0})
    expect(BN2Str(await base.balanceOf(acc0))).to.equal('1000');
  });
  it("Should transfer to", async function() {
    await base.transferTo(acc0, "1000", {from:acc1}) 
    expect(BN2Str(await base.balanceOf(acc0))).to.equal('2000');
  });
  it("Should burn", async function() {
    await base.burn("500", {from:acc0})
    expect(BN2Str(await base.balanceOf(acc0))).to.equal('1500');
    expect(BN2Str(await base.totalSupply())).to.equal(BN2Str('19999999999999999999500'));

  });
  it("Should burn from", async function() {
    await base.approve(acc2, "500", {from:acc0}) 
    expect(BN2Str(await base.allowance(acc0, acc2))).to.equal('500');
    await base.burnFrom(acc0, "500", {from:acc2})
    expect(BN2Str(await base.balanceOf(acc0))).to.equal('1000');
    expect(BN2Str(await base.totalSupply())).to.equal(BN2Str('19999999999999999999000'));

  });
});

describe("DAO Functions", function() {
  it("Non-DAO fails", async function() {
    await truffleAssert.reverts(base.startEmissions({from:acc1}))
  });
  it("DAO changeEmissionCurve", async function() {
    await base.changeEmissionCurve('1024')
    expect(BN2Str(await base.emissionCurve())).to.equal('1024');
  });
  it("DAO changeIncentiveAddress", async function() {
    await base.changeIncentiveAddress(acc3)
    expect(await base.incentiveAddress()).to.equal(acc3);
  });
  it("DAO changeDAO", async function() {
    await base.changeDAO(acc2)
    expect(await base.DAO()).to.equal(acc2);
  });
  it("DAO start emitting", async function() {
    await base.startEmissions({from:acc2})
    expect(await base.emitting()).to.equal(true);
  });
  
  it("Old DAO fails", async function() {
    await truffleAssert.reverts(base.startEmissions())
  });
});

describe("Emissions", function() {
  it("Should emit properly", async function() {
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('39062499999999999998'));
    // await sleep(2000)
    await base.transfer(acc0, BN2Str(10000 * one), {from:acc2})
    await base.transfer(acc1, BN2Str(10000 * one), {from:acc0})
    expect(BN2Str(await base.currentEra())).to.equal('3');
    expect(BN2Str(await base.balanceOf(acc3))).to.equal(BN2Str('78201293945312499996'));
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('39215236902236938474'));
    
    await sleep(2000)
    await base.transfer(acc0, BN2Str(10000 * one), {from:acc1})
    expect(BN2Str(await base.currentEra())).to.equal('4');
    expect(BN2Str(await base.balanceOf(acc3))).to.equal(BN2Str('117416530847549438470'));
    expect(BN2Str(await base.getDailyEmission())).to.equal(BN2Str('39291829161811619995'));
  });

  it("DAO changeEraDuration", async function() {
    await base.changeEraDuration('200',{from:acc2})
    expect(BN2Str(await base.secondsPerEra())).to.equal('200');
  });
});
