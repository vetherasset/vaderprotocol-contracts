const { expect } = require("chai");
var Utils = artifacts.require('./Utils')
var Vether = artifacts.require('./Vether')
var Vader = artifacts.require('./Vader')
var VUSD = artifacts.require('./VUSD')
var VAULT = artifacts.require('./Vault')
const BigNumber = require('bignumber.js')
const truffleAssert = require('truffle-assertions')

function BN2Str(BN) { return ((new BigNumber(BN)).toFixed()) }
function getBN(BN) { return (new BigNumber(BN)) }

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var utils; var vader; var vether; var vusd; var vault;
var acc0; var acc1; var acc2; var acc3; var acc0; var acc5;
const one = 10**18

// 

before(async function() {
  accounts = await ethers.getSigners();
  acc0 = await accounts[0].getAddress()
  acc1 = await accounts[1].getAddress()
  acc2 = await accounts[2].getAddress()
  acc3 = await accounts[3].getAddress()

  utils = await Utils.new();
  vether = await Vether.new();
  vader = await Vader.new(vether.address);
  vusd = await VUSD.new(vader.address, utils.address);
  vault = await VAULT.new(vader.address, vusd.address, utils.address);
  await vader.setVUSD(vusd.address)
  expect(await vader.VUSD()).to.equal(vusd.address);

  console.log('acc0:', acc0)
  console.log('acc1:', acc1)
  console.log('acc2:', acc2)
  console.log('utils:', utils.address)
  console.log('vether:', vether.address)
  console.log('vader:', vader.address)
  console.log('vusd:', vusd.address)
  console.log('vault:', vault.address)

  await vusd.setVault(vault.address)
  expect(await vusd.VAULT()).to.equal(vault.address);

  await vether.transfer(acc1, BN2Str(2002))
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |    0 |
// acc1 |2002 |    0 |    0 |

  let balance = await vether.balanceOf(acc1)
  await vether.approve(vader.address, balance, {from:acc1})
  await vader.upgrade(balance, {from:acc1}) 
})

// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 |  2000 |    0 |

describe("Deploy", function() {
  it("Should deploy", async function() {
    expect(await vusd.name()).to.equal("VADER USD");
    expect(await vusd.symbol()).to.equal("vUSD");
    expect(BN2Str(await vusd.decimals())).to.equal('18');
    expect(BN2Str(await vusd.totalSupply())).to.equal('0');
    expect(BN2Str(await vusd.currentEra())).to.equal('1');
    expect(BN2Str(await vusd.secondsPerEra())).to.equal('1');
    expect(await vusd.DAO()).to.equal(acc0);
    expect(await vusd.UTILS()).to.equal(utils.address);
  });
});

describe("Convert to VUSD", function() {

  it("Should convert acc1", async function() {
    let balance = await vader.balanceOf(acc1)
    await vusd.convert(balance/2, {from:acc1})
    expect(BN2Str(await vusd.totalSupply())).to.equal(BN2Str(1000));
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1000));
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(1000));
  });

// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |    0 |
// acc1 |   0 | 1000 | 1000 |

});

describe("Be a valid ERC-20", function() {
  it("Should transfer From", async function() {
    await vusd.approve(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vusd.allowance(acc1, acc0))).to.equal('100');
    await vusd.transferFrom(acc1, acc0, "100", {from:acc0})
    expect(BN2Str(await vusd.balanceOf(acc0))).to.equal('100');
  });
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  900 |

  it("Should transfer to", async function() {
    await vusd.transferTo(acc0, "100", {from:acc1}) 
    expect(BN2Str(await vusd.balanceOf(acc0))).to.equal('200');
  });
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |  200 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn", async function() {
    await vusd.burn("100", {from:acc0})
    expect(BN2Str(await vusd.balanceOf(acc0))).to.equal('100');
    expect(BN2Str(await vusd.totalSupply())).to.equal(BN2Str('900'));
  });
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |  100 |
// acc1 |   0 | 1000 |  800 |

  it("Should burn from", async function() {
    await vusd.approve(acc1, "100", {from:acc0}) 
    expect(BN2Str(await vusd.allowance(acc0, acc1))).to.equal('100');
    await vusd.burnFrom(acc0, "100", {from:acc1})
    expect(BN2Str(await vusd.balanceOf(acc0))).to.equal('0');
    expect(BN2Str(await vusd.totalSupply())).to.equal(BN2Str('800'));
  });
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |  0   |
// acc1 |   0 | 1000 |  800 |

});

describe("VUSD should redeem to VADER", function() {
  it("Should redeem", async function() {
    let balance = await vusd.balanceOf(acc1)
    await vader.redeem(balance/2, {from:acc1})
    expect(BN2Str(await vusd.totalSupply())).to.equal('400');
    expect(BN2Str(await vader.balanceOf(acc1))).to.equal(BN2Str(1400));
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal('400');
  });
});
// acc  | VTH | VDR  | VUSD |
// acc0 |   0 |    0 |  0   |
// acc1 |   0 | 1400 |  400 |

describe("Member should deposit for rewards", function() {
  it("Should deposit", async function() {
    await vusd.deposit('200', {from:acc1})
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(200));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(200));
    expect(BN2Str(await vusd.mapMember_deposit(acc1))).to.equal(BN2Str(200));
    expect(await vusd.isMember(acc1)).to.equal(true);
    expect(BN2Str(await vusd.totalFunds())).to.equal(BN2Str(200));
  });
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |    0 |  0   |   0 |
// acc1 |   0 | 1400 |  200 | 200 |

  it("Should calc rewards", async function() {
    let balanceStart = await vader.balanceOf(vusd.address)
    expect(BN2Str(balanceStart)).to.equal(BN2Str(0));
    await vader.startEmissions()
    await vader.changeEmissionCurve('1')
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('1400'));

    await vader.transfer(acc0, BN2Str(100), {from:acc1})
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |  100 |  0   |   0 |
// acc1 |   0 | 1300 |  200 | 200 |

    expect(BN2Str(await vader.currentEra())).to.equal(BN2Str(2));
    expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('2800'));

    expect(BN2Str(await vader.balanceOf(vusd.address))).to.equal(BN2Str(1400));

    await vusd.transfer(acc0, BN2Str(100), {from:acc1})
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |  100 |  100 |   0 |
// acc1 |   0 | 1300 |  100 | 200 |
// vusd |   0 | 467  |  933 |   0 |
    
    expect(BN2Str(await vusd.vUSDReserve())).to.equal(BN2Str(933));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1133));
    expect(BN2Str(await vader.balanceOf(vusd.address))).to.equal(BN2Str(467));

    expect(BN2Str(await vusd.calcPayment(acc1))).to.equal(BN2Str(9)); // 933/100
    expect(BN2Str(await vusd.calcCurrentPayment(acc1))).to.equal(BN2Str(36)); // * by seconds
  });
  it("Should harvest", async function() {
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(100));
    expect(BN2Str(await vusd.calcCurrentPayment(acc1))).to.equal(BN2Str(36)); // * by seconds
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1133));
    let tx = await vusd.harvest({from:acc1})
    //0: to member
    //1: burn, to 0
    //2: mint, to vusd
    //3: harvest
    // console.log(tx.logs[0].event)
    // console.log(tx.logs[0].args.from)
    // console.log(tx.logs[0].args.to)
    // console.log(BN2Str(tx.logs[0].args.value))

    // console.log(tx.logs[1].event)
    // console.log(tx.logs[1].args.from)
    // console.log(tx.logs[1].args.to)
    // console.log(BN2Str(tx.logs[1].args.value))

    // console.log(tx.logs[2].event)
    // console.log(tx.logs[2].args.from)
    // console.log(tx.logs[2].args.to)
    // console.log(BN2Str(tx.logs[2].args.value))
    
    // console.log(tx.logs[3].event)
    // console.log(tx.logs[3].args.member)
    // console.log(BN2Str(tx.logs[3].args.payment))
    
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(145));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1399));
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |  100 |  100 |   0 |
// acc1 |   0 | 1300 |  145 | 200 |
// vusd |   0 | 467  | 1399 |   0 |
  });
  it("Should withdraw 50%", async function() {
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(145));
    expect(BN2Str(await vusd.mapMember_deposit(acc1))).to.equal(BN2Str(200));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1399));
    let tx = await vusd.withdraw("5000",{from:acc1})
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(251));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1397));
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |  100 |  100 |   0 |
// acc1 |   0 | 1300 |  251 | 200 |
// vusd |   0 | 467  | 1397 |   0 |
  });
  it("Should withdraw 100%", async function() {
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(251));
    expect(BN2Str(await vusd.mapMember_deposit(acc1))).to.equal(BN2Str(107));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1397));
    let tx = await vusd.withdraw("10000",{from:acc1})
    expect(BN2Str(await vusd.mapMember_deposit(acc1))).to.equal(BN2Str(0));
    expect(BN2Str(await vusd.totalFunds())).to.equal(BN2Str(0));
    expect(BN2Str(await vusd.balanceOf(acc1))).to.equal(BN2Str(371));
    expect(BN2Str(await vusd.balanceOf(vusd.address))).to.equal(BN2Str(1311));
// acc  | VTH | VDR  | VUSD | DEP |
// acc0 |   0 |  100 |  100 |   0 |
// acc1 |   0 | 1300 |  251 | 200 |
// vusd |   0 | 467  | 1397 |   0 |
  });
});


// describe("DAO Functions", function() {
//   it("Non-DAO fails", async function() {
//     await truffleAssert.reverts(vader.startEmissions({from:acc1}))
//   });
//   it("DAO changeEmissionCurve", async function() {
//     await vader.changeEmissionCurve('1024')
//     expect(BN2Str(await vader.emissionCurve())).to.equal('1024');
//   });
//   it("DAO changeIncentiveAddress", async function() {
//     await vader.setVUSD(vusd.address)
//     expect(await vader.VUSD()).to.equal(vusd.address);
//   });
//   it("DAO changeDAO", async function() {
//     await vader.changeDAO(acc2)
//     expect(await vader.DAO()).to.equal(acc2);
//   });
//   it("DAO start emitting", async function() {
//     await vader.startEmissions({from:acc2})
//     expect(await vader.emitting()).to.equal(true);
//   });
  
//   it("Old DAO fails", async function() {
//     await truffleAssert.reverts(vader.startEmissions())
//   });
// });

// describe("Emissions", function() {
//   it("Should emit properly", async function() {
//     expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('9755859374999999999'));
//     // await sleep(2000)
//     await vader.transfer(acc0, BN2Str(one), {from:acc1})
//     await vader.transfer(acc1, BN2Str(one), {from:acc0})
//     expect(BN2Str(await vader.currentEra())).to.equal('3');
//     expect(BN2Str(await vader.balanceOf(vusd.address))).to.equal(BN2Str('19521245956420898435'));
//     expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('9774923091754317282'));
    
//     await sleep(2000)
//     await vader.transfer(acc0, BN2Str(one), {from:acc1})
//     expect(BN2Str(await vader.currentEra())).to.equal('4');
//     expect(BN2Str(await vader.balanceOf(vusd.address))).to.equal(BN2Str('29296169048175215717'));
//     expect(BN2Str(await vader.getDailyEmission())).to.equal(BN2Str('9784468915086108608'));
//   });

//   it("DAO changeEraDuration", async function() {
//     await vader.changeEraDuration('200',{from:acc2})
//     expect(BN2Str(await vader.secondsPerEra())).to.equal('200');
//   });
// });


