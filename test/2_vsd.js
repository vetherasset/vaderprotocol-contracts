const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var VSD = artifacts.require('./VSD')
var VAULT = artifacts.require('./Vault')
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var vsd; var vault;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
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
  await vader.setVSD(vsd.address)
  expect(await vader.VSD()).to.equal(vsd.address);

  console.log('acc0:', acc0)
  console.log('acc1:', acc1)
  console.log('acc2:', acc2)
  console.log('utils:', utils.address)
  console.log('vether:', vether.address)
  console.log('vader:', vader.address)
  console.log('vsd:', vsd.address)
  console.log('vault:', vault.address)

  await vsd.setVault(vault.address)
  expect(await vsd.VAULT()).to.equal(vault.address);

  await vether.transfer(acc1, BN2Str(2002))
// acc  | VTH | VADER  | VSD |
// acc0 |   0 |    0 |    0 |
// acc1 |2002 |    0 |    0 |

  let balance = await vether.balanceOf(acc1)
  await vether.approve(vader.address, balance, {from:acc1})
  await vader.upgrade(balance, {from:acc1}) 
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
    let balance = await vader.balanceOf(acc1)
    await vsd.convert(balance/2, {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(1000));
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
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(1500));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1500));
  });
  it("Should convert acc1", async function() {
    await vsd.convert('500', {from:acc1})
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(500));
    expect(BN2Str(await vsd.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(1000));
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
    await vader.changeEmissionCurve('1')
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('1000'));

    await vader.transfer(acc0, BN2Str(100), {from:acc1})
    expect(BN2Str(await vader.currentEra())).to.equal(BN2Str(2));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('2000'));
    expect(BN2Str(await vader.balanceOf(vsd.address))).to.equal(BN2Str(1000));
    await vsd.transfer(acc0, BN2Str(100), {from:acc1})
    expect(BN2Str(await vsd.reserveVSD())).to.equal(BN2Str(666));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(866));
    expect(BN2Str(await vader.balanceOf(vsd.address))).to.equal(BN2Str(334));

    expect(BN2Str(await vsd.calcPayment(acc1))).to.equal(BN2Str(6)); // 666/100
    expect(BN2Str(await vsd.calcCurrentPayment(acc1))).to.equal(BN2Str(24)); // * by seconds
  });
  it("Should harvest", async function() {
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(500));
    expect(BN2Str(await vsd.calcCurrentPayment(acc1))).to.equal(BN2Str(24)); // * by seconds
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(866));
    await vsd.harvest({from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(530));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(1058));
  });
  it("Should withdraw", async function() {
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(530));
    expect(BN2Str(await vsd.getMemberDeposit(acc1))).to.equal(BN2Str(200));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(1058));
    let tx = await vsd.withdrawToVSD("10000",{from:acc1})
    expect(BN2Str(await vsd.balanceOf(acc1))).to.equal(BN2Str(738));
    expect(BN2Str(await vsd.balanceOf(vsd.address))).to.equal(BN2Str(924));
  });
});


