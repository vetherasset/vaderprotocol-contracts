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
var Asset1 = artifacts.require('./Token1');
var Asset2 = artifacts.require('./Token2');
var Anchor = artifacts.require('./Token2');

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }

var acc0, acc1;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var asset1, asset2, anchor;

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
});


describe("Deploy Router", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    asset1 = await Asset1.new();
    asset2 = await Asset2.new();
    anchor = await Anchor.new();

    await vether.transfer(acc1, BN2Str(7407))
    await anchor.transfer(acc1, BN2Str(2000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await vether.approve(vader.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });

    await anchor.approve(router.address, max, { from: acc1 });
    await asset1.approve(router.address, max, { from: acc1 });
    await asset2.approve(router.address, max, { from: acc1 });

    await vader.upgrade('8', { from: acc1 })
    await asset1.transfer(acc1, '2000');
    await asset2.transfer(acc1, '2000');

    await vader.flipMinting();
    await vader.convertToUSDV('4000', { from: acc1 });

    assert.equal(await vader.GovernorAlpha(), governor.address);
    assert.equal(await governor.UTILS(), utils.address);
    assert.equal(await router.VADER(), vader.address);
    assert.equal(await governor.USDV(), usdv.address);

    await router.addLiquidity(vader.address, '1000', anchor.address, '1000', { from: acc1 });
    await router.addLiquidity(usdv.address, '1000', asset1.address, '1000', { from: acc1 });
    await router.addLiquidity(usdv.address, '1000', asset2.address, '1000', { from: acc1 });

  });
});


describe("Should Swap Synths", function () {
  it("Fail for anchor", async function () {
    await truffleAssert.reverts(pools.deploySynth(anchor.address));
  });

  it("Swap from Base to Synth", async function () {
    await pools.deploySynth(asset1.address);
    const synthAddress = await factory.getSynth(asset1.address);
    const synth = await Synth.at(synthAddress);
    await router.swapWithSynths('250', usdv.address, false, asset1.address, true, { from: acc1 });
    const S = BN2Str(await synth.totalSupply());
    const B = BN2Str(await pools.getBaseAmount(asset1.address));
    const T = BN2Str(await pools.getTokenAmount(asset1.address));
    assert.equal(S, '160');
    assert.equal(B, '1250');
    assert.equal(T, '1000');
    assert.equal(BN2Str(await utils.calcSynthUnits(S, B, T)), '100');
    assert.equal(BN2Str(await pools.mapToken_Units(asset1.address)), '1000');

    assert.equal(BN2Str(await utils.calcSwapOutput('250', '1000', '1000')), '160');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '160');
    assert.equal(await synth.name(), 'Token1 - vSynth');
    assert.equal(await synth.symbol(), 'TKN1.v');
    assert.equal(BN2Str(await synth.totalSupply()), '160');
  });

  it("Swap from Synth to Base", async function () {
    const synthAddress = await factory.getSynth(asset1.address);
    const synth = await Synth.at(synthAddress);
    await synth.approve(router.address, max, { from: acc1 });
    await router.swapWithSynths('80', asset1.address, true, vader.address, false, { from: acc1 });
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '80');
    assert.equal(BN2Str(await pools.getBaseAmount(asset1.address)), '1165');
    assert.equal(BN2Str(await pools.getTokenAmount(asset1.address)), '1000');
    assert.equal(BN2Str(await utils.calcShare('80', '160', '100')), '50');
    assert.equal(BN2Str(await pools.mapToken_Units(asset1.address)), '1000');
  });

  it("Swap from Synth to Synth", async function () {
    const synthAddress = await factory.getSynth(asset1.address);
    const synth = await Synth.at(synthAddress);
    await synth.approve(router.address, max, { from: acc1 });
    await pools.deploySynth(asset2.address);
    await router.swapWithSynths('80', asset1.address, true, asset2.address, true, { from: acc1 });
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '0');
    assert.equal(BN2Str(await pools.getBaseAmount(asset2.address)), '1079');
    assert.equal(BN2Str(await pools.getTokenAmount(asset2.address)), '1000');
    assert.equal(BN2Str(await utils.calcShare('80', '160', '100')), '50');
    assert.equal(BN2Str(await pools.mapToken_Units(asset1.address)), '1000');

    assert.equal(BN2Str(await utils.calcSwapOutput('250', '1000', '1000')), '160');
    const synthAddress2 = await factory.getSynth(asset2.address);
    const synth2 = await Synth.at(synthAddress2);
    assert.equal(BN2Str(await synth2.balanceOf(acc1)), '67');
    assert.equal(await synth2.name(), 'Token2 - vSynth');
    assert.equal(await synth2.symbol(), 'TKN2.v');
    assert.equal(BN2Str(await synth2.totalSupply()), '67');
  });

  it("Swap from token to Synth", async function () {
    const synth = await Synth.at(await factory.getSynth(asset2.address));
    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '1000');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '67');

    await router.swapWithSynths('80', asset1.address, false, asset2.address, true, { from: acc1 });

    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '920');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '127');
  });

  it("Swap from Synth to token", async function () {
    const synth = await Synth.at(await factory.getSynth(asset2.address));
    await synth.approve(router.address, max, { from: acc1 });

    assert.equal(BN2Str(await synth.balanceOf(acc1)), '127');
    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '920');

    await router.swapWithSynths('50', asset2.address, true, asset1.address, false, { from: acc1 });

    assert.equal(BN2Str(await synth.balanceOf(acc1)), '77');
    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '970');
  });

  it("Swap from Token to its own Synth", async function () {
    const synth = await Synth.at(await factory.getSynth(asset2.address));
    await synth.approve(router.address, max, { from: acc1 });
    assert.equal(BN2Str(await asset2.balanceOf(acc1)), '1000');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '77');

    await router.swapWithSynths('10', asset2.address, false, asset2.address, true, { from: acc1 });

    assert.equal(BN2Str(await asset2.balanceOf(acc1)), '990');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '86');
  });
});

describe("Member should deposit Synths for rewards", function () {
  it("Should deposit", async function () {
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
    signatures = ["setParams(uint256,uint256,uint256)"];
    calldatas = [encodeParameters(['uint256', 'uint256', 'uint256'], [1, 2, 365])];

    ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });

    await vader.transfer(acc0, ('100'), { from: acc1 });
    await vader.transfer(acc1, ('100'), { from: acc0 });
    assert.equal(BN2Str(await vader.getDailyEmission()), ('5'));

    const synth = await Synth.at(await factory.getSynth(asset2.address));
    await pools.deploySynth(synth.address); // Works only with this, need to check
    await synth.approve(vault.address, max, { from: acc1 });
    await vault.deposit(synth.address, '20', { from: acc1 });
    assert.equal(BN2Str(await synth.balanceOf(acc1)), ('66'));
    assert.equal(BN2Str(await synth.balanceOf(vault.address)), ('20'));
    assert.equal(BN2Str(await vault.getMemberDeposit(acc1, synth.address)), ('20'));
    assert.equal(BN2Str(await vault.getMemberWeight(acc1)), ('20'));
    assert.equal(BN2Str(await vault.totalWeight()), ('20'));
  });

  it("Should calc rewards", async function () {
    const synth = await Synth.at(await factory.getSynth(asset2.address));
    const balanceStart = await vader.balanceOf(vault.address);
    assert.equal(BN2Str(balanceStart), ('0'));
    await usdv.transfer(acc0, ('100'), { from: acc1 });
    assert.equal(BN2Str(await reserve.reserveUSDV()), '6');
    assert.equal(BN2Str(await synth.balanceOf(vault.address)), ('20'));
    assert.equal(BN2Str(await vault.calcDepositValueForMember(synth.address, acc1)), ('20')); // * by seconds
  });

  it("Should harvest", async function () {
    const ts = await currentBlockTimestamp();
    await setNextBlockTimestamp(ts + 5 * 15);

    const synth = await Synth.at(await factory.getSynth(asset2.address));
    assert.equal(BN2Str(await vault.getAssetDeposit(synth.address)), ('20'));
    assert.equal(BN2Str(await vault.totalWeight()), ('20'));
    assert.equal(BN2Str(await reserve.getVaultReward()), ('3'));
    assert.equal(BN2Str(await vault.calcRewardForAsset(synth.address)), ('3'));

    await vault.harvest(synth.address, { from: acc1 });
    assert.equal(BN2Str(await synth.balanceOf(vault.address)), ('22'));
    assert.equal(BN2Str(await vault.getMemberWeight(acc1)), ('20'));
    assert.equal(BN2Str(await vault.totalWeight()), ('20'));
  });

  it("Should withdraw", async function () {
    const synth = await Synth.at(await factory.getSynth(asset2.address));
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '66');
    assert.equal(BN2Str(await synth.balanceOf(vault.address)), '22');
    assert.equal(BN2Str(await vault.getMemberDeposit(acc1, synth.address)), '20');
    assert.equal(BN2Str(await vault.getMemberWeight(acc1)), '20');

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["flipEmissions()"];
    const calldatas = [encodeParameters([], [])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc0 });

    await vault.withdraw(synth.address, "10000", { from: acc1 });
    assert.equal(BN2Str(await vault.getMemberDeposit(acc1, synth.address)), '0');
    assert.equal(BN2Str(await vault.getMemberWeight(acc1)), '0');
    assert.equal(BN2Str(await vault.totalWeight()), '0');
    assert.equal(BN2Str(await synth.balanceOf(vault.address)), '0');
    assert.equal(BN2Str(await synth.balanceOf(acc1)), '88');
  });
});