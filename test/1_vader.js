const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var DAO = artifacts.require('./DAO')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var RESERVE = artifacts.require('./Reserve')
var VAULT = artifacts.require('./Vault')
var Router = artifacts.require('./Router')
var Lender = artifacts.require('./Lender')
var Factory = artifacts.require('./Factory')
var POOLS = artifacts.require('./Pools')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

async function mine() {
  await ethers.provider.send('evm_mine')
}

var utils;
var dao; var vader; var vether; var usdv;
var reserve; var vault; var router; var lender; var factory;
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
  pools = await POOLS.new(vader.address);
  factory = await Factory.new(pools.address);

  await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

  await vader.changeDAO(dao.address)
  await reserve.init(vader.address)

  await vether.transfer(acc1, '1')
// acc  | VTH | VADER  |
// acc0 |   0 |    0 |
// acc1 |1001 |    0 |
})

describe("Deploy Vader", function() {
  it("Should deploy", async function() {
    expect(await vader.name()).to.equal("VADER PROTOCOL TOKEN");
    expect(await vader.symbol()).to.equal("VADER");
    expect(BN2Str(await vader.decimals())).to.equal('18');
    expect(BN2Str(await vader.totalSupply())).to.equal('0');
    expect(BN2Str(await vader.maxSupply())).to.equal(BN2Str(2000000000 * one));
    expect(BN2Str(await vader.emissionCurve())).to.equal('10');
    expect(await vader.emitting()).to.equal(false);
    expect(BN2Str(await vader.secondsPerEra())).to.equal('1');
    // console.log(BN2Str(await vader.nextEraTime()));
    expect(await vader.DAO()).to.equal(dao.address);
    expect(await vader.burnAddress()).to.equal("0x0111011001100001011011000111010101100101");
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('0'));
  });
});

describe("Upgrade", function() {
  it("Should upgrade acc1", async function() {
    await vether.approve(vader.address, '10000000000000000000000', {from:acc1})
    await vader.upgrade(1, {from:acc1})
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vether.balanceOf(acc1))).to.equal(BN2Str(0));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('100'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |    0 |
// acc1 |   0 | 1000 |
});

describe("Be a valid ERC-20", function() {
  it("Should transfer From fail", async function() {
    expect(BN2Str(await vader.allowance(acc1, acc0))).to.equal('0');
    await truffleAssert.reverts(vader.transferFrom(acc1, acc0, "100", {from:acc0}))
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('0');
  });

  it("Should transfer From", async function() {
    await vader.approve(acc0, "100", {from:acc1})
    expect(BN2Str(await vader.allowance(acc1, acc0))).to.equal('100');
    await vader.transferFrom(acc1, acc0, "100", {from:acc0})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('100');
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  100 |
// acc1 |   0 |  1000 |

  it("Should transfer", async function() {
    await vader.transfer(acc0, "100", {from:acc1})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('200');
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  200 |
// acc1 |   0 |  800 |

  it("Should burn", async function() {
    await vader.burn("100", {from:acc0})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('100');
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str('900'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  100 |
// acc1 |   0 |  800 |

  it("Should burn from", async function() {
    await vader.approve(acc1, "100", {from:acc0})
    expect(BN2Str(await vader.allowance(acc0, acc1))).to.equal('100');
    await vader.burnFrom(acc0, "100", {from:acc1})
    expect(BN2Str(await vader.balanceOf(acc0))).to.equal('0');
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str('800'));
  });
// acc  | VTH | VADER  |
// acc0 |   0 |  0   |
// acc1 |   0 |  800 |
});

describe("DAO Functions", function() {
  it("Non-DAO fails", async function() {
    await truffleAssert.reverts(vader.flipEmissions({from:acc1}))
  });

  it("DAO setParams", async function() {
    await dao.newParamProposal("VADER_PARAMS", '1', '1', '0', '0')
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    expect(BN2Str(await vader.secondsPerEra())).to.equal('1');
    expect(BN2Str(await vader.emissionCurve())).to.equal('1');
  });

  it("DAO start emitting", async function() {
    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    expect(await vader.emitting()).to.equal(true);
  });
});

describe("Emissions", function() {
  it("Should emit properly", async function() {
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('800'));
    await vader.transfer(acc0, BN2Str(200), {from:acc1})
    await vader.transfer(acc1, BN2Str(100), {from:acc0})
    expect(BN2Str(await vader.balanceOf(reserve.address))).to.equal(BN2Str('2400'));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('3200'));
    await vader.transfer(acc0, BN2Str(100), {from:acc1})
    expect(BN2Str(await vader.balanceOf(reserve.address))).to.equal(BN2Str('5600'));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('6400'));
  });
});

describe("FeeOnTransfer", function() {
  it("Should set up fees", async function() {
    expect(BN2Str(await vader.feeOnTransfer())).to.equal('0');
    expect(BN2Str(await vader.totalSupply())).to.equal(BN2Str(6400));
    expect(BN2Str(await vether.balanceOf(acc0))).to.equal('999999999999999999999999');
    await vether.approve(vader.address, '999999999999999999999999', {from:acc0})
    await vader.upgrade('999999999999999999999999', {from:acc0})
    await dao.newParamProposal("VADER_PARAMS", '1', '2024', '0', '0')
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('494071146245059288537546'));
    expect(BN2Str(await vader.totalSupply())).to.equal('1000000000000000000000005400');
    await vader.transfer(acc1, BN2Str(100), {from:acc0})
    expect(BN2Str(await vader.totalSupply())).to.equal('1000494071146245059288542946');
    expect(BN2Str(await vader.maxSupply())).to.equal(BN2Str(2 * 10**9 * 10 ** 18));
    expect(BN2Str(await vader.feeOnTransfer())).to.equal('50');
  });

  it("Should charge fees", async function() {
    let tx = await vader.transfer(acc1, BN2Str(10000), {from:acc0})
    expect(BN2Str(tx.logs[0].args.value)).to.equal('50');
    expect(BN2Str(tx.logs[1].args.value)).to.equal('9950');
  });
});
