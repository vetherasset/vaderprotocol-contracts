const BigNumber = require('bignumber.js');

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

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }

var acc0, acc1, acc2;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;

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
});
// acc  | VTH | VADER | USDV |
// acc0 |   0 |     0 |    0 |
// acc1 |   0 |  2000 |    0 |

describe("Deploy USDV", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    await vether.transfer(acc1, '3403');
    await vether.approve(vader.address, '3400', { from: acc1 });
    await vader.upgrade('4', { from: acc1 });

    assert.equal(await usdv.name(), "VADER STABLE DOLLAR");
    assert.equal(await usdv.symbol(), "USDV");
    assert.equal(BN2Str(await usdv.decimals()), '18');
    assert.equal(BN2Str(await usdv.totalSupply()), '0');
  });
});

describe("Convert", function () {
  it("Should convert acc1", async function () {
    await vader.flipMinting();
    await vader.approve(usdv.address, '10000', { from: acc1 });
    await vader.convertToUSDV('250', { from: acc1 });
    assert.equal(BN2Str(await vader.totalSupply()), '3750');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3750');
    assert.equal(BN2Str(await usdv.totalSupply()), '250');
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '250');
  });

  it("Should convert for member", async function () {
    await vader.convertToUSDVForMember(acc1, '250', { from: acc1 });
    assert.equal(BN2Str(await vader.totalSupply()), '3500');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3500');
    assert.equal(BN2Str(await usdv.totalSupply()), '500');
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '500');
  });

  it("Should convert acc1 directly", async function () {
    await vader.transfer(usdv.address, '500', { from: acc1 });
    await usdv.convertToUSDVDirectly({ from: acc1 });
    assert.equal(BN2Str(await vader.totalSupply()), '3000');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '3000');
    assert.equal(BN2Str(await usdv.totalSupply()), BN2Str(1000));
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), BN2Str(1000));
  });

  it("Should convert acc1", async function () {
    await vader.transfer(usdv.address, '500', { from: acc1 });
    await usdv.convertToUSDVForMemberDirectly(acc1, { from: acc1 });
    assert.equal(BN2Str(await vader.totalSupply()), '2500');
    assert.equal(BN2Str(await vader.balanceOf(acc1)), '2500');
    assert.equal(BN2Str(await usdv.totalSupply()), '1500');
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '1500');
  });
  // acc  | VTH | VADER | USDV |
  // acc0 |   0 |     0 |    0 |
  // acc1 |   0 |  1000 | 1000 |
});

describe("Be a valid ERC-20", function () {
  it("Should transfer From", async function () {
    await usdv.approve(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await usdv.allowance(acc1, acc0)), '100');
    await usdv.transferFrom(acc1, acc0, "100", { from: acc0 });
    assert.equal(BN2Str(await usdv.balanceOf(acc0)), '100');
  });
  // acc  | VTH | VADER | USDV |
  // acc0 |   0 |     0 |  100 |
  // acc1 |   0 |  1000 |  900 |

  it("Should transfer to", async function () {
    await usdv.transfer(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await usdv.balanceOf(acc0)), '200');
  });
  // acc  | VTH | VADER | USDV |
  // acc0 |   0 |     0 |  200 |
  // acc1 |   0 |  1000 |  800 |

  it("Should burn", async function () {
    await usdv.burn("100", { from: acc0 });
    assert.equal(BN2Str(await usdv.balanceOf(acc0)), '100');
    assert.equal(BN2Str(await usdv.totalSupply()), BN2Str('1400'));
  });
  // acc  | VTH | VADER | USDV |
  // acc0 |   0 |     0 |  100 |
  // acc1 |   0 |  1000 |  800 |

  it("Should burn from", async function () {
    await usdv.approve(acc1, "100", { from: acc0 });
    assert.equal(BN2Str(await usdv.allowance(acc0, acc1)), '100');
    await usdv.burnFrom(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await usdv.balanceOf(acc0)), '0');
    assert.equal(BN2Str(await usdv.totalSupply()), BN2Str('1300'));
    assert.equal(BN2Str(await usdv.balanceOf(acc1)), '1300');
  });
  // acc  | VTH | VADER | USDV |
  // acc0 |   0 |     0 |  0   |
  // acc1 |   0 |  1000 |  800 |
});
