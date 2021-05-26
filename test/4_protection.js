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
const truffleAssert = require('truffle-assertions');
const { VoidSigner } = require("@ethersproject/abstract-signer");

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

async function mine() {
  await ethers.provider.send('evm_mine')
}

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

var utils;
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var router; var lender; var factory;
var anchor0; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5;
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
  pools = await Pools.new(vader.address);
  factory = await Factory.new(pools.address);
})
// acc  | VTH | VADER  | USDV | Anr  |  Ass |
// pool|   0 | 2000 | 2000 | 1000 | 1000 |
// acc1 |   0 | 1000 | 1000 | 1000 | 1000 |

describe("Deploy Protection", function() {
  it("Should have right reserves", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)

    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())

    anchor = await Anchor.new();
    asset = await Asset.new();

    await vether.transfer(acc1, BN2Str(7407))
    await anchor.transfer(acc1, BN2Str(2000))

    await vader.approve(usdv.address, max, {from:acc1})
    await anchor.approve(router.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc1})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})

    await vader.upgrade('8', {from:acc1})
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})

    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await dao.newParamProposal("VADER_PARAMS", '1', '1', '0', '0')
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    await vader.convertToUSDV('2000', {from:acc1})

    await asset.transfer(acc1, '2000')
    await asset.approve(router.address, BN2Str(one), {from:acc1})
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})

    await vader.transfer(acc0, '100', {from:acc1})
    await vader.transfer(acc1, '100')
    await vader.transfer(acc0, '100', {from:acc1})
    await usdv.transfer(acc0, '100', {from:acc1})

    // console.log(BN2Str(await vader.getDailyEmission()))

    expect(BN2Str(await vader.getDailyEmission())).to.equal('6800');
    expect(BN2Str(await reserve.reserveVADER())).to.equal('800');
    expect(BN2Str(await vader.balanceOf(reserve.address))).to.equal('800');
    // await dao.newActionProposal("EMISSIONS")
    // await dao.voteProposal(await dao.proposalCount())
    // await mine()
    // await dao.finaliseProposal(await dao.proposalCount())
  });
});

describe("Should do IL Protection", function() {
  it("Core math", async function() {
    expect(BN2Str(await utils.calcCoverage('123', '456', '789', '0'))).to.equal('0'); // T1 == 0, so calculation can't continue
    expect(BN2Str(await utils.calcCoverage('100', '20', '100', '100'))).to.equal('0'); // deposit less than redemption

    expect(BN2Str(await utils.calcCoverage('1000', '1000', '1100', '918'))).to.equal('0');
    expect(BN2Str(await utils.calcCoverage('1000', '1000', '1200', '820'))).to.equal('63');

    expect(BN2Str(await utils.calcCoverage('100', '1000', '75', '2000'))).to.equal('0');
    expect(BN2Str(await utils.calcCoverage('100', '1000', '20', '2000'))).to.equal('70');
  });
  it("Small swap, need protection", async function() {
    await router.curatePool(anchor.address)
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('1000');
    expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal('1000');
    expect(BN2Str(await pools.getTokenAmount(anchor.address))).to.equal('1000');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('4900');

    for(let i = 0; i<9; i++){
      await router.swap('100', anchor.address, vader.address, {from:acc1})
    }
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('100');
    expect(BN2Str(await pools.getTokenAmount(anchor.address))).to.equal('1900');
    expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal('554');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('5346');

    expect(BN2Str(await router.mapMemberToken_depositBase(acc1, anchor.address))).to.equal('1000');
    expect(BN2Str(await router.mapMemberToken_depositToken(acc1, anchor.address))).to.equal('1000');
    let coverage = await utils.getCoverage(acc1, anchor.address)
    expect(BN2Str(coverage)).to.equal('183');
    expect(BN2Str(await utils.getProtection(acc1, anchor.address, "10000", '1'))).to.equal('183');
    // let reserveVADER = BN2Str(await reserve.reserveVADER())
    expect(BN2Str(await router.getILProtection(acc1, vader.address, anchor.address, '10000'))).to.equal('183');
    // expect(BN2Str(await reserve.reserveVADER())).to.equal('8');
    // expect(BN2Str(await router.getILProtection(acc1, vader.address, anchor.address, '10000'))).to.equal('8');
  });

  it("RECEIVE protection on 50% ", async function() {
    expect(BN2Str(await reserve.reserveVADER())).to.equal('800');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('5346');
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('100');

    let share = await utils.getMemberShare('5000', anchor.address, acc1)

    expect(BN2Str(share.units)).to.equal('500');
    expect(BN2Str(share.outputBase)).to.equal('277');
    expect(BN2Str(share.outputToken)).to.equal('950');

    let tx = await router.removeLiquidity(vader.address, anchor.address, '5000', {from:acc1})

    expect(BN2Str(await reserve.reserveVADER())).to.equal('709');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal('5668'); //+322
    expect(BN2Str(await anchor.balanceOf(acc1))).to.equal('1049'); //+950

    expect(BN2Str(await pools.getMemberUnits(anchor.address, acc1))).to.equal('536');
  });

  it("Small swap, need protection on Asset", async function() {
    // await dao.newActionProposal("EMISSIONS")
    // await dao.voteProposal(await dao.proposalCount())
    // await mine()
    // await dao.finaliseProposal(await dao.proposalCount())
    // expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
    // expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
    await dao.newParamProposal("ROUTER_PARAMS", '1', '1', '2', '0')
    await dao.voteProposal(await dao.proposalCount())
    await mine()
    await dao.finaliseProposal(await dao.proposalCount())
    expect(await pools.isAsset(asset.address)).to.equal(true);
    await router.curatePool(asset.address)
    expect(await router.isCurated(asset.address)).to.equal(true);
    expect(BN2Str(await usdv.balanceOf(acc1))).to.equal('900');
    for(let i = 0; i<9; i++){
      await router.swap('100', asset.address, usdv.address, {from:acc1})
    }

    expect(BN2Str(await router.mapMemberToken_depositBase(acc1, asset.address))).to.equal('1000');
    expect(BN2Str(await router.mapMemberToken_depositToken(acc1, asset.address))).to.equal('1000');
    let coverage = await utils.getCoverage(acc1, asset.address)
    expect(BN2Str(coverage)).to.equal('183');
    expect(BN2Str(await utils.getProtection(acc1, asset.address, "10000", '1'))).to.equal('183');
    expect(Number(await router.getILProtection(acc1, usdv.address, asset.address, '10000'))).to.be.lessThanOrEqual(Number(await reserve.reserveVADER()));
  });
});
