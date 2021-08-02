const BigNumber = require('bignumber.js');
const truffleAssert = require('truffle-assertions');
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
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }
function getBN(BN) { return (new BigNumber(BN)); }
function approx(number) { return BN2Str((getBN(number).div(10 ** 16)).integerValue()); }

var acc0, acc1;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var anchor0, anchor1, anchor2, anchor3, anchor4, anchor5;

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
const one = 1e18;

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
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    reserve.address,
    utils.address,
    acc0
  );
  timelock = await Timelock.new(acc0, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);

  anchor0 = await Anchor.new();
  anchor1 = await Anchor.new();
  anchor2 = await Anchor.new();
  anchor3 = await Anchor.new();
  anchor4 = await Anchor.new();
  anchor5 = await Anchor.new();
});

describe("Deploy Anchor", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    await vether.transfer(acc1, BN2Str(6006));

    await vader.approve(usdv.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });

    await vader.upgrade('6', { from: acc1 });

    await anchor0.transfer(acc1, BN2Str(2000));
    await anchor0.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor1.transfer(acc1, BN2Str(2000));
    await anchor1.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor2.transfer(acc1, BN2Str(2000));
    await anchor2.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor3.transfer(acc1, BN2Str(2000));
    await anchor3.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor4.transfer(acc1, BN2Str(2000));
    await anchor4.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor5.transfer(acc1, BN2Str(2000));
    await anchor5.approve(router.address, BN2Str(one), { from: acc1 });

    await router.addLiquidity(vader.address, '100', anchor0.address, '99', { from: acc1 });
    await router.addLiquidity(vader.address, '100', anchor1.address, '100', { from: acc1 });
    await router.addLiquidity(vader.address, '100', anchor2.address, '101', { from: acc1 });
    await router.addLiquidity(vader.address, '100', anchor3.address, '102', { from: acc1 });
    await router.addLiquidity(vader.address, '100', anchor4.address, '103', { from: acc1 });

    assert.equal(BN2Str(await utils.calcValueInBase(anchor0.address, '100')), '101');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor1.address, '100')), '100');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor2.address, '100')), '99');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor3.address, '100')), '98');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor4.address, '100')), '97');
  });
});

describe("Handle Anchors", function () {
  it("List Anchors", async function () {
    await router.listAnchor(anchor0.address, { from: acc1 });
    await router.listAnchor(anchor1.address, { from: acc1 });
    await router.listAnchor(anchor2.address, { from: acc1 });
    await router.listAnchor(anchor3.address, { from: acc1 });
    await router.listAnchor(anchor4.address, { from: acc1 });
    await truffleAssert.reverts(router.listAnchor(anchor4.address, { from: acc1 }));
  });

  it("Get prices", async function () {
    assert.equal(BN2Str(await router.getAnchorPrice()), '990099009900990099');
  });

  it("Replace Median", async function () {
    await router.swap('2', vader.address, anchor4.address, { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_baseAmount(anchor4.address)), '102');
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(anchor4.address)), '102');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor4.address, '100')), '100');
    assert.equal(BN2Str(await router.getAnchorPrice()), '1000000000000000000');
  });

  it("Create outlier", async function () {
    await router.swap('10', vader.address, anchor0.address, { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_baseAmount(anchor0.address)), '110');
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(anchor0.address)), '91');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor0.address, '100')), '120');
    assert.equal(BN2Str(await router.getAnchorPrice()), '1000000000000000000');
  });

  it("Replace Outlier", async function () {
    assert.equal(await router.arrayAnchors('0'), anchor0.address);
    await router.addLiquidity(vader.address, '111', anchor5.address, '111', { from: acc1 });
    assert.equal(BN2Str(await router.getAnchorPrice()), '1000000000000000000');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor0.address, '1000000000000000000')), '1208791208791208791');
    assert.equal(BN2Str(await utils.calcValueInBase(anchor5.address, '1000000000000000000')), '1000000000000000000');

    const targets = [router.address];
    const values = ["0"];
    const signatures = ["replaceAnchor(address,address)"];
    const calldatas = [encodeParameters(['address', 'address'], [anchor0.address, anchor5.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts);
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts);

    assert.equal(await router.arrayAnchors('0'), anchor5.address);
    assert.equal(BN2Str(await router.getAnchorPrice()), '1000000000000000000');
  });
});

describe("Handle TWAP", function () {
  it("Get prices", async function () {
    const ts = await currentBlockTimestamp() + 2000;
    await setNextBlockTimestamp(ts);
    await router.swap('10', vader.address, anchor0.address, { from: acc1 });
    await router.swap('10', vader.address, anchor1.address, { from: acc1 });
    await router.swap('10', vader.address, anchor2.address, { from: acc1 });
    await router.swap('10', vader.address, anchor3.address, { from: acc1 });
    await router.swap('10', vader.address, anchor4.address, { from: acc1 });
    await setNextBlockTimestamp(ts + 1 * 15);

    assert.equal(approx(await router.getTWAPPrice()), '31');
    await router.swap('10', anchor0.address, vader.address, { from: acc1 });
    await router.swap('10', anchor1.address, vader.address, { from: acc1 });
    await router.swap('10', anchor2.address, vader.address, { from: acc1 });
    await router.swap('10', anchor3.address, vader.address, { from: acc1 });
    await router.swap('10', anchor4.address, vader.address, { from: acc1 });
    await setNextBlockTimestamp(ts + 2 * 15);

    assert.equal(approx(await router.getTWAPPrice()), '32');
    await router.swap('10', anchor0.address, vader.address, { from: acc1 });
    await router.swap('10', anchor1.address, vader.address, { from: acc1 });
    await router.swap('10', anchor2.address, vader.address, { from: acc1 });
    await router.swap('10', anchor3.address, vader.address, { from: acc1 });
    await router.swap('10', anchor4.address, vader.address, { from: acc1 });
    await setNextBlockTimestamp(ts + 3 * 15);

    assert.equal(approx(await router.getTWAPPrice()), '27');
    assert.equal(approx(await router.getAnchorPrice()), '83');
    assert.equal(BN2Str(await router.getVADERAmount('100')), '26');
    assert.equal(BN2Str(await router.getUSDVAmount('100')), '374');
  });
});
