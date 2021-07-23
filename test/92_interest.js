const BigNumber = require('bignumber.js');
const {
  encodeParameters,
  setNextBlockTimestamp,
  currentBlockTimestamp,
} = require('./Utils/Ethereum');

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
var Synth = artifacts.require('./Synth');
var Asset = artifacts.require('./Token1');
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }

var acc0, acc1;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var asset, anchor;

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

before(async function () {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress();
  acc1 = await accounts[1].getAddress();

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
    reserve.address,
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    utils.address,
    acc0
  );
  timelock = await Timelock.new(acc0, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);
});

describe("Deploy Interest", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    asset = await Asset.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, '9409');
    await anchor.transfer(acc1, '2000');

    await vader.approve(usdv.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });
    await anchor.approve(router.address, max, { from: acc1 });
    await asset.approve(router.address, max, { from: acc1 });

    await vader.upgrade('10', { from: acc1 });

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["flipEmissions()"];
    const calldatas = [encodeParameters([], [])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });

    await vader.flipMinting();
    await vader.convertToUSDV('5000', { from: acc1 });

    await asset.transfer(acc1, '2000');
    await vader.transfer(router.address, '1000', { from: acc1 });
    await usdv.transfer(router.address, '1000', { from: acc1 });
  });
});

describe("Add liquidity", function () {
  it("Should add anchor", async function () {
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', { from: acc1 });
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', { from: acc1 });
  });
});

describe("Should Borrow Debt", function () {
  it("Borrow", async function () {
    await vader.approve(lender.address, max, { from: acc1 });
    await usdv.approve(lender.address, max, { from: acc1 });
    await lender.borrow('100', vader.address, anchor.address, { from: acc1 });
    await lender.borrow('100', usdv.address, asset.address, { from: acc1 });
    await pools.deploySynth(asset.address);
    await router.swapWithSynths('250', usdv.address, false, asset.address, true, { from: acc1 });
    const synth = await Synth.at(await factory.getSynth(asset.address));
    await synth.approve(lender.address, max, { from: acc1 });
    await lender.borrow('144', synth.address, asset.address, { from: acc1 });
  });

});

describe("Should pay interest", function () {
  it("Pay VADER-ANCHOR interest", async function () {
    assert.equal(BN2Str(await utils.getDebtLoading(vader.address, anchor.address)), '615');
    assert.equal(BN2Str(await utils.getInterestPayment(vader.address, anchor.address)), '3');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor.address, '3')), '3');
    assert.equal(BN2Str(await utils.getInterestOwed(vader.address, anchor.address, '31536000')), '3');
    assert.equal(BN2Str(await lender.getSystemInterestPaid(vader.address, anchor.address)), '3');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), '1069');
  });
});

