const { expect } = require("chai");
const keccak256 = require('keccak256');
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')
const {
  address,
  encodeParameters,
  mineBlock
} = require('../Utils/Ethereum');

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
  acc5 = await accounts[5].getAddress()

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

describe("Deploy Governor Alpha", function() {
  it("Should deploy right", async function() {
    await dao.init(vether.address, vader.address, usdv.address, reserve.address, 
      vault.address, router.address, pools.address, factory.address, utils.address, timelock.address);

    assert.equal(await governor.name(), "Vader Governor Alpha");
    assert.equal(await governor.quorumVotes(), 4000e18);
    assert.equal(await governor.proposalThreshold(), 1000e18);
    assert.equal(await governor.proposalMaxOperations(), 10);
    assert.equal(await governor.votingDelay(), 1);
    assert.equal(await governor.votingPeriod(), 17280);
    assert.equal(await governor.timelock(), address(0));
    assert.equal(await governor.vault(), vault.address);
    assert.equal(await governor.guardian(), address(0));
    assert.equal(await governor.DOMAIN_TYPEHASH(), "0x" + keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)").toString('hex'));
    assert.equal(await governor.BALLOT_TYPEHASH(), "0x" + keccak256("Ballot(uint256 proposalId,bool support)").toString('hex'));

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
    
    targets = [root];
    values = ["0"];
    signatures = ["getBalanceOf(address)"];
    callDatas = [encodeParameters(['address'], [acc2])];
    await governor.propose(targets, values, signatures, callDatas, "do nothing");
    
    proposalBlock = +(await web3.eth.getBlockNumber());
    proposalId = await governor.latestProposalIds(root);
    trivialProposal = await governor.proposals(proposalId);
  });

  describe("simple initialization", () => {
    it("ID is set to a globally unique identifier", async () => {
      expect(trivialProposal.id.toString()).to.equal(proposalId.toString());
    });

    it("Proposer is set to the sender", async () => {
      expect(trivialProposal.proposer).to.equal(root);
    });

    it("Start block is set to the current block number plus vote delay", async () => {
      expect(trivialProposal.startBlock.toString()).to.equal(proposalBlock + 1 + "");
    });

    it("End block is set to the current block number plus the sum of vote delay and vote period", async () => {
      expect(trivialProposal.endBlock.toString()).to.equal(proposalBlock + 1 + 17280 + "");
    });

    it("ForVotes and AgainstVotes are initialized to zero", async () => {
      expect(trivialProposal.forVotes.toString()).to.equal("0");
      expect(trivialProposal.againstVotes.toString()).to.equal("0");
    });

    xit("Voters is initialized to the empty set", async () => {
      test.todo('mmm probably nothing to prove here unless we add a counter or something');
    });

    it("Executed and Canceled flags are initialized to false", async () => {
      expect(trivialProposal.canceled).to.equal(false);
      expect(trivialProposal.executed).to.equal(false);
    });

    it("ETA is initialized to zero", async () => {
      expect(trivialProposal.eta.toString()).to.equal("0");
    });

    it("Targets, Values, Signatures, Calldatas are set according to parameters", async () => {
      let dynamicFields = await governor.getActions(trivialProposal.id);
      expect(dynamicFields.targets.join(',')).to.equal(targets.join(','));
      expect(dynamicFields.values.join(',')).to.equal(values.join(','));
      expect(dynamicFields.signatures.join(',')).to.equal(signatures.join(','));
      expect(dynamicFields.calldatas.join(',')).to.equal(callDatas.join(','));
    });

    it("This function returns the id of the newly created proposal. # proposalId(n) = succ(proposalId(n-1))", async () => {
      await vault.delegate(acc3, { from: root });

      await mineBlock();
      let proposal = await governor.propose(targets, values, signatures, callDatas, "yoot", { from: acc3 });
      proposalLog = proposal.logs[0].args;
      expect(proposalLog.id.toNumber()).to.equal(trivialProposal.id.toNumber() + 1);
    });

    it("emits log with id and description", async () => {
      await vault.delegate(acc4, { from: root });

      await mineBlock();
      let newProposal = await governor.propose(targets, values, signatures, callDatas, "second proposal", { from: acc4 });
      const newProposalLog = newProposal.logs[0].args;

      expect(newProposalLog.id.toNumber()).to.equal(proposalLog.id.toNumber() + 1)
      expect(newProposalLog.targets.join(',')).to.equal(targets.join(','))
      expect(newProposalLog.values.join(',')).to.equal(values.join(','))
      expect(newProposalLog.signatures.join(',')).to.equal(signatures.join(','))
      expect(newProposalLog.calldatas.join(',')).to.equal(callDatas.join(','))
      expect(newProposalLog.startBlock.toNumber()).to.equal(50)
      expect(newProposalLog.endBlock.toNumber()).to.equal(17330)
      expect(newProposalLog.description).to.equal("second proposal")
      expect(newProposalLog.proposer).to.equal(acc4)
    });
  });

  describe("This function must revert if", () => {
    it("the length of the values, signatures or calldatas arrays are not the same length", async () => {
      await expect(
        governor.propose(targets.concat(root), values, signatures, callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("GovernorAlpha::propose: proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values.concat(values), signatures, callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("GovernorAlpha::propose: proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values, signatures.concat(signatures), callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("GovernorAlpha::propose: proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values, signatures, callDatas.concat(callDatas), "do nothing", { from: acc4 })
      ).to.be.revertedWith("GovernorAlpha::propose: proposal function information arity mismatch");
    });

    it("or if that length is zero or greater than Max Operations", async () => {
      await expect(
        governor.propose([], [], [], [], "do nothing", { from: acc4 })
      ).to.be.revertedWith("GovernorAlpha::propose: must provide actions");
    });

    describe("Additionally, if there exists a pending or active proposal from the same proposer, we must revert.", () => {
      it("reverts with active", async () => {
        await expect(
          governor.propose(targets, values, signatures, callDatas, "do nothing", { from: acc4 })
        ).to.be.revertedWith("GovernorAlpha::propose: one live proposal per proposer, found an already active proposal");
      });
    });
  });
});



