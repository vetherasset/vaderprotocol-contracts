const { expect } = require("chai");
const BigNumber = require('bignumber.js');
const {
  encodeParameters,
  advanceBlocks,
  freezeTime,
  mineBlock,
  mineNBlocks
} = require('../Utils/Ethereum');

var Vether = artifacts.require('./Vether');
var Vader = artifacts.require('./Vader');
var USDV = artifacts.require('./USDV');
var RESERVE = artifacts.require('./Reserve');
var VAULT = artifacts.require('./Vault');
var Router = artifacts.require('./Router');
var Lender = artifacts.require('./Lender');
var Pools = artifacts.require('./Pools');
var Factory = artifacts.require('./Factory');
var Utils = artifacts.require('./Utils');
var Governor = artifacts.require('./Governance/GovernorAlpha');
var Timelock = artifacts.require('./Timelock');
var Asset1 = artifacts.require('./Token1');
var Asset2 = artifacts.require('./Token2');
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }
async function enfranchise(contract, delegatee, delegator) {
  await contract.delegate(delegatee, { from: delegator });
}

let ts = 1830384000; // Sat Jan 02 2028 00:00:00 GMT+0000
const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';

var root, acc1, acc2, acc3, acc4, acc5;
var timelock, vether, vader, usdv, reserve, vault;
var router, lender, pools, factory, utils, governor;
var asset1, asset2, anchor;
let targets, values, signatures, callDatas;

before(async function () {
  accounts = await ethers.getSigners();
  root = await accounts[0].getAddress();
  acc1 = await accounts[1].getAddress();
  acc2 = await accounts[2].getAddress();
  acc3 = await accounts[3].getAddress();
  acc4 = await accounts[4].getAddress();
  acc5 = await accounts[5].getAddress();

  vether = await Vether.new();
  vader = await Vader.new();
  usdv = await USDV.new(vader.address);
  reserve = await RESERVE.new();
  vault = await VAULT.new(vader.address);
  router = await Router.new(vader.address);
  lender = await Lender.new(vader.address);
  pools = await Pools.new(vader.address);
  factory = await Factory.new(pools.address);
  utils = await Utils.new(vader.address);

  governor = await Governor.new(
    vether.address,
    vader.address,
    usdv.address,
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    reserve.address,
    utils.address,
    acc5
  );
  timelock = await Timelock.new(governor.address, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);

  asset1 = await Asset1.new();
  asset2 = await Asset2.new();
  anchor = await Anchor.new();
})

describe("GovernorAlpha#queue", function () {
  it("Should deploy right", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    await vether.transfer(acc1, BN2Str(4000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });
    await usdv.approve(vault.address, max, { from: acc1 });
    await anchor.approve(router.address, max, { from: acc1 });
    await asset1.approve(router.address, max, { from: acc1 });
    await asset2.approve(router.address, max, { from: acc1 });

    await vader.flipMinting();
    await vader.upgrade(BN2Str(4), { from: acc1 });
    await usdv.convertToUSDV(BN2Str(4000), { from: acc1 });
    await vault.depositForMember(usdv.address, root, BN2Str(4000), { from: acc1 });
    await vault.delegate(root);
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
      await governor.propose(targets, values, signatures, calldatas, "do nothing", { from: acc1 });
      await mineBlock();

      const proposalId = await governor.latestProposalIds(acc1);
      await advanceBlocks(20000);

      await expect(governor.queue(proposalId)).to.be.revertedWith("proposal can only be queued if it is succeeded");
    });

    it("propose different proposals works", async () => {
      await enfranchise(vault, acc2, root);
      await mineBlock();

      const targets = [vault.address];
      const values = ["0"];
      const signatures = ["getBalanceOf(address)"];
      const calldatas = [encodeParameters(['address'], [root])];
      await governor.propose(targets, values, signatures, calldatas, "do nothing", { from: acc2 });
      await enfranchise(vault, acc3, root);
      await governor.propose(targets, values, signatures, calldatas, "do nothing", { from: acc3 });
      await mineBlock();

      const proposalId1 = await governor.latestProposalIds(acc2);
      const proposalId2 = await governor.latestProposalIds(acc3);
      await governor.castVote(proposalId1, true, { from: acc2 });
      await governor.castVote(proposalId1, true, { from: acc3 });
      await governor.castVote(proposalId1, true, { from: acc1 });
      await governor.castVote(proposalId1, true, { from: root });
      await governor.castVote(proposalId2, true, { from: acc2 });
      await governor.castVote(proposalId2, true, { from: acc3 });
      await governor.castVote(proposalId2, true, { from: acc1 });
      await governor.castVote(proposalId2, true, { from: root });
      await mineNBlocks(10000);
    });

    it("queueing actions in different proposals works", async () => {
      await mineNBlocks(10000);
      const proposalId1 = await governor.latestProposalIds(acc2);
      const proposalId2 = await governor.latestProposalIds(acc3);
      await governor.queue(proposalId1);
      await governor.queue(proposalId2, { from: acc2 });
    });
  });
});