const BigNumber = require('bignumber.js');
const {
  encodeParameters,
  etherUnsigned,
  freezeTime,
  setNextBlockTimestamp,
  keccak256,
  currentBlockTimestamp
} = require('./Utils/Ethereum');

var Timelock = artifacts.require('./Timelock');

const oneWeekInSeconds = etherUnsigned(7 * 24 * 60 * 60);
const zero = etherUnsigned(0);
const gracePeriod = oneWeekInSeconds.multipliedBy(2);
let ts = 0;

describe('Timelock', () => {
  let root, notAdmin, newAdmin;
  let blockTimestamp;
  let timelock;
  let delay = oneWeekInSeconds;
  let newDelay = delay.multipliedBy(2);
  let target;
  let value = zero;
  let signature = 'setDelay(uint256)';
  let data = encodeParameters(['uint256'], [newDelay.toFixed()]);
  let revertData = encodeParameters(['uint256'], [etherUnsigned(60 * 60).toFixed()]);
  let eta;
  let queuedTxHash;
  let accounts;

  before(async () => {
    accounts = await ethers.getSigners();
    root = await accounts[0].getAddress();
    notAdmin = await accounts[1].getAddress();
    newAdmin = await accounts[2].getAddress();

    timelock = await Timelock.new(root, delay);

    ts = await currentBlockTimestamp();
    await setNextBlockTimestamp(ts);
    blockTimestamp = etherUnsigned(ts);
    await freezeTime(blockTimestamp.toNumber());
    target = timelock.address;
    eta = blockTimestamp.plus(delay).plus(100);

    queuedTxHash = keccak256(
      encodeParameters(
        ['address', 'uint256', 'string', 'bytes', 'uint256'],
        [target, value.toString(), signature, data, eta.toString()]
      )
    );
  });

  describe('constructor', () => {
    it('sets address of admin', async () => {
      let configuredAdmin = await timelock.admin();
      expect(configuredAdmin).to.equal(root);
    });

    it('sets delay', async () => {
      let configuredDelay = await timelock.delay();
      expect(configuredDelay.toString()).to.equal(delay.toString());
    });
  });

  describe('setDelay', () => {
    it('requires msg.sender to be Timelock', async () => {
      await expect(timelock.setDelay(delay, { from: root })).to.be.revertedWith('Timelock::setDelay: Call must come from Timelock.');
    });
  });

  describe('setPendingAdmin', () => {
    it('requires msg.sender to be Timelock', async () => {
      await expect(
        timelock.setPendingAdmin(newAdmin, { from: root })
      ).to.be.revertedWith('Timelock::setPendingAdmin: Call must come from Timelock.');
    });
  });

  describe('acceptAdmin', () => {
    it('requires msg.sender to be pendingAdmin', async () => {
      await expect(
        timelock.acceptAdmin({ from: notAdmin })
      ).to.be.revertedWith('Timelock::acceptAdmin: Call must come from pendingAdmin.');
    });
  });

  describe('queueTransaction', () => {
    it('requires admin to be msg.sender', async () => {
      await expect(
        timelock.queueTransaction(target, value, signature, data, eta, { from: notAdmin })
      ).to.be.revertedWith('Timelock::queueTransaction: Call must come from admin.');
    });

    it('requires eta to exceed delay', async () => {
      const etaLessThanDelay = blockTimestamp.plus(delay).minus(1);

      await expect(
        timelock.queueTransaction(target, value, signature, data, etaLessThanDelay, { from: root })
      ).to.be.revertedWith('Timelock::queueTransaction: Estimated execution block must satisfy delay.');
    });

    it('sets hash as true in queuedTransactions mapping', async () => {
      const queueTransactionsHashValueBefore = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueBefore).to.equal(false);

      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      const queueTransactionsHashValueAfter = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueAfter).to.equal(true);
    });

    it('should emit QueueTransaction event', async () => {
      const result = await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      expect(result).to.emit(timelock, 'QueueTransaction').withArgs(
        data,
        signature,
        target,
        eta.toString(),
        queuedTxHash,
        value.toString()
      );
    });
  });

  describe('cancelTransaction', () => {
    beforeEach(async () => {
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
    });

    it('requires admin to be msg.sender', async () => {
      await expect(
        timelock.cancelTransaction(target, value, signature, data, eta, { from: notAdmin })
      ).to.be.revertedWith('Timelock::cancelTransaction: Call must come from admin.');
    });

    it('sets hash from true to false in queuedTransactions mapping', async () => {
      const queueTransactionsHashValueBefore = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueBefore).to.equal(true);

      await timelock.cancelTransaction(target, value, signature, data, eta, { from: root });

      const queueTransactionsHashValueAfter = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueAfter).to.equal(false);
    });

    it('should emit CancelTransaction event', async () => {
      const result = await timelock.cancelTransaction(target, value, signature, data, eta, { from: root });

      expect(result).to.emit(timelock, 'CancelTransaction').withArgs(
        data,
        signature,
        target,
        eta.toString(),
        queuedTxHash,
        value.toString()
      );
    });
  });

  describe('queue and cancel empty', () => {
    it('can queue and cancel an empty signature and data', async () => {
      const txHash = keccak256(
        encodeParameters(
          ['address', 'uint256', 'string', 'bytes', 'uint256'],
          [target, value.toString(), '', '0x', eta.toString()]
        )
      );
      expect(await timelock.queuedTransactions(txHash)).to.equal(false);
      await timelock.queueTransaction(target, value, '', '0x', eta, { from: root });
      expect(await timelock.queuedTransactions(txHash)).to.equal(true);
      await timelock.cancelTransaction(target, value, '', '0x', eta, { from: root });
      expect(await timelock.queuedTransactions(txHash)).to.equal(false);
    });
  });

  describe('executeTransaction (setDelay)', () => {

    it('requires admin to be msg.sender', async () => {
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: notAdmin })
      ).to.be.revertedWith('Timelock::executeTransaction: Call must come from admin.');
    });

    it('requires transaction to be queued', async () => {
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      const differentEta = eta.plus(1);
      await expect(
        timelock.executeTransaction(target, value, signature, data, differentEta, { from: root })
      ).to.be.revertedWith("Timelock::executeTransaction: Transaction hasn't been queued.");
    });

    it('requires timestamp to be greater than or equal to eta', async () => {
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      await setNextBlockTimestamp(new BigNumber(ts).plus(delay).plus(90).toNumber());
      ts = new BigNumber(ts).plus(delay).plus(90).toNumber();

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: root })
      ).to.be.revertedWith("Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
    });

    it('requires timestamp to be less than eta plus gracePeriosd', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);

      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      await setNextBlockTimestamp(new BigNumber(ts).plus(delay).plus(gracePeriod).plus(101).toNumber());
      ts = new BigNumber(ts).plus(delay).plus(gracePeriod).plus(101).toNumber();

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: root })
      ).to.be.revertedWith('Timelock::executeTransaction: Transaction is stale.');
    });

    it('requires target.call transaction to succeed', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      await setNextBlockTimestamp(eta.toNumber());
      ts = eta.toNumber();

      await expect(
        timelock.executeTransaction(target, value, signature, revertData, eta, { from: root })
      ).to.be.revertedWith('Timelock::executeTransaction: Transaction execution reverted.');
    });

    it('sets hash from true to false in queuedTransactions mapping, updates delay, and emits ExecuteTransaction event', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });
      await timelock.queueTransaction(target, value, signature, revertData, eta, { from: root });

      const configuredDelayBefore = await timelock.delay();
      expect(configuredDelayBefore.toString()).to.equal(delay.toString());

      queuedTxHash = keccak256(
        encodeParameters(
          ['address', 'uint256', 'string', 'bytes', 'uint256'],
          [target, value.toString(), signature, data, eta.toString()]
        )
      );

      const queueTransactionsHashValueBefore = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueBefore).to.equal(true);

      const newBlockTimestamp = new BigNumber(ts).plus(delay).plus(101);

      await setNextBlockTimestamp(newBlockTimestamp.toNumber());
      ts = newBlockTimestamp.toNumber();

      const result = await timelock.executeTransaction(target, value, signature, data, eta, { from: root });

      const queueTransactionsHashValueAfter = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueAfter).to.equal(false);

      const configuredDelayAfter = await timelock.delay();
      expect(configuredDelayAfter.toString()).to.equal(newDelay.toString());

      expect(result).to.emit(timelock, 'ExecuteTransaction').withArgs(
        data,
        signature,
        target,
        eta.toString(),
        queuedTxHash,
        value.toString()
      );

      expect(result).to.emit(timelock, 'NewDelay').withArgs(
        newDelay.toString()
      );
    });
  });

  describe('executeTransaction (setPendingAdmin)', () => {
    beforeEach(async () => {
      const configuredDelay = await timelock.delay();

      delay = etherUnsigned(configuredDelay);
      signature = 'setPendingAdmin(address)';
      data = encodeParameters(['address'], [newAdmin]);

      queuedTxHash = keccak256(
        encodeParameters(
          ['address', 'uint256', 'string', 'bytes', 'uint256'],
          [target, value.toString(), signature, data, eta.toString()]
        )
      );

    });

    it('requires admin to be msg.sender', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: notAdmin })
      ).to.be.revertedWith('Timelock::executeTransaction: Call must come from admin.');
    });

    it('requires transaction to be queued', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      const differentEta = eta.plus(1);
      await expect(
        timelock.executeTransaction(target, value, signature, data, differentEta, { from: root })
      ).to.be.revertedWith("Timelock::executeTransaction: Transaction hasn't been queued.");
    });

    it('requires timestamp to be greater than or equal to eta', async () => {
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      await setNextBlockTimestamp(new BigNumber(ts).plus(delay).plus(90).toNumber());
      ts = new BigNumber(ts).plus(delay).plus(90).toNumber();

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: root })
      ).to.be.revertedWith("Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
    });

    it('requires timestamp to be less than eta plus gracePeriod', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);

      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      await setNextBlockTimestamp(new BigNumber(ts).plus(delay).plus(gracePeriod).plus(101).toNumber());
      ts = new BigNumber(ts).plus(delay).plus(gracePeriod).plus(101).toNumber();

      await expect(
        timelock.executeTransaction(target, value, signature, data, eta, { from: root })
      ).to.be.revertedWith('Timelock::executeTransaction: Transaction is stale.');
    });

    it('sets hash from true to false in queuedTransactions mapping, updates admin, and emits ExecuteTransaction event', async () => {
      eta = new BigNumber(ts).plus(delay).plus(100);
      await timelock.queueTransaction(target, value, signature, data, eta, { from: root });

      const configuredPendingAdminBefore = await timelock.pendingAdmin();
      expect(configuredPendingAdminBefore).to.equal('0x0000000000000000000000000000000000000000');

      queuedTxHash = keccak256(
        encodeParameters(
          ['address', 'uint256', 'string', 'bytes', 'uint256'],
          [target, value.toString(), signature, data, eta.toString()]
        )
      );

      const queueTransactionsHashValueBefore = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueBefore).to.equal(true);

      const newBlockTimestamp = new BigNumber(ts).plus(delay).plus(101);

      await setNextBlockTimestamp(newBlockTimestamp.toNumber());
      ts = newBlockTimestamp.toNumber();

      const result = await timelock.executeTransaction(target, value, signature, data, eta, { from: root });

      const queueTransactionsHashValueAfter = await timelock.queuedTransactions(queuedTxHash);
      expect(queueTransactionsHashValueAfter).to.equal(false);

      const configuredPendingAdminAfter = await timelock.pendingAdmin();
      expect(configuredPendingAdminAfter).to.equal(newAdmin);

      expect(result).to.emit(timelock, 'ExecuteTransaction').withArgs(
        data,
        signature,
        target,
        eta.toString(),
        queuedTxHash,
        value.toString()
      );

      expect(result).to.emit(timelock, 'NewPendingAdmin').withArgs(
        newAdmin
      );
    });
  });
});
