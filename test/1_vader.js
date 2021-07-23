const BigNumber = require('bignumber.js');
const { expect } = require('hardhat');
const truffleAssert = require('truffle-assertions');
const {
  encodeParameters,
  mineBlock,
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

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()); }

var acc0, acc1, acc2, acc3;
var vether, vader, usdv, reserve, vault, router;
var lender, pools, factory, utils, governor, timelock;

const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
const one = 1e18;

before(async function () {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress();
  acc1 = await accounts[1].getAddress();
  acc2 = await accounts[2].getAddress();
  acc3 = await accounts[3].getAddress();

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
    acc3
  );
  timelock = await Timelock.new(acc3, 2 * 24 * 60 * 60);
  await governor.initTimelock(timelock.address);

  await vether.transfer(acc1, BN2Str(4000));
  await vether.transfer(acc2, BN2Str(8000));

  await vader.approve(usdv.address, max, { from: acc1 });
  await vader.approve(usdv.address, max, { from: acc3 });
  await vether.approve(vader.address, max, { from: acc1 });
  await vether.approve(vader.address, max, { from: acc2 });
  await vether.approve(vader.address, max, { from: acc3 });
  await usdv.approve(vault.address, max, { from: acc1 });
  await usdv.approve(vault.address, max, { from: acc3 });
  await vether.transfer(acc3, BN2Str(BigNumber(1000000e18).minus(12000))); // 1e6 * 1e18 - 4000 - 8000

  // acc  |  VTH |VADER |
  // acc0 |    0 |    0 |
  // acc1 | 3996 |    0 |
});

describe("Deploy Vader", function () {
  it("Should deploy", async function () {
    await vader.changeGovernorAlpha(governor.address);
    await reserve.init(vader.address);

    assert.equal(await vader.name(), "VADER PROTOCOL TOKEN");
    assert.equal(await vader.symbol(), "VADER");
    assert.equal(BN2Str(await vader.decimals()), '18');
    assert.equal(BN2Str(await vader.totalSupply()), '0');
    assert.equal(BN2Str(await vader.maxSupply()), BN2Str(2e9 * one));
    assert.equal(BN2Str(await vader.emissionCurve()), '10');
    assert.equal(await vader.emitting(), false);
    assert.equal(BN2Str(await vader.secondsPerEra()), '1');
    assert.equal(await vader.GovernorAlpha(), governor.address);
    assert.equal(await vader.Admin(), acc0);
    assert.equal(await vader.burnAddress(), "0x0111011001100001011011000111010101100101");
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('0'));
  });
});

describe("Upgrade", function () {
  it("Should upgrade acc1", async function () {
    await vader.flipMinting();
    await vader.upgrade(BN2Str(5), { from: acc1 });
    await usdv.convertToUSDV(BN2Str(4000), { from: acc1 });
    await vault.deposit(usdv.address, BN2Str(4000), { from: acc1 });
    await vader.upgrade(BN2Str(12), { from: acc3 });
    await usdv.convertToUSDV(BN2Str(12000), { from: acc3 });
    await vault.deposit(usdv.address, BN2Str(12000), { from: acc3 });
    await mineBlock();

    assert.equal(BN2Str(await vader.totalSupply()), BN2Str(1000));
    assert.equal(BN2Str(await vether.balanceOf(acc1)), BN2Str(3991)); // 4000 - 4(0.1% of 4000) - 5(0.1% of 5000);
    assert.equal(BN2Str(await vader.balanceOf(acc1)), BN2Str(1000));
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('100'));
  });
  // acc  |  VTH | VADER |
  // acc0 |    0 |     0 |
  // acc1 | 3991 |  1000 |
});

describe("Be a valid ERC-20", function () {
  it("Should transfer From fail", async function () {
    assert.equal(BN2Str(await vader.allowance(acc1, acc0)), '0');
    await truffleAssert.reverts(vader.transferFrom(acc1, acc0, "100", { from: acc0 }));
    assert.equal(BN2Str(await vader.balanceOf(acc0)), '0');
  });

  it("Should transfer From", async function () {
    await vader.approve(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await vader.allowance(acc1, acc0)), '100');
    await vader.transferFrom(acc1, acc0, "100", { from: acc0 });
    assert.equal(BN2Str(await vader.balanceOf(acc0)), '100');
  });
  // acc  |  VTH | VADER |
  // acc0 |    0 |   100 |
  // acc1 | 3991 |   900 |

  it("Should transfer", async function () {
    await vader.transfer(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await vader.balanceOf(acc0)), '200');
  });
  // acc  |  VTH | VADER |
  // acc0 |    0 |   200 |
  // acc1 | 3991 |   800 |

  it("Should burn", async function () {
    await vader.burn("100", { from: acc0 });
    assert.equal(BN2Str(await vader.balanceOf(acc0)), '100');
    assert.equal(BN2Str(await vader.totalSupply()), BN2Str('900'));
  });
  // acc  |  VTH | VADER |
  // acc0 |    0 |   100 |
  // acc1 | 3991 |   800 |

  it("Should burn from", async function () {
    await vader.approve(acc1, "100", { from: acc0 });
    assert.equal(BN2Str(await vader.allowance(acc0, acc1)), '100');
    await vader.burnFrom(acc0, "100", { from: acc1 });
    assert.equal(BN2Str(await vader.balanceOf(acc0)), '0');
    assert.equal(BN2Str(await vader.totalSupply()), BN2Str('800'));
  });
  // acc  |  VTH | VADER |
  // acc0 |    0 |     0 |
  // acc1 | 3991 |   800 |
});

describe("Governance Functions", function () {
  it("Non-Governance fails", async function () {
    await truffleAssert.reverts(vader.flipEmissions({ from: acc1 }));
  });

  it("Governance setParams", async function () {
    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["setParams(uint256,uint256)"];
    const calldatas = [encodeParameters(['uint256', 'uint256'], [1, 1])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(BN2Str(await vader.secondsPerEra()), '1');
    assert.equal(BN2Str(await vader.emissionCurve()), '1');
  });

  it("Governance start emitting", async function () {
    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["flipEmissions()"];
    const calldatas = [encodeParameters([], [])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(await vader.emitting(), true);
  });
});

describe("Emissions", function () {
  it("Should emit properly", async function () {
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('800'));
    await vader.transfer(acc0, BN2Str(200), { from: acc1 });
    await vader.transfer(acc1, BN2Str(100), { from: acc0 });
    assert.equal(BN2Str(await vader.balanceOf(reserve.address)), BN2Str('2400'));
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('3200'));
    await vader.transfer(acc0, BN2Str(100), { from: acc1 });
    assert.equal(BN2Str(await vader.balanceOf(reserve.address)), BN2Str('5600'));
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('6400'));
  });
});

describe("FeeOnTransfer", function () {
  it("Should set up fees", async function () {
    assert.equal(BN2Str(await vader.feeOnTransfer()), '0');
    assert.equal(BN2Str(await vader.totalSupply()), BN2Str(6400));
    assert.equal(BN2Str(await vether.balanceOf(acc1)), '3991');
    await vether.transfer(acc1, BN2Str(BigNumber(1e24).minus(1e22)), { from: acc3 });
    await vether.approve(vader.address, BN2Str(1e23), { from: acc1 });
    await vader.upgrade(BN2Str(1e23), { from: acc1 }); // totalSupply = 1e26 + 6400

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["setParams(uint256,uint256)"];
    const calldatas = [encodeParameters(['uint256', 'uint256'], [1, 2024])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(BN2Str(await vader.secondsPerEra()), '1');
    assert.equal(BN2Str(await vader.emissionCurve()), '2024');

    // _adjustedMax = (maxSupply * totalSupply) / baseline
    // _adjustedMax = (2bn * (1e26 + 6400)) / 1bn = 2e26 + 12800
    // (_adjustedMax - totalSupply) / (emissionCurve);
    // ((2e26 + 12800) - (1e26 + 6400)) / (2024) = (1e26 + 6400) / 2024 = 49,407,114,624,505,928,853,758
    assert.equal(BN2Str(await vader.getDailyEmission()), BN2Str('49407114624505928853758'));
    assert.equal(BN2Str(await vader.totalSupply()), BN2Str(BigNumber(1e26).plus(6400)));
    await vader.transfer(acc1, BN2Str(100), { from: acc1 });
    // 1e26 + 6,400 + 49,407,114,624,505,928,853,758 = 100,049,407,114,624,505,928,860,158
    assert.equal(BN2Str(await vader.totalSupply()), '100049407114624505928860158');
    assert.equal(BN2Str(await vader.maxSupply()), BN2Str(2 * 10 ** 9 * 10 ** 18));
    // (1e26 + 49,407,114,624,505,928,853,758) * 100 / 2e27
    assert.equal(BN2Str(await vader.feeOnTransfer()), '5');
  });

  it("Should charge fees", async function () {
    // 5 * 8000 / 10000 = 4
    let tx = await vader.transfer(acc0, BN2Str(8000), { from: acc1 });
    assert.equal(BN2Str(tx.logs[0].args.value), '4');
    // 8000 - 4 = 7996
    assert.equal(BN2Str(tx.logs[1].args.value), '7996');
  });
});

describe("Governor and Admin", function () {
  it("Should change Admin", async function () {
    await expect(vader.changeAdmin(acc2, { from: acc3 })).to.be.revertedWith("!Admin && !TIMELOCK");
    await vader.changeAdmin(acc2);
    assert.equal(await vader.Admin(), acc2);

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["changeAdmin(address)"];
    const calldatas = [encodeParameters(['address'], [acc3])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(await vader.Admin(), acc3);
  });

  it("Should purge Admin", async function () {
    await expect(vader.purgeAdmin()).to.be.revertedWith("!TIMELOCK");

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["purgeAdmin()"];
    const calldatas = [encodeParameters([], [])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(await vader.Admin(), "0x0000000000000000000000000000000000000000");
  });

  it("Should purge GorvernorAlpha", async function () {
    await expect(vader.purgeGovernorAlpha()).to.be.revertedWith("!TIMELOCK");

    const targets = [vader.address];
    const values = ["0"];
    const signatures = ["purgeGovernorAlpha()"];
    const calldatas = [encodeParameters([], [])];

    const ts = await currentBlockTimestamp() + 2 * 24 * 60 * 60 + 60;
    await timelock.queueTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });
    await setNextBlockTimestamp(ts);
    await timelock.executeTransaction(targets[0], values[0], signatures[0], calldatas[0], ts, { from: acc3 });

    assert.equal(await vader.GovernorAlpha(), "0x0000000000000000000000000000000000000000");
  });
});