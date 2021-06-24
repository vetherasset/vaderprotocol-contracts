const { expect } = require("chai");
const BigNumber = require('bignumber.js');
const {
  encodeParameters,
  mineBlock
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
  utils = await Utils.new(vader.address);
  usdv = await USDV.new(vader.address);
  reserve = await RESERVE.new();
  vault = await VAULT.new(vader.address);
  router = await Router.new(vader.address);
  lender = await Lender.new(vader.address);
  pools = await Pools.new(vader.address);
  factory = await Factory.new(pools.address);

  governor = await Governor.new(
    vether.address,
    vader.address,
    usdv.address,
    reserve.address,
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    utils.address,
    acc5
  );
  timelock = await Timelock.new(governor.address, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);

  asset1 = await Asset1.new();
  asset2 = await Asset2.new();
  anchor = await Anchor.new();
})

describe("governorAlpha#castVote", function () {
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
    await vader.upgrade(BN2Str(4), { from: acc1 })
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

  describe("We must revert if:", () => {
    it("There does not exist a proposal with matching proposal id where the current block number is between the proposal's start block (exclusive) and end block (inclusive)", async () => {
      await expect(governor.castVote(proposalId, true)).to.be.revertedWith("revert GovernorAlpha::_castVote: voting is closed");
    });

    it("Such proposal already has an entry in its voters set matching the sender", async () => {
      await mineBlock();
      await governor.castVote(proposalId, true, { from: acc4 });
      await expect(governor.castVote(proposalId, true, { from: acc4 })).to.be.revertedWith("revert GovernorAlpha::_castVote: voter already voted");
    });
  });

  describe("Otherwise", () => {
    it("we add the sender to the proposal's voters set", async () => {
      assert.equal((await governor.getReceipt(proposalId, acc2)).hasVoted, false);
      await governor.castVote(proposalId, true, { from: acc2 });
      assert.equal((await governor.getReceipt(proposalId, acc2)).hasVoted, true);
    });

    describe("and we take the balance returned by GetPriorVotes for the given sender and the proposal's start block, which may be zero,", () => {
      let actor; // an account that will propose, receive tokens, delegate to self, and vote on own proposal

      it("and we add that ForVotes", async () => {
        actor = acc1;
        await enfranchise(vault, actor, root);
        await governor.propose(targets, values, signatures, callDatas, "do nothing", { from: actor });
        proposalId = await governor.latestProposalIds(actor);
        await mineBlock();

        await governor.castVote(proposalId, true, { from: actor });
        const afterFors = (await governor.proposals(proposalId)).forVotes;

        assert.equal(afterFors.toString(), BN2Str(4000));
      })

      it("or AgainstVotes corresponding to the caller's support flag.", async () => {
        actor = acc3;
        await enfranchise(vault, actor, root);
        await governor.propose(targets, values, signatures, callDatas, "do nothing", { from: actor });
        proposalId = await governor.latestProposalIds(actor);;
        await mineBlock();

        await governor.castVote(proposalId, false, { from: actor });
        const afterAgainsts = (await governor.proposals(proposalId)).againstVotes;

        assert.equal(afterAgainsts.toString(), BN2Str(4000));
      });
    });

    describe('castVoteBySig', () => {
      it('reverts if the signatory is invalid', async () => {
        await expect(governor.castVoteBySig(proposalId, false, 0, '0xbad', '0xbad')).to.be.revertedWith("revert GovernorAlpha::castVoteBySig: invalid signature");
      });
    });
  });
});



