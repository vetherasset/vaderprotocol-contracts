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
var DAO = artifacts.require('./DAO')
var Synth = artifacts.require('./Synth')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

async function setNextBlockTimestamp(ts) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [ts])
  await ethers.provider.send('evm_mine')
}
const ts0 = 1830384000 // Sat Jan 02 2028 00:00:00 GMT+0000

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

var utils; 
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var router; var lender; var factory;
var dao;
var anchor; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5; 
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
  dao = await DAO.new();

  asset = await Asset.new();
  anchor = await Anchor.new();

})

describe("Deploy DAO", function() {
  it("Should deploy right", async function() {
     
    await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);
 
    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)
    
    await vader.approve(usdv.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc0})

    await vader.approve(router.address, max, {from:acc0})
    await usdv.approve(router.address, max, {from:acc0})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})

    await asset.approve(router.address, max, {from:acc1})

    await vader.upgrade('5', {from:acc0}) 

    await dao.newActionProposal("EMISSIONS")
    await dao.voteProposal(await dao.proposalCount())
    await setNextBlockTimestamp(ts0 + 1*15)
    await dao.finaliseProposal(await dao.proposalCount())
    await dao.newParamProposal("VADER_PARAMS", '1', '90', '0', '0')
    await dao.voteProposal(await dao.proposalCount())
    await setNextBlockTimestamp(ts0 + 2*15)
    await dao.finaliseProposal(await dao.proposalCount())

    await vader.transfer(acc1, ('100'), {from:acc0})
    await vader.transfer(acc0, ('100'), {from:acc1})

    await vader.transfer(acc1, '2000') 
    await asset.transfer(acc1, '1110') 

    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await setNextBlockTimestamp(ts0 + 3*15)
    await dao.finaliseProposal(await dao.proposalCount())

    await vader.convertToUSDV('2000', {from:acc0})
    await vader.convertToUSDV('2000', {from:acc1})
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', {from:acc1})

    await pools.deploySynth(asset.address)
    await router.swapWithSynths('110', usdv.address, false, asset.address, true, {from:acc0})
    await router.swapWithSynths('110', usdv.address, false, asset.address, true, {from:acc1})

    let synth = await Synth.at(await factory.getSynth(asset.address));

    await synth.approve(vault.address, max, {from:acc0})
    await synth.approve(vault.address, max, {from:acc1})

    await vault.deposit(synth.address, '10', {from:acc0})
    await vault.deposit(synth.address, '10', {from:acc1})

  });
});

describe("DAO Functions", function() {
  it("It should GRANT", async () => {
      await usdv.transfer(vault.address, '100', {from:acc1});
      assert.equal(BN2Str(await reserve.reserveUSDV()), '173')
      await dao.newGrantProposal(acc3, '10', { from: acc1 })
      let proposalCount = BN2Str(await dao.proposalCount())
      await dao.voteProposal(proposalCount, { from: acc0 })
      await dao.voteProposal(proposalCount, { from: acc1 })
      await setNextBlockTimestamp(ts0 + 5*15)
      let balanceBefore = getBN(await usdv.balanceOf(acc3))
      await dao.finaliseProposal(proposalCount)
      let balanceAfter = getBN(await usdv.balanceOf(acc3))
      assert.equal(BN2Str(balanceAfter.minus(balanceBefore)), '10')
  })
  it("It should cahnge Utils", async () => {
    assert.equal(await dao.UTILS(), utils.address)
    let utils2 = await Utils.new(vader.address);
    await dao.newAddressProposal('UTILS', utils2.address, { from: acc1 })
    let proposalCount = BN2Str(await dao.proposalCount())
    await dao.voteProposal(proposalCount, { from: acc0 })
    await dao.voteProposal(proposalCount, { from: acc1 })
    await setNextBlockTimestamp(ts0 + 6*15)
    await dao.finaliseProposal(proposalCount)
    assert.equal(await dao.UTILS(), utils2.address)
})
})



