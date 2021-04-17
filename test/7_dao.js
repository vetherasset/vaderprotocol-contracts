const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var USDV = artifacts.require('./USDV')
var Vault = artifacts.require('./Vault')
var Router = artifacts.require('./Router')
var Asset = artifacts.require('./Token1')
var Anchor = artifacts.require('./Token2')
var DAO = artifacts.require('./DAO')

const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var usdv; var vault; var anchor; var asset; var rotuer; var dao;
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
  dao = await DAO.new();

  asset = await Asset.new();
  anchor0 = await Anchor.new();

})

describe("Deploy DAO", function() {
  it("Should deploy right", async function() {
    await utils.init(vault.address)
    await vader.init(vether.address, usdv.address, utils.address)
    await usdv.init(vader.address, router.address)
    await router.init(vader.address, usdv.address, vault.address);
    await vault.init(vader.address, usdv.address, router.address);
    await dao.init(vader.address, usdv.address);
    
    await vether.approve(vader.address, '6000', {from:acc0})
    await vader.upgrade('1000', {from:acc0}) 

    await vether.transfer(acc1, BN2Str(6006)) 
    await vether.approve(vader.address, '6000', {from:acc1})
    await vader.upgrade('1000', {from:acc1}) 

    await usdv.convertToUSDV('1000', {from:acc0})
    await usdv.convertToUSDV('1000', {from:acc1})

    await usdv.deposit('100', {from:acc0})
    await usdv.deposit('100', {from:acc1})

    await vader.changeDAO(dao.address, {from:acc0})

    // await anchor0.transfer(acc1, BN2Str(2000))
    // await anchor0.approve(router.address, BN2Str(one), {from:acc1})
    
  });
});

describe("DAO Functions", function() {
  it("It should GRANT", async () => {
      await usdv.transfer(usdv.address, '100');
      assert.equal(BN2Str(await usdv.reserveUSDV()), '100')
      await dao.newGrantProposal(acc3, '10', { from: acc1 })
      let proposalCount = BN2Str(await dao.proposalCount())
      await dao.voteProposal(proposalCount, { from: acc0 })
      await dao.voteProposal(proposalCount, { from: acc1 })
      await sleep(100)
      let balanceBefore = getBN(await usdv.balanceOf(acc3))
      await dao.finaliseProposal(proposalCount)
      let balanceAfter = getBN(await usdv.balanceOf(acc3))
      assert.equal(BN2Str(balanceAfter.minus(balanceBefore)), '10')
  })
  it("It should cahnge Utils", async () => {
    assert.equal(await vader.UTILS(), utils.address)
    let utils2 = await Utils.new();
    await dao.newAddressProposal(utils2.address, 'UTILS', { from: acc1 })
    let proposalCount = BN2Str(await dao.proposalCount())
    await dao.voteProposal(proposalCount, { from: acc0 })
    await dao.voteProposal(proposalCount, { from: acc1 })
    await sleep(2000)
    await dao.finaliseProposal(proposalCount)
    assert.equal(await vader.UTILS(), utils2.address)
})
})



