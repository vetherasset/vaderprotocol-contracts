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
var asset, anchor;

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
    reserve.address,
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    utils.address,
    acc2
  );
  timelock = await Timelock.new(acc2, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);
})
// acc  | VTH | VADER | USDV | Anr  |  Ass |
// pool |   0 |  2000 | 2000 | 1000 | 1000 |
// acc1 |   0 |  1000 | 1000 | 1000 | 1000 |

describe("Deploy Protection", function () {
  it("Should have right reserves", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    let targets = [vader.address];
    let values = ["0"];
    let signatures = ["flipEmissions()"];
    let calldatas = [encodeParameters([], [])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    anchor = await Anchor.new();
    asset = await Asset.new();

    await vether.transfer(acc1, BN2Str(7407));
    await anchor.transfer(acc1, BN2Str(2000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await anchor.approve(router.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });

    await vader.upgrade('8', { from: acc1 });
    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', { from: acc1 });

    await vader.flipMinting();
    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    targets = [vader.address];
    values = ["0"];
    signatures = ["setParams(uint256,uint256)"];
    calldatas = [encodeParameters(['uint256', 'uint256'], [1, 1])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    await vader.convertToUSDV('2000', { from: acc1 });

    await asset.transfer(acc1, '2000');
    await asset.approve(router.address, BN2Str(one), { from: acc1 });
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', { from: acc1 });

    await vader.transfer(acc0, '100', { from: acc1 });
    await vader.transfer(acc1, '100');
    await vader.transfer(acc0, '100', { from: acc1 });
    await usdv.transfer(acc0, '100', { from: acc1 });

    assert.equal(BN2Str(await vader.getDailyEmission()), '6800');
    assert.equal(BN2Str(await reserve.reserveVADER()), '800');
    assert.equal(BN2Str(await vader.balanceOf(reserve.address)), '800');
  });
});

describe("Should do IL Protection", function () {
  it("Core math", async function () {
    assert.equal(BN2Str(await utils.calcCoverage('123', '456', '789', '0')), '0'); // T1 == 0, so calculation can't continue
    assert.equal(BN2Str(await utils.calcCoverage('100', '20', '100', '100')), '0'); // deposit less than redemption

    assert.equal(BN2Str(await utils.calcCoverage('1000', '1000', '1100', '918')), '0');
    assert.equal(BN2Str(await utils.calcCoverage('1000', '1000', '1200', '820')), '63');

    assert.equal(BN2Str(await utils.calcCoverage('100', '1000', '75', '2000')), '0');
    assert.equal(BN2Str(await utils.calcCoverage('100', '1000', '20', '2000')), '70');
  });

  it("Small swap, need protection", async function () {
    await router.curatePool(anchor.address)
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), '1000');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor.address)), '1000');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '4900');

    for (let i = 0; i < 9; i++) {
      await router.swap('100', anchor.address, vader.address, { from: acc1 })
    }
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '100');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor.address)), '1900');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), '554');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '5346');

    assert.equal(BN2Str(await router.mapMemberToken_depositBase(acc1, anchor.address)), '1000');
    assert.equal(BN2Str(await router.mapMemberToken_depositToken(acc1, anchor.address)), '1000');
    const coverage = await utils.getCoverage(acc1, anchor.address);
    assert.equal(BN2Str(coverage), '183');
    assert.equal(BN2Str(await utils.getProtection(acc1, anchor.address, "10000", '1')), '183');
    assert.equal(BN2Str(await router.getILProtection(acc1, vader.address, anchor.address, '10000')), '183');
  });

  it("RECEIVE protection on 50% ", async function () {
    assert.equal(BN2Str(await reserve.reserveVADER()), '800');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '5346');
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '100');

    const share = await utils.getMemberShare('5000', anchor.address, acc1)

    assert.equal(BN2Str(share.units), '500');
    assert.equal(BN2Str(share.outputBase), '277');
    assert.equal(BN2Str(share.outputToken), '950');

    await router.removeLiquidity(vader.address, anchor.address, '5000', { from: acc1 })

    assert.equal(BN2Str(await reserve.reserveVADER()), '709');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '5668'); // +322
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1049'); // +950

    assert.equal(BN2Str(await pools.getMemberUnits(anchor.address, acc1)), '536');
  });

  it("Small swap, need protection on Asset", async function () {
    const targets = [router.address];
    const values = ["0"];
    const signatures = ["setParams(uint256,uint256,uint256,uint256)"];
    const calldatas = [encodeParameters(['uint256', 'uint256', 'uint256', 'uint256'], [1, 1, 2, 0])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(await pools.isAsset(asset.address), true);
    await router.curatePool(asset.address);
    assert.equal(await router.isCurated(asset.address), true);
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '900');
    for (let i = 0; i < 9; i++) {
      await router.swap('100', asset.address, usdv.address, { from: acc1 });
    }

    assert.equal(BN2Str(await router.mapMemberToken_depositBase(acc1, asset.address)), '1000');
    assert.equal(BN2Str(await router.mapMemberToken_depositToken(acc1, asset.address)), '1000');
    const coverage = await utils.getCoverage(acc1, asset.address);
    assert.equal(BN2Str(coverage), '183');;
    assert.equal(BN2Str(await utils.getProtection(acc1, asset.address, "10000", '1')), '183');
    expect(Number(await router.getILProtection(acc1, usdv.address, asset.address, '10000'))).to.be.lessThanOrEqual(Number(await reserve.reserveVADER()));
  });
});
