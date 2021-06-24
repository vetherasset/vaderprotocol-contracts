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
var Synth = artifacts.require('./Synth');
var Asset = artifacts.require('./Token1');
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }

var acc0, acc1;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var asset, anchor;

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

describe("Deploy Lender", function () {
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

    await vader.upgrade('10', { from: acc1 });

    let targets = [vader.address];
    let values = ["0"];
    let signatures = ["flipEmissions()"];
    let calldatas = [encodeParameters([], [])];

    let ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });

    targets = [vader.address];
    values = ["0"];
    signatures = ["setParams(uint256,uint256)"];
    calldatas = [encodeParameters(['uint256', 'uint256'], [1, 1])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });

    await vader.transfer(acc0, ('100'), { from: acc1 });
    await vader.transfer(acc1, ('100'), { from: acc0 });

    await vader.flipMinting();
    await vader.convertToUSDV('5000', { from: acc1 });

    await asset.transfer(acc1, '2000');
    await asset.approve(router.address, BN2Str(one), { from: acc1 });

    await vader.transfer(router.address, '1000', { from: acc1 });
    await usdv.transfer(router.address, '1000', { from: acc1 });

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
  it("Should add asset", async function () {
    let tx = await router.addLiquidity(usdv.address, '1000', asset.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset.address)), '1000');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset.address)), '1000');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset.address, acc1)), '1000');
  });
});

describe("Should Borrow Debt", function () {
  it("Borrow ANCHOR with VADER", async function () {
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3000');
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1000');
    await vader.approve(lender.address, max, { from: acc1 });
    await lender.borrow('100', vader.address, anchor.address, { from: acc1 });
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '2900');
    assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1058');
    assert.equal(BN2Str(await lender.getSystemCollateral(vader.address, anchor.address)), '97');
    assert.equal(BN2Str(await lender.getSystemDebt(vader.address, anchor.address)), '58');
    assert.equal(BN2Str(await lender.getMemberCollateral(acc1, vader.address, anchor.address)), '100');
    assert.equal(BN2Str(await lender.getMemberDebt(acc1, vader.address, anchor.address)), '58');
  });
  it("Borrow ASSET with USDV", async function () {
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '3000');
    assert.equal(BN2Str(await asset.balanceOf(acc1)), '1000');
    await usdv.approve(lender.address, max, { from: acc1 });
    await lender.borrow('100', usdv.address, asset.address, { from: acc1 });
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '2900');
    assert.equal(BN2Str(await asset.balanceOf(acc1)), '1058');
    assert.equal(BN2Str(await lender.getSystemCollateral(usdv.address, asset.address)), '97');
    assert.equal(BN2Str(await lender.getSystemDebt(usdv.address, asset.address)), '58');
    assert.equal(BN2Str(await lender.getMemberCollateral(acc1, usdv.address, asset.address)), '100');
    assert.equal(BN2Str(await lender.getMemberDebt(acc1, usdv.address, asset.address)), '58');
  });
  it("Borrow ASSET with SYNTH-ASSET", async function () {
    await pools.deploySynth(asset.address);
    await router.swapWithSynths('250', usdv.address, false, asset.address, true, { from: acc1 });
    let synth = await Synth.at(await factory.getSynth(asset.address));
    await pools.deploySynth(synth.address); // Works only with this, need to check
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '144');
    assert.equal(BN2Str(await asset.balanceOf(acc1)), '1058');
    await synth.approve(lender.address, max, { from: acc1 });
    await lender.borrow('144', synth.address, asset.address, { from: acc1 });
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '0');
    assert.equal(BN2Str(await asset.balanceOf(acc1)), '1124');
  });
  it("Fail bad combos", async function () {
    await truffleAssert.reverts(lender.borrow('1', vader.address, asset.address, { from: acc1 }));
    await truffleAssert.reverts(lender.borrow('1', usdv.address, anchor.address, { from: acc1 }));
    let synth = await Synth.at(await factory.getSynth(asset.address));
    await truffleAssert.reverts(lender.borrow('1', synth.address, anchor.address, { from: acc1 }));
  });
});

// describe("Should Repay Debt", function() {
//     it("Repay VADER with ANCHOR", async function() {
//       assert.equal(BN2Str(await vader.balanceOf(acc1)), '2650');
//       assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1124');
//     //   assert.equal(BN2Str(await router.getMemberDebt(acc1, vader.address, anchor.address)), '58');
//       await router.repay('10000', vader.address, anchor.address, {from: acc1});
//       assert.equal(BN2Str(await vader.balanceOf(acc1)), '2750');
//       assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1066');
//       assert.equal(BN2Str(await router.getSystemCollateral(vader.address, anchor.address)), '0');
//       assert.equal(BN2Str(await router.getSystemDebt(vader.address, anchor.address)), '0');
//       assert.equal(BN2Str(await router.getMemberCollateral(acc1, vader.address, anchor.address)), '0');
//       assert.equal(BN2Str(await router.getMemberDebt(acc1, vader.address, anchor.address)), '0');
//     });
//     it("Repay USDV with ASSET", async function() {
//         assert.equal(BN2Str(await usdv.balanceOf(acc1)), '2650');
//         assert.equal(BN2Str(await asset.balanceOf(acc1)), '1124');
//         // assert.equal(BN2Str(await router.getMemberDebt(acc1, usdv.address, asset.address)), '58');
//         await router.repay('10000', usdv.address, asset.address, {from: acc1});
//         assert.equal(BN2Str(await usdv.balanceOf(acc1)), '2750');
//         assert.equal(BN2Str(await asset.balanceOf(acc1)), '1066');
//         assert.equal(BN2Str(await router.getSystemCollateral(usdv.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getSystemDebt(usdv.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getMemberCollateral(acc1, usdv.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getMemberDebt(acc1, usdv.address, asset.address)), '0');
//       });

//       it("Repay SYNTH-ANCHOR with ANCHOR", async function() {
//         let synth = await Synth.at(await factory.getSynth(anchor.address));
//         assert.equal(BN2Str(await synth.balanceOf(acc1)), '0');
//         assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1066');
//         // assert.equal(BN2Str(await router.getMemberDebt(acc1, synth.address, anchor.address)), '66');
//         await router.repay('10000', synth.address, anchor.address, {from: acc1});
//         assert.equal(BN2Str(await synth.balanceOf(acc1)), '144');
//         assert.equal(BN2Str(await anchor.balanceOf(acc1)), '1000');
//         assert.equal(BN2Str(await router.getSystemCollateral(synth.address, anchor.address)), '0');
//         assert.equal(BN2Str(await router.getSystemDebt(synth.address, anchor.address)), '0');
//         assert.equal(BN2Str(await router.getMemberCollateral(acc1, synth.address, anchor.address)), '0');
//         assert.equal(BN2Str(await router.getMemberDebt(acc1, synth.address, anchor.address)), '0');
//       });
//       it("Repay SYNTH-ASSET with ASSET", async function() {
//         let synth = await Synth.at(await factory.getSynth(asset.address));
//         assert.equal(BN2Str(await synth.balanceOf(acc1)), '0');
//         assert.equal(BN2Str(await asset.balanceOf(acc1)), '1066');
//         // assert.equal(BN2Str(await router.getMemberDebt(acc1, synth.address, asset.address)), '66');
//         await router.repay('10000', synth.address, asset.address, {from: acc1});
//         assert.equal(BN2Str(await synth.balanceOf(acc1)), '144');
//         assert.equal(BN2Str(await asset.balanceOf(acc1)), '1000');
//         assert.equal(BN2Str(await router.getSystemCollateral(synth.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getSystemDebt(synth.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getMemberCollateral(acc1, synth.address, asset.address)), '0');
//         assert.equal(BN2Str(await router.getMemberDebt(acc1, synth.address, asset.address)), '0');
//       });
// });

