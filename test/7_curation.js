const { expect } = require("chai");
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
var Asset = artifacts.require('./Token1');
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }

var acc0, acc1, acc2;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var asset1, asset2, asset3, anchor;

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
const one = 1e18;

before(async function () {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress();
  acc1 = await accounts[1].getAddress();
  acc2 = await accounts[2].getAddress();

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
    acc2
  );
  timelock = await Timelock.new(acc2, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);
});

describe("Deploy Router", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["flipEmissions()"];
    const calldatas = [encodeParameters([], [])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    asset1 = await Asset.new();
    asset2 = await Asset.new();
    asset3 = await Asset.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, BN2Str(7407));
    await anchor.transfer(acc1, BN2Str(2000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });
    await anchor.approve(router.address, max, { from: acc1 });

    await vader.upgrade('7', { from: acc1 });

    await asset1.transfer(acc1, BN2Str(2000));
    await asset1.approve(router.address, BN2Str(one), { from: acc1 });
    await asset2.transfer(acc1, BN2Str(2000));
    await asset2.approve(router.address, BN2Str(one), { from: acc1 });
    await asset3.transfer(acc1, BN2Str(2000));
    await asset3.approve(router.address, BN2Str(one), { from: acc1 });

    await vader.flipMinting();
    await vader.convertToUSDV(3000, { from: acc1 });
    await usdv.transfer(acc0, '1', { from: acc1 });
    await usdv.transfer(acc1, '1', { from: acc0 });

    assert.equal(await vader.GovernorAlpha(), governor.address);
    assert.equal(await governor.UTILS(), utils.address);
    assert.equal(await router.VADER(), vader.address);
    assert.equal(await governor.USDV(), usdv.address);
  });
});

describe("Add liquidity", function () {
  it("Should add anchor", async function () {
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.getUnits(anchor.address)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.getTokenAmount(anchor.address)), '1000');
    assert.equal(BN2Str(await pools.getMemberUnits(anchor.address, acc1)), '1000');
  });

  it("Should add asset1", async function () {
    await router.addLiquidity(usdv.address, '1000', asset1.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset1.address)), '1000');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset1.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset1.address)), '1000');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset1.address, acc1)), '1000');
  });

  it("Should add asset2", async function () {
    await router.addLiquidity(usdv.address, '999', asset2.address, '999', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset2.address)), '999');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset2.address)), '999');
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset2.address)), '999');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset2.address, acc1)), '999');
  });

  it("Should add asset3", async function () {
    await router.addLiquidity(usdv.address, '999', asset3.address, '999', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset3.address)), '999');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset3.address)), '999');
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset3.address)), '999');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset3.address, acc1)), '999');
  });
});

describe("Should Curate", function () {
  it("Curate first pool", async function () {
    assert.equal(await pools.isAsset(asset1.address), true);
    assert.equal(await router.isCurated(asset1.address), false);
    assert.equal(BN2Str(await router.curatedPoolLimit()), '1');
    assert.equal(BN2Str(await router.curatedPoolCount()), '0');

    const targets = [router.address];
    const values = ["0"];
    const signatures = ["curatePool(address)"];
    const calldatas = [encodeParameters(['address'], [asset1.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(await router.isCurated(asset1.address), true);
    assert.equal(BN2Str(await router.curatedPoolCount()), '1');
  });

  it("Fail curate second", async function () {
    const targets = [router.address];
    const values = ["0"];
    const signatures = ["curatePool(address)"];
    const calldatas = [encodeParameters(['address'], [asset2.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(await router.isCurated(asset2.address), false);
    assert.equal(BN2Str(await router.curatedPoolCount()), '1');
  });

  it("Increase limit", async function () {
    let targets = [router.address];
    let values = ["0"];
    let signatures = ["setParams(uint256,uint256,uint256,uint256)"];
    let calldatas = [encodeParameters(['uint256', 'uint256', 'uint256', 'uint256'], [1, 1, 2, 0])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(BN2Str(await router.curatedPoolLimit()), '2');
    
    targets = [router.address];
    values = ["0"];
    signatures = ["curatePool(address)"];
    calldatas = [encodeParameters(['address'], [asset2.address])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(await router.isCurated(asset2.address), true);
    assert.equal(BN2Str(await router.curatedPoolCount()), '2');
  });

  it("Replace 1-for-1", async function () {
    await router.addLiquidity(usdv.address, '1', asset3.address, '1', { from: acc1 })
  
    assert.equal(await router.isCurated(asset2.address), true);
    assert.equal(await router.isCurated(asset3.address), false);

    const targets = [router.address];
    const values = ["0"];
    const signatures = ["replacePool(address,address)"];
    const calldatas = [encodeParameters(['address', 'address'], [asset2.address, asset3.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(await router.isCurated(asset2.address), false);
    assert.equal(await router.isCurated(asset3.address), true);
  });
});

describe("Should Do Rewards and Protection", function () {
  it("Not curated, No rewards", async function () {
    assert.equal(await router.isCurated(asset2.address), false);
    assert.equal(BN2Str(await utils.getRewardShare(asset2.address, '1')), '0');
  });

  it("Curated, Rewards", async function () {
    const targets = [router.address];
    const values = ["0"];
    const signatures = ["curatePool(address)"];
    const calldatas = [encodeParameters(['address'], [asset1.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    expect(Number(await reserve.reserveUSDV())).to.be.greaterThan(0);
  });

  it("Not curated, No Protection", async function () {
    for (let i = 0; i < 9; i++) {
      await router.swap('100', asset2.address, usdv.address, { from: acc1 });
    }
    await utils.getCoverage(acc1, asset2.address);
    assert.equal(BN2Str(await utils.getProtection(acc1, asset2.address, "10000", '1')), '0');
  });

  it("Curated, Protection", async function () {
    for (let i = 0; i < 9; i++) {
      await router.swap('100', asset1.address, usdv.address, { from: acc1 });
    }
    await utils.getCoverage(acc1, asset2.address);
    assert.equal(BN2Str(await utils.getProtection(acc1, asset2.address, "10000", '1')), '0');
  });
});