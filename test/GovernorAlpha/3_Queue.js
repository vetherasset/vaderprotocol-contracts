const { expect } = require("chai");
const keccak256 = require('keccak256');
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')
const {
  blockNumber,
  encodeParameters,
  advanceBlocks,
  freezeTime,
  mineBlock
} = require('../Utils/Ethereum');
const EIP712 = require('../Utils/EIP712');

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
var Asset2 = artifacts.require('./Token2')
var Anchor = artifacts.require('./Token2')
var DAO = artifacts.require('./DAO')
var Synth = artifacts.require('./Synth')
var Governor = artifacts.require('./Governance/GovernorAlpha')
var Timelock = artifacts.require('./Timelock')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }
async function setNextBlockTimestamp(ts) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [ts])
  await ethers.provider.send('evm_mine')
}
async function enfranchise(contract, delegatee, delegator) {
  await contract.delegate(delegatee, { from: delegator });
}

const ts0 = 1830384000 // Sat Jan 02 2028 00:00:00 GMT+0000
const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

var utils; 
var dao; var vader; var vether; var usdv;
var reserve; var vault; var pools; var anchor; var asset; var router; var factory;
var governor; var timelock; var asset2;
var anchor; var anchor1; var anchor2; var anchor3; var anchor4;  var anchor5; 
var acc0; var acc1; var acc2; var acc3; var acc4; var root;
let trivialProposal, targets, values, signatures, callDatas;
let proposalBlock; let proposalLog;
const one = 10**18

before(async function() {
  accounts = await ethers.getSigners();
  root = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()
  acc4 = await accounts[4].getAddress()
  acc5 = new ethers.Wallet("0x1da6847600b0ee25e9ad9a52abbd786dd2502fa4005dd5af9310b7cc7a3b25db");

  dao = await DAO.new();
  vether = await Vether.new();
  vader = await Vader.new();
  utils = await Utils.new(vader.address);
  usdv = await USDV.new(vader.address);
  reserve = await RESERVE.new();
  vault = await VAULT.new(vader.address);
  router = await Router.new(vader.address);
  pools = await Pools.new(vader.address);
  factory = await Factory.new(pools.address);
  timelock = await Timelock.new(root, 2 * 24 * 60 * 60);
  governor = await Governor.new(timelock.address, vault.address, root);

  asset = await Asset.new();
  anchor = await Anchor.new();
})

describe("GovernorAlpha#queue", function() {
  it("Should deploy right", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address, 
      vault.address, router.address, pools.address, factory.address, utils.address, timelock.address);

    await vader.changeDAO(dao.address)
    await reserve.init(vader.address)
    
    asset = await Asset.new();
    asset2 = await Asset2.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, BN2Str(4000e18)) 
    await anchor.transfer(acc1, BN2Str(2000))

    await vader.approve(usdv.address, max, {from:acc1})
    await vether.approve(vader.address, max, {from:acc1})
    await vader.approve(router.address, max, {from:acc1})
    await usdv.approve(router.address, max, {from:acc1})
    await usdv.approve(vault.address, max, {from:acc1})

    await anchor.approve(router.address, max, {from:acc1})
    await asset.approve(router.address, max, {from:acc1})
    await asset2.approve(router.address, max, {from:acc1})

    await vader.upgrade(BN2Str(4e18), {from:acc1}) 
    await asset.transfer(acc1, '4000')
    await asset2.transfer(acc1, '4000')

    await dao.newActionProposal("MINTING")
    await dao.voteProposal(await dao.proposalCount())
    await setNextBlockTimestamp(ts0 + 1*15)
    await dao.finaliseProposal(await dao.proposalCount())
    await vader.convertToUSDV(BN2Str(4000e18), {from:acc1})
    await vault.depositForMember(usdv.address, root, BN2Str(4000e18), {from:acc1});
    await vault.delegate(root);
    // await setNextBlockTimestamp(ts0 + 5*15)
    
    await mineBlock();
    await mineBlock();
    
    targets = [acc1];
    values = ["0"];
    signatures = ["getBalanceOf(address)"];
    callDatas = [encodeParameters(['address'], [acc1])];
    await governor.propose(targets, values, signatures, callDatas, "do nothing");
    
    proposalId = await governor.latestProposalIds(root);
  });

  describe("overlapping actions", () => {
    it("reverts on queueing action is not succeeded", async () => {
      await enfranchise(vault, acc1, root);
      await mineBlock();

      const targets = [vault.address, vault.address];
      const values = ["0", "0"];
      const signatures = ["getBalanceOf(address)", "getBalanceOf(address)"];
      const calldatas = [encodeParameters(['address'], [root]), encodeParameters(['address'], [root])];
      await governor.propose(targets, values, signatures, calldatas, "do nothing", {from: acc1});
      await mineBlock();
      let proposalId = await governor.latestProposalIds(acc1);
      const txVote1 = await governor.castVote(proposalId, true, {from: acc1});
      await advanceBlocks(20000);

      await expect(
        governor.queue(proposalId)
      ).to.be.revertedWith("GovernorAlpha::queue: proposal can only be queued if it is succeeded");
    });

    it("reverts on queueing overlapping actions in different proposals, works if waiting", async () => {
      await enfranchise(vault, acc2, root);
      await mineBlock();

      const targets = [vault.address];
      const values = ["0"];
      const signatures = ["getBalanceOf(address)"];
      const calldatas = [encodeParameters(['address'], [root])];
      await governor.propose(targets, values, signatures, calldatas, "do nothing", {from: acc2});
      await enfranchise(vault, acc3, root);
      await governor.propose(targets, values, signatures, calldatas, "do nothing", {from: acc3});
      await mineBlock();

      let proposalId1 = await governor.latestProposalIds(acc2);
      let proposalId2 = await governor.latestProposalIds(acc3);
      await governor.castVote(proposalId1, true, {from: acc2});
      await governor.castVote(proposalId1, true, {from: acc3});
      await governor.castVote(proposalId1, true, {from: acc1});
      await governor.castVote(proposalId1, true, {from: root});
      await governor.castVote(proposalId2, true, {from: acc2});
      await governor.castVote(proposalId2, true, {from: acc3});
      await governor.castVote(proposalId2, true, {from: acc1});
      await governor.castVote(proposalId2, true, {from: root});
      console.log(await blockNumber())
      const mineBlockCalls = [];
      for (let i = 0; i < 20000; i += 1) {
        mineBlockCalls.push(mineBlock());
      }
      await Promise.all(mineBlockCalls);

      console.log(await blockNumber())
      console.log((await governor.state(proposalId1)).toString())

      await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts0 + 2 * 24 * 60 * 60 + 30000);
      await expect(
        governor.queue(proposalId2)
      ).to.be.revertedWith("Timelock::queueTransaction: Call must come from admin.");

      await freezeTime(101);
    });
  });
});



