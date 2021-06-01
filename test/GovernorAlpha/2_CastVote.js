const { expect } = require("chai");
const keccak256 = require('keccak256');
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')
const {
  address,
  etherMantissa,
  encodeParameters,
  mineBlock,
  unlockedAccount
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
  timelock = await Timelock.new(acc4, 2 * 24 * 60 * 60);
  governor = await Governor.new(address(0), vault.address, address(0));

  asset = await Asset.new();
  anchor = await Anchor.new();
})

describe("governorAlpha#castVote", function() {
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

  describe("We must revert if:", () => {
    it("There does not exist a proposal with matching proposal id where the current block number is between the proposal's start block (exclusive) and end block (inclusive)", async () => {
      await expect(
        governor.castVote(proposalId, true)
      ).to.be.revertedWith("revert GovernorAlpha::_castVote: voting is closed");
    });

    it("Such proposal already has an entry in its voters set matching the sender", async () => {
      await mineBlock();
      await mineBlock();

      await governor.castVote(proposalId, true, { from: acc4 });
      await expect(
        governor.castVote(proposalId, true, { from: acc4 })
      ).to.be.revertedWith("revert GovernorAlpha::_castVote: voter already voted");
    });
  });

  describe("Otherwise", () => {
    it("we add the sender to the proposal's voters set", async () => {
      expect((await governor.getReceipt(proposalId, acc2)).hasVoted).to.equal(false);
      await governor.castVote(proposalId, true, { from: acc2 });
      expect((await governor.getReceipt(proposalId, acc2)).hasVoted).to.equal(true);
    });

    describe("and we take the balance returned by GetPriorVotes for the given sender and the proposal's start block, which may be zero,", () => {
      let actor; // an account that will propose, receive tokens, delegate to self, and vote on own proposal

      it("and we add that ForVotes", async () => {
        actor = acc1;
        await enfranchise(vault, actor, root);

        await governor.propose(targets, values, signatures, callDatas, "do nothing", { from: actor });
        proposalId = await governor.latestProposalIds(actor);

        let beforeFors = (await governor.proposals(proposalId)).forVotes;
        await mineBlock();
        await governor.castVote(proposalId, true, { from: actor });

        let afterFors = (await governor.proposals(proposalId)).forVotes;
        expect(afterFors.toString()).to.equal(new BigNumber(4000e18).toFixed());
      })

      it("or AgainstVotes corresponding to the caller's support flag.", async () => {
        actor = acc3;
        await enfranchise(vault, actor, root);

        await governor.propose(targets, values, signatures, callDatas, "do nothing", { from: actor });
        proposalId = await governor.latestProposalIds(actor);;

        let beforeAgainsts = (await governor.proposals(proposalId)).againstVotes;
        await mineBlock();
        await governor.castVote(proposalId, false, { from: actor });

        let afterAgainsts = (await governor.proposals(proposalId)).againstVotes;
        expect(afterAgainsts.toString()).to.equal(new BigNumber(4000e18).toFixed());
      });
    });

    describe('castVoteBySig', () => {
      const Domain = (governor) => ({
        name: 'Vader Governor Alpha',
        chainId: 1,
        verifyingContract: governor._address
      });
      const Types = {
        Ballot: [
          { name: 'proposalId', type: 'uint256' },
          { name: 'support', type: 'bool' }
        ]
      };

      it('reverts if the signatory is invalid', async () => {
        await expect(governor.castVoteBySig(proposalId, false, 0, '0xbad', '0xbad')).to.be.revertedWith("revert GovernorAlpha::castVoteBySig: invalid signature");
      });
    });
  });
});



