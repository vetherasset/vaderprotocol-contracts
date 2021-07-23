const BigNumber = require('bignumber.js');
const truffleAssert = require('truffle-assertions');
const {
  blockNumber, mineBlock,
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

var acc1, acc2;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;
var asset1, asset2, anchor1, anchor2;

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
const one = 1e18;

before(async function () {
  accounts = await ethers.getSigners();
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
});

describe("Deploy Router", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    asset1 = await Asset.new();
    asset2 = await Asset.new();
    anchor1 = await Anchor.new();
    anchor2 = await Anchor.new();

    await vether.transfer(acc1, BN2Str(7407));
    await anchor1.transfer(acc1, BN2Str(2000));
    await anchor1.approve(router.address, BN2Str(one), { from: acc1 });
    await anchor2.transfer(acc1, BN2Str(2000));
    await anchor2.approve(router.address, BN2Str(one), { from: acc1 });

    await vether.approve(vader.address, '7400', { from: acc1 });
    await vader.upgrade('8', { from: acc1 });

    await asset1.transfer(acc1, BN2Str(2000));
    await asset2.transfer(acc1, BN2Str(2000));

    await vader.approve(usdv.address, max, { from: acc1 });
    await vader.approve(router.address, max, { from: acc1 });
    await usdv.approve(router.address, max, { from: acc1 });
    await asset1.approve(router.address, max, { from: acc1 });
    await asset2.approve(router.address, max, { from: acc1 });

    await vader.flipMinting();
    await vader.convertToUSDV('3000', { from: acc1 });

    assert.equal(await vader.GovernorAlpha(), governor.address);
    assert.equal(await governor.UTILS(), utils.address);
    assert.equal(await router.VADER(), vader.address);
    assert.equal(await governor.USDV(), usdv.address);
  });
});

describe("Add liquidity", function () {
  it("Should add anchor1", async function () {
    await router.addLiquidity(vader.address, '1000', anchor1.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.getUnits(anchor1.address)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '1000');
    assert.equal(BN2Str(await pools.getMemberUnits(anchor1.address, acc1)), '1000');
  });

  it("Should add anchor2", async function () {
    await router.addLiquidity(vader.address, '1000', anchor2.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.getUnits(anchor2.address)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor2.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.getTokenAmount(anchor2.address)), '1000');
    assert.equal(BN2Str(await pools.getMemberUnits(anchor2.address, acc1)), '1000');
  });

  it("Should add asset1", async function () {
    await router.addLiquidity(usdv.address, '1000', asset1.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset1.address)), '1000');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset1.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset1.address)), '1000');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset1.address, acc1)), '1000');
  });

  it("Should add asset2", async function () {
    await router.addLiquidity(usdv.address, '1000', asset2.address, '1000', { from: acc1 });
    assert.equal(BN2Str(await pools.mapToken_Units(asset2.address)), '1000');
    assert.equal(BN2Str(await pools.mapToken_baseAmount(asset2.address)), BN2Str(1000));
    assert.equal(BN2Str(await pools.mapToken_tokenAmount(asset2.address)), '1000');
    assert.equal(BN2Str(await pools.mapTokenMember_Units(asset2.address, acc1)), '1000');
  });
});

describe("Should Swap VADER Pools", function () {
  it("Swap from Vader to Anchor", async function () {
    await router.swap('250', vader.address, anchor1.address, { from: acc1 });
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '2750');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), '1250');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '840');
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '1160');
  });

  it("Swap to Anchor", async function () {
    await router.swap('160', anchor1.address, vader.address, { from: acc1 });
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '1000');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), '1082');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '2918');
  });

  it("Swap to Other Anchor", async function () {
    await router.swap('250', anchor1.address, anchor2.address, { from: acc1 });
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '750');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '1250');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), '909');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor2.address)), '1173');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor2.address)), '875');
    assert.equal(BN2Str(await anchor2.balanceOf(acc1)), '1125');
  });
});

describe("Should Swap USDV Pools", function () {
  it("Swap from USDV to Anchor", async function () {
    await router.swap('250', usdv.address, asset1.address, { from: acc1 });
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '750');
    assert.equal(BN2Str(await pools.getBaseAmount(asset1.address)), '1250');
    assert.equal(BN2Str(await pools.getTokenAmount(asset1.address)), '840');
    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '1160');
  });

  it("Swap to Anchor", async function () {
    await router.swap('160', asset1.address, usdv.address, { from: acc1 });
    assert.equal(BN2Str(await asset1.balanceOf(acc1)), '1000');
    assert.equal(BN2Str(await pools.getTokenAmount(asset1.address)), '1000');
    assert.equal(BN2Str(await pools.getBaseAmount(asset1.address)), '1082');
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '918');
  });

  it("Swap to Other Anchor", async function () {
    await router.swap('250', asset1.address, asset2.address, { from: acc1 });
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '750');
    assert.equal(BN2Str(await pools.getTokenAmount(asset1.address)), '1250');
    assert.equal(BN2Str(await pools.getBaseAmount(asset1.address)), '909');
    assert.equal(BN2Str(await pools.getBaseAmount(asset2.address)), '1173');
    assert.equal(BN2Str(await pools.getTokenAmount(asset2.address)), '875');
    assert.equal(BN2Str(await asset2.balanceOf(acc1)), '1125');
  });
});

describe("Should Swap Above Limit", function () {
  it("Fail when swap above limit", async function () {
    await truffleAssert.reverts(router.swapWithLimit('250', usdv.address, asset1.address, '1', { from: acc1 }));
  });
});

describe("Should remove liquidity", function () {
  it("Remove Anchor", async function () {
    assert.equal(BN2Str(await pools.getUnits(anchor1.address)), '1000');
    await router.removeLiquidity(vader.address, anchor1.address, '5000', { from: acc1 });
    assert.equal(BN2Str(await pools.getUnits(anchor1.address)), '500');
    assert.equal(BN2Str(await pools.getMemberUnits(anchor1.address, acc1)), '500');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), '455');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '625');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3372');
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '1375');
  });

  it("Remove Anchor", async function () {
    await router.removeLiquidity(vader.address, anchor1.address, '10000', { from: acc1 });
    assert.equal(BN2Str(await pools.getUnits(anchor1.address)), '0');
    assert.equal(BN2Str(await pools.getMemberUnits(anchor1.address, acc1)), '0');
    assert.equal(BN2Str(await pools.getBaseAmount(anchor1.address)), '0');
    assert.equal(BN2Str(await pools.getTokenAmount(anchor1.address)), '0');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3827');
    assert.equal(BN2Str(await anchor1.balanceOf(acc1)), '2000');
  });
});