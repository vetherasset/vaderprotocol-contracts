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
var Factory = artifacts.require('./Factory')
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

var utils; 
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var router; var factory;
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
  dao = await DAO.new();
  vether = await Vether.new();
  vader = await Vader.new();
  usdv = await USDV.new();
  reserve = await RESERVE.new();
  vault = await VAULT.new();
  router = await Router.new();
  pools = await Pools.new();
  factory = await Factory.new();
})
// acc  | VTH | VADER  | USDV | Anr  |  Ass |
// pool|   0 | 2000 | 2000 | 1000 | 1000 |
// acc1 |   0 | 1000 | 1000 | 1000 | 1000 |

describe("Deploy Rewards", function() {
  it("Should have right reserves", async function() {
    await utils.init(vader.address)
    await dao.init(vether.address, vader.address, usdv.address, reserve.address, 
      vault.address, router.address, pools.address, factory.address, utils.address);
    
    await vader.init(dao.address)
  await usdv.init(vader.address)
    await reserve.init(vader.address)
    await vault.init(vader.address)
    await router.init(vader.address);
    await pools.init(vader.address);
    await factory.init(pools.address);

    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await sleep(2000)
    await dao.finaliseProposal(await dao.proposalCount())
    await dao.newParamProposal("VADER_PARAMS", '1', '90', '0', '0')
    await dao.voteProposal(await dao.proposalCount())
    await sleep(2000)
    await dao.finaliseProposal(await dao.proposalCount())


    anchor = await Anchor.new();
    asset = await Asset.new();

    await vether.transfer(acc1, BN2Str(7407)) 
    await anchor.transfer(acc1, BN2Str(3000))
    await anchor.approve(router.address, BN2Str(one), {from:acc1})

    await vether.approve(vader.address, '7400', {from:acc1})
    await vader.upgrade('8', {from:acc1}) 
    await vader.transfer(acc0, '100', {from:acc1})
    await vader.transfer(acc1, '100')
    
    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await sleep(2000)
    await dao.finaliseProposal(await dao.proposalCount())
    await usdv.convert(BN2Str(1100), {from:acc1})
    // await usdv.withdrawToUSDV('10000', {from:acc1})
    await asset.transfer(acc1, BN2Str(2000))
    await asset.approve(router.address, BN2Str(one), {from:acc1})

    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', {from:acc1})
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})
    
    expect(BN2Str(await vader.getDailyEmission())).to.equal('7');
    expect(BN2Str(await reserve.reserveVADER())).to.equal('15');
    expect(BN2Str(await reserve.reserveUSDV())).to.equal('16');
  });
});

describe("Should do pool rewards", function() {

  it("Swap anchor, get rewards", async function() {
    let r = '15';
    await router.curatePool(anchor.address)
    expect(BN2Str(await reserve.reserveVADER())).to.equal(r);
    expect(await router.emitting()).to.equal(true);
    expect(BN2Str(await utils.getRewardShare(anchor.address, '1'))).to.equal(r);
    expect(BN2Str(await utils.getReducedShare(r, '1'))).to.equal(r);
    expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal('1000');
    let tx = await router.swap('100', vader.address, anchor.address, {from:acc1})
    expect(BN2Str(tx.logs[0].args.amount)).to.equal('22');
    expect(BN2Str(await pools.getBaseAmount(anchor.address))).to.equal('1118');
    expect(BN2Str(await reserve.reserveVADER())).to.equal('0');
    expect(BN2Str(await utils.getRewardShare(anchor.address, '1'))).to.equal('0');
    expect(BN2Str(await utils.getReducedShare('0', '1'))).to.equal('0');

    expect(BN2Str(await reserve.reserveVADER())).to.equal('0');
    expect(BN2Str(await reserve.reserveUSDV())).to.equal('20');
  });

  it("Swap asset, get rewards", async function() {
    let r = '20';
    await dao.newParamProposal("ROUTER_PARAMS", '1', '1', '2', '0')
    await dao.voteProposal(await dao.proposalCount())
    await sleep(2000)
    await dao.finaliseProposal(await dao.proposalCount())
    await router.curatePool(asset.address, {from:acc1})
    expect(BN2Str(await reserve.reserveUSDV())).to.equal(r);
    expect(await router.emitting()).to.equal(true);
    expect(BN2Str(await utils.getRewardShare(asset.address, '1'))).to.equal(r);
    expect(BN2Str(await utils.getReducedShare(r, '1'))).to.equal(r);
    expect(BN2Str(await pools.getBaseAmount(asset.address))).to.equal('1000');
    let tx = await router.swap('100', usdv.address, asset.address, {from:acc1})
    expect(BN2Str(tx.logs[0].args.amount)).to.equal(r);
    expect(BN2Str(await pools.getBaseAmount(asset.address))).to.equal(BN2Str(1100 + +r));
    expect(BN2Str(await reserve.reserveUSDV())).to.equal('0');
    expect(BN2Str(await utils.getRewardShare(asset.address, '1'))).to.equal('0');
    expect(BN2Str(await utils.getReducedShare('0', '1'))).to.equal('0');

    expect(BN2Str(await reserve.reserveVADER())).to.equal('0');
    expect(BN2Str(await reserve.reserveUSDV())).to.equal('0');
  });
});

