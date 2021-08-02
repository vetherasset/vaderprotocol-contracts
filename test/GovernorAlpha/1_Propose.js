const keccak256 = require('keccak256');
const BigNumber = require('bignumber.js');
const {
  blockNumber,
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

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';

var root, acc1, acc2, acc3, acc4, acc5;
var timelock, vether, vader, usdv, reserve, vault;
var router, lender, pools, factory, utils, governor;
var asset1, asset2, anchor;
let trivialProposal, targets, values, signatures, callDatas;
let proposalBlock, proposalLog;

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

describe("Deploy Governor Alpha", function () {
  it("Should deploy right", async function () {
    await vader.changeGovernorAlpha(governor.address);

    assert.equal(await governor.name(), "Vader Governor Alpha");
    assert.equal(await governor.quorumVotes(), 0);
    assert.equal(await governor.proposalThreshold(), 0);
    assert.equal(await governor.proposalMaxOperations(), 10);
    assert.equal(await governor.votingDelay(), 1);
    assert.equal(await governor.votingPeriod(), 17280);
    assert.equal(await governor.TIMELOCK(), timelock.address);
    assert.equal(await governor.VAULT(), vault.address);
    assert.equal(await governor.GUARDIAN(), acc5);
    assert.equal(await governor.DOMAIN_TYPEHASH(), "0x" + keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)").toString('hex'));
    assert.equal(await governor.BALLOT_TYPEHASH(), "0x" + keccak256("Ballot(uint256 proposalId,bool support)").toString('hex'));

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

    assert.equal((await governor.quorumVotes()).toString(), 160); // 4% of 4000 USDV
    assert.equal((await governor.proposalThreshold()).toString(), 40); // 1% of 4000 USDV

    await mineBlock();

    targets = [root];
    values = ["0"];
    signatures = ["getBalanceOf(address)"];
    callDatas = [encodeParameters(['address'], [acc2])];
    await governor.propose(targets, values, signatures, callDatas, "do nothing");

    proposalBlock = await blockNumber() + 1;
    proposalId = await governor.latestProposalIds(root);
    trivialProposal = await governor.proposals(proposalId);
  });

  describe("simple initialization", () => {
    it("ID is set to a globally unique identifier", async () => {
      assert.deepEqual(trivialProposal.id, proposalId);
    });

    it("Proposer is set to the sender", async () => {
      assert.deepEqual(trivialProposal.proposer, root);
    });

    it("Start block is set to the current block number plus vote delay", async () => {
      assert.equal(trivialProposal.startBlock.toString(), proposalBlock + "");
    });

    it("End block is set to the current block number plus the sum of vote delay and vote period", async () => {
      assert.equal(trivialProposal.endBlock.toString(), proposalBlock + 17280 + "");
    });

    it("ForVotes and AgainstVotes are initialized to zero", async () => {
      assert.equal(trivialProposal.forVotes.toString(), "0");
      assert.equal(trivialProposal.againstVotes.toString(), "0");
    });

    it("Executed and Canceled flags are initialized to false", async () => {
      assert.equal(trivialProposal.canceled, false);
      assert.equal(trivialProposal.executed, false);
    });

    it("ETA is initialized to zero", async () => {
      assert.equal(trivialProposal.eta.toString(), "0");
    });

    it("Targets, Values, Signatures, Calldatas are set according to parameters", async () => {
      const dynamicFields = await governor.getActions(trivialProposal.id);
      assert.deepEqual(dynamicFields.targets, targets);
      assert.deepEqual(dynamicFields.values.join(','), values.join(','));
      assert.deepEqual(dynamicFields.signatures, signatures);
      assert.deepEqual(dynamicFields.calldatas, callDatas);
    });

    it("This function returns the id of the newly created proposal. # proposalId(n) = succ(proposalId(n-1))", async () => {
      await vault.delegate(acc3, { from: root });
      await mineBlock();

      const proposal = await governor.propose(targets, values, signatures, callDatas, "yoot", { from: acc3 });
      proposalLog = proposal.logs[0].args;

      assert.equal(proposalLog.id.toNumber(), trivialProposal.id.toNumber() + 1);
    });

    it("emits log with id and description", async () => {
      await vault.delegate(acc4, { from: root });
      await mineBlock();

      const newProposal = await governor.propose(targets, values, signatures, callDatas, "second proposal", { from: acc4 });
      const newProposalLog = newProposal.logs[0].args;
      const nextBlockNumber = await blockNumber() + 1;

      assert.equal(newProposalLog.id.toNumber(), proposalLog.id.toNumber() + 1);
      assert.deepEqual(newProposalLog.targets, targets);
      assert.deepEqual(newProposalLog.values.join(','), values.join(','));
      assert.deepEqual(newProposalLog.signatures, signatures);
      assert.deepEqual(newProposalLog.calldatas, callDatas);
      assert.equal(newProposalLog.startBlock.toNumber(), nextBlockNumber);
      assert.equal(newProposalLog.endBlock.toNumber(), nextBlockNumber + 17280);
      assert.equal(newProposalLog.description, "second proposal");
      assert.equal(newProposalLog.proposer, acc4);
    });
  });

  describe("This function must revert if", () => {
    it("the length of the values, signatures or calldatas arrays are not the same length", async () => {
      await expect(
        governor.propose(targets.concat(root), values, signatures, callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values.concat(values), signatures, callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values, signatures.concat(signatures), callDatas, "do nothing", { from: acc4 })
      ).to.be.revertedWith("proposal function information arity mismatch");

      await expect(
        governor.propose(targets, values, signatures, callDatas.concat(callDatas), "do nothing", { from: acc4 })
      ).to.be.revertedWith("proposal function information arity mismatch");
    });

    it("or if that length is zero or greater than Max Operations", async () => {
      await expect(
        governor.propose([], [], [], [], "do nothing", { from: acc4 })
      ).to.be.revertedWith("must provide actions");
    });

    describe("Additionally, if there exists a pending or active proposal from the same proposer, we must revert.", () => {
      it("reverts with active", async () => {
        await expect(
          governor.propose(targets, values, signatures, callDatas, "do nothing", { from: acc4 })
        ).to.be.revertedWith("one live proposal per proposer, found an already active proposal");
      });
    });
  });
});



