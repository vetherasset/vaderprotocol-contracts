const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var VSD = artifacts.require('./VSD')
var VAULT = artifacts.require('./Vault')
var Anchor = artifacts.require('./Token2')
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var vsd; var vault;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
var anchor0; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5; 
const one = 10**18

// 

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
  vault = await VAULT.new(vader.address, vsd.address, utils.address);
  anchor0 = await Anchor.new();
  anchor1 = await Anchor.new();
  anchor2 = await Anchor.new();
  anchor3 = await Anchor.new();
  anchor4 = await Anchor.new();
  anchor5 = await Anchor.new();

  await vsd.setVault(vault.address)
  await utils.setVault(vault.address)
  await vader.setVSD(vsd.address)

  await vether.transfer(acc1, BN2Str(3403)) 
  await vether.approve(vader.address, '3400', {from:acc1})
  await vader.upgrade('3400', {from:acc1}) 

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

  await vault.addLiquidity(vader.address, '100', anchor0.address, '98', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor1.address, '99', {from:acc1})
  await vault.addLiquidity(vader.address, '1000', anchor2.address, '1000', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor3.address, '101', {from:acc1})
  await vault.addLiquidity(vader.address, '100', anchor4.address, '102', {from:acc1})
  await vault.listAnchor(anchor0.address, {from:acc1})
  await vault.listAnchor(anchor1.address, {from:acc1})
  await vault.listAnchor(anchor2.address, {from:acc1})
  await vault.listAnchor(anchor3.address, {from:acc1})
  await vault.listAnchor(anchor4.address, {from:acc1})
})

// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 |  2000 |    0 |

describe("Deploy", function() {
  it("Should deploy", async function() {
    expect(await vsd.name()).to.equal("VADER STABLE DOLLAR");
    expect(await vsd.symbol()).to.equal("VSD");
    expect(BN2Str(await vsd.decimals())).to.equal('18');
    expect(BN2Str(await vsd.totalSupply())).to.equal('0');
    expect(BN2Str(await vsd.erasToEarn())).to.equal('100');
    // expect(BN2Str(await vsd.minimumDepositTime())).to.equal('1');
    expect(await vsd.DAO()).to.equal(acc0);
    expect(await vsd.UTILS()).to.equal(utils.address);
  });
});

describe("Convert to VSD", function() {

  it("Should convert acc1", async function() {
    await vsd.convert('1000', {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(2400));
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1000));
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(1000));
  });
  it("Should withdraw VSD", async function() {
    await vsd.withdrawToVSD('5000',{from:acc1})
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(500));
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(500));
  });
  it("Should withdraw VADER", async function() {
    await vsd.withdrawToVADER('10000',{from:acc1})
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(0));
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str(500));
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(2900));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1500));
  });
  it("Should convert acc1", async function() {
    await vsd.convert('500', {from:acc1})
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(500));
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(2400));
    await vsd.withdrawToVSD('10000',{from:acc1})
  });

// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 | 1000 | 1000 |

});

describe("Be a valid ERC-20", function() {
  it("Should transfer From", async function() {
    await vsd.approve(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vsd.allowance(acc1, acc0))).to.equal('100');
    await vsd.transferFrom(acc1, acc0, "100", {from:acc0})
    expect(BN2Str(await vsd.balanceOf(acc0))).to.equal('100');
  });
// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  900 |

  it("Should transfer to", async function() {
    await vsd.transferTo(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vsd.balanceOf(acc0))).to.equal('200');
  });
// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |  200 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn", async function() {
    await vsd.burn("100", {from:acc0})
    expect(BN2Str(await vsd.balanceOf(acc0))).to.equal('100');
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str('900'));
  });
// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn from", async function() {
    await vsd.approve(acc1, "100", {from:acc0}) 
    expect(BN2Str(await vsd.allowance(acc0, acc1))).to.equal('100');
    await vsd.burnFrom(acc0, "100", {from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc0))).to.equal('0');
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str('800'));
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal('800');
  });
// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |  0   |
// acc1 |   0 | 1000 |  800 |

});

describe("Member should deposit for rewards", function() {
  it("Should deposit", async function() {
    // await vader.transfer(acc3, balance/2, {from:acc1})
    await vsd.deposit('200', {from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(600));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(200));
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(200));
    expect(await vsd.isMember(acc1)).to.equal(true);
    expect(BN2Str(await vsd.totalFunds())).to.equal(BN2Str(200));
  });
// acc  | VTH | VADER  | VSD | DEP |
// acc0 |   0 |    0 |  0   |   0 |
// acc1 |   0 | 1400 |  100 | 200 |

  it("Should calc rewards", async function() {
    let balanceStart = await vader.balanceOf(vsd.address)
    expect(BN2Str(balanceStart)).to.equal(BN2Str(0));
    await vader.startEmissions()
    await vader.changeEmissionCurve('2')
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('1200'));

    await vader.transfer(acc0, BN2Str(100), {from:acc1})
    expect(BN2Str(await vader.currentEra())).to.equal(BN2Str(2));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('1800'));
    expect(BN2Str(await vader.balanceOf(vsd.address))).to.equal(BN2Str(1200));
    await vsd.transfer(acc0, BN2Str(100), {from:acc1})
    expect(BN2Str(await vsd.reserveVSD())).to.equal(BN2Str(400));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(600));
    expect(BN2Str(await vader.balanceOf(vsd.address))).to.equal(BN2Str(1400));
    expect(BN2Str(await vsd.calcPayment(acc1))).to.equal(BN2Str(4)); // 666/100
    expect(BN2Str(await vsd.calcCurrentPayment(acc1))).to.equal(BN2Str(16)); // * by seconds
  });
  it("Should harvest", async function() {
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(500));
    expect(BN2Str(await vsd.calcCurrentPayment(acc1))).to.equal(BN2Str(16)); // * by seconds
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(600));
    expect(BN2Str(await vsd.reserveVSD())).to.equal(BN2Str(400));
    expect(BN2Str(await vader.balanceOf(vsd.address))).to.equal(BN2Str(1400));
    expect(BN2Str(await vault.getAnchorPrice())).to.equal('1000000000000000000')
    expect(BN2Str(await vault.getVADERAmount('100'))).to.equal('100')

    await vsd.harvest({from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(520));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(1047));
  });
  it("Should withdraw", async function() {
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(520));
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(200));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(1047));
    let tx = await vsd.withdrawToVSD("10000",{from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(728));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(1383));
  });
});


