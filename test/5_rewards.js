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
// acc  | VTH | VADER | USDV |  Anr |  Ass |
// pool |   0 |  2000 | 2000 | 1000 | 1000 |
// acc1 |   0 |  1000 | 1000 | 1000 | 1000 |

describe("Deploy Rewards", function () {
  it("Should have right reserves", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    anchor = await Anchor.new();
    asset = await Asset.new();

    await vether.transfer(acc1, BN2Str(7407));
    await anchor.transfer(acc1, BN2Str(3000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await anchor.approve(router.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });

    await vader.upgrade('8', { from: acc1 });
    
    await vader.flipMinting();

    let targets = [vader.address];
    let values = ["0"];
    let signatures = ["flipEmissions()"];
    let calldatas = [encodeParameters([], [])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    targets = [vader.address];
    values = ["0"];
    signatures = ["setParams(uint256,uint256,uint256)"];
    calldatas = [encodeParameters(['uint256', 'uint256', 'uint256'], [1, 1, 365])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    await vader.convertToUSDV(BN2Str(1100), { from: acc1 });
    await asset.transfer(acc1, BN2Str(2000));
    await asset.approve(router.address, BN2Str(one), { from: acc1 });

    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', { from: acc1 });
    await router.addLiquidity(usdv.address, '1000', asset.address, '1000', { from: acc1 });

    await vader.transfer(acc0, '100', { from: acc1 });
    await vader.transfer(acc1, '100');
    await vader.transfer(acc0, '100', { from: acc1 });

    assert.equal(BN2Str(await vader.getDailyEmission()), '19');
    assert.equal(BN2Str(await reserve.reserveVADER()), '81');
    assert.equal(BN2Str(await reserve.reserveUSDV()), '14');
  });
});

describe("Should do pool rewards", function () {
  it("Swap anchor, get rewards", async function () {
    let r = '81';

    const targets = [router.address];
    const values = ["0"];
    const signatures = ["curatePool(address)"];
    const calldatas = [encodeParameters(['address'], [anchor.address])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(BN2Str(await reserve.reserveVADER()), r);
    assert.equal(await router.emitting(), true);
    assert.equal(BN2Str(await utils.getRewardShare(anchor.address, '1')), r);
    assert.equal(BN2Str(await utils.getReducedShare(r, '1')), r);
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), '1000');

    let tx = await router.swap('100', vader.address, anchor.address, { from: acc1 });
    assert.equal(BN2Str(tx.logs[0].args.amount), '100');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor.address)), '1150');
    assert.equal(BN2Str(await reserve.reserveVADER()), '0');
    assert.equal(BN2Str(await utils.getRewardShare(anchor.address, '1')), '0');
    assert.equal(BN2Str(await utils.getReducedShare('0', '1')), '0');
    assert.equal(BN2Str(await reserve.reserveVADER()), '0');
    assert.equal(BN2Str(await reserve.reserveUSDV()), '64');
  });

  it("Swap asset, get rewards", async function () {
    let r = '64';
    let targets = [router.address];
    let values = ["0"];
    let signatures = ["setParams(uint256,uint256,uint256,uint256)"];
    let calldatas = [encodeParameters(['uint256', 'uint256', 'uint256', 'uint256'], [1, 1, 2, 0])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    
    targets = [router.address];
    values = ["0"];
    signatures = ["curatePool(address)"];
    calldatas = [encodeParameters(['address'], [asset.address])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc2 });

    assert.equal(BN2Str(await reserve.reserveUSDV()), r);
    assert.equal(await router.emitting(), true);
    assert.equal(BN2Str(await utils.getRewardShare(asset.address, '1')), r);
    assert.equal(BN2Str(await utils.getReducedShare(r, '1')), r);
    assert.equal(BN2Str(await pools.getBaseAmount(asset.address)), '1000');

    let tx = await router.swap('100', usdv.address, asset.address, { from: acc1 });
    assert.equal(BN2Str(tx.logs[0].args.amount), r);
    assert.equal(BN2Str(await pools.getBaseAmount(asset.address)), BN2Str(1100 + +r));
    assert.equal(BN2Str(await reserve.reserveUSDV()), '0');
    assert.equal(BN2Str(await utils.getRewardShare(asset.address, '1')), '0');
    assert.equal(BN2Str(await utils.getReducedShare('0', '1')), '0');
    assert.equal(BN2Str(await reserve.reserveVADER()), '0');
    assert.equal(BN2Str(await reserve.reserveUSDV()), '0');
  });
});

