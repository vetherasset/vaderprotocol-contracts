const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var DAO = artifacts.require('./DAO')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var RESERVE = artifacts.require('./Reserve')
var VAULT = artifacts.require('./Vault')
var POOLS = artifacts.require('./Pools')
var Router = artifacts.require('./Router')
var Lender = artifacts.require('./Lender')
var Factory = artifacts.require('./Factory')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

async function mine() {
  await ethers.provider.send('evm_mine')
}

var utils;
var dao; var vader; var vether; var usdv;
var reserve; var vault; var router; var lender; var pools; var attack; var factory;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;

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
  pools = await POOLS.new(vader.address);
  factory = await Factory.new(pools.address);
})

// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 |  2000 |    0 |

describe("Deploy USDV", function() {
  it("Should deploy", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)

    await vether.transfer(acc1, '3403')
    await vether.approve(vader.address, '3400', {from:acc1})
    await vader.upgrade('4', {from:acc1})

    expect(await usdv.name()).to.equal("VADER STABLE DOLLAR");
    expect(await usdv.symbol()).to.equal("USDV");
    expect(BN2Str(await usdv.decimals())).to.equal('18');
    expect(BN2Str(await usdv.totalSupply())).to.equal('0');
    // expect(BN2Str(await usdv.minimumDepositTime())).to.equal('1');
    // expect(await usdv.DAO()).to.equal(acc0);
    // expect(await usdv.UTILS()).to.equal(utils.address);
  });
});

describe("Convert", function() {
  it("Should convert acc1", async function() {
    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())

    await vader.approve(usdv.address, '10000', {from:acc1})
    await vader.convertToUSDV('250', {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal('3750');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3750');
    expect(BN2Str(await usdv.totalSupply())).to.equal('250');
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('250');
  });
  it("Should convert for member", async function() {
    await vader.convertToUSDVForMember(acc1, '250', {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal('3500');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3500');
    expect(BN2Str(await usdv.totalSupply())).to.equal('500');
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('500');
  });
  it("Should convert acc1 directly", async function() {
    await vader.transfer(usdv.address, '500', {from:acc1})
    await usdv.convertToUSDVDirectly({from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal('3000');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3000');
    expect(BN2Str(await usdv.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal(BN2Str(1000));
  });
  // it("Should redeem", async function() {
  //   // await usdv.approve(usdv.address, '1000', {from:acc1})
  //   expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('1000');
  //   await usdv.redeemToVADER('250',{from:acc1})
  //   // expect(BN2Str(await usdv.getMemberDeposit(acc1))).to.equal(BN2Str(0));
  //   expect(BN2Str(await usdv.totalSupply())).to.equal('750');
  //   expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('750');
  //   expect(BN2Str(await vader.totalSupply())).to.equal('3250');
  //   expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3250');
  // });
  // it("Should redeem for member", async function() {
  //   await usdv.redeemForMember(acc1, '250',{from:acc1})
  //   // expect(BN2Str(await usdv.getMemberDeposit(acc1))).to.equal(BN2Str(0));
  //   expect(BN2Str(await usdv.totalSupply())).to.equal('500');
  //   expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('500');
  //   expect(BN2Str(await vader.totalSupply())).to.equal('3500');
  //   expect(BN2Str(await vader.balanceOf(acc1))).to.equal('3500');
  // });

  it("Should convert acc1", async function() {
    await vader.transfer(usdv.address, '500', {from:acc1})
    await usdv.convertToUSDVForMemberDirectly(acc1, {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal('2500');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('2500');
    expect(BN2Str(await usdv.totalSupply())).to.equal('1500');
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('1500');
  });

// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 | 1000 | 1000 |
});

describe("Be a valid ERC-20", function() {
  it("Should transfer From", async function() {
    await usdv.approve(acc0, "100", {from:acc1})
    expect(BN2Str(await usdv.allowance(acc1, acc0))).to.equal('100');
    await usdv.transferFrom(acc1, acc0, "100", {from:acc0})
    expect(BN2Str(await usdv.balanceOf(acc0))).to.equal('100');
  });
// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  900 |

  it("Should transfer to", async function() {
    await usdv.transfer(acc0, "100", {from:acc1})
    expect(BN2Str(await usdv.balanceOf(acc0))).to.equal('200');
  });
// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |  200 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn", async function() {
    await usdv.burn("100", {from:acc0})
    expect(BN2Str(await usdv.balanceOf(acc0))).to.equal('100');
    expect(BN2Str(await usdv.totalSupply())).to.equal(BN2Str('1400'));
  });
// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn from", async function() {
    await usdv.approve(acc1, "100", {from:acc0})
    expect(BN2Str(await usdv.allowance(acc0, acc1))).to.equal('100');
    await usdv.burnFrom(acc0, "100", {from:acc1})
    expect(BN2Str(await usdv.balanceOf(acc0))).to.equal('0');
    expect(BN2Str(await usdv.totalSupply())).to.equal(BN2Str('1300'));
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('1300');
  });
// acc  | VTH | VADER  | USDV |
// acc0 |   0 |    0 |  0   |
// acc1 |   0 | 1000 |  800 |
});
