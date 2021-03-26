/*
################################################
Creates 3 tokens and stakes them
################################################
*/

const assert = require("chai").assert;
const truffleAssert = require('truffle-assertions');
var BigNumber = require('bignumber.js');

const _ = require('./utils.js');
const math = require('./math.js');
const help = require('./helper.js');

var BASE = artifacts.require("./BaseMinted.sol");
var DAO = artifacts.require("./Dao.sol");
var ROUTER = artifacts.require("./Router.sol");
var POOL = artifacts.require("./Pool.sol");
var UTILS = artifacts.require("./Utils.sol");
var TOKEN1 = artifacts.require("./Token1.sol");

var base; var token1;  var token2; var addr1; var addr2;
var utils; var router; var Dao;
var poolETH; var poolTKN1; var poolTKN2;
var acc0; var acc1; var acc2; var acc3;

contract('BASE', function (accounts) {
    acc0 = accounts[0]; acc1 = accounts[1]; acc2 = accounts[2]; acc3 = accounts[3]
    createPool()
    

    stake(acc1, _.BN2Str(_.one * 10), _.dot1BN)
    swapBASEToETH(acc0, _.BN2Str(_.one * 10))
    // stake(acc0, _.BN2Str(_.one * 10), _.dot1BN)
    unstakeETH(5000, acc1)
    swapBASEToETH(acc0, _.BN2Str(_.one * 10))
    stake(acc0, _.BN2Str(_.one * 10), _.dot1BN)
    unstakeETH(10000, acc1)
    unstakeETH(10000, acc0)

})

before(async function() {
    accounts = await ethers.getSigners();
    acc0 = await accounts[0].getAddress(); 
    acc1 = await accounts[1].getAddress(); 
    acc2 = await accounts[2].getAddress(); 
    acc3 = await accounts[3].getAddress()

    base = await BASE.new()
    utils = await UTILS.new(base.address)
    Dao = await DAO.new(base.address)
    router = await ROUTER.new(base.address)
    await base.changeDAO(Dao.address)
    await Dao.setGenesisAddresses(router.address, utils.address)
    // assert.equal(await Dao.DEPLOYER(), '0x0000000000000000000000000000000000000000', " deployer purged")
    console.log(await utils.BASE())
    console.log(await Dao.ROUTER())

    token1 = await TOKEN1.new();
    token2 = await TOKEN1.new();

    console.log(`Acc0: ${acc0}`)
    console.log(`base: ${base.address}`)
    console.log(`dao: ${Dao.address}`)
    console.log(`utils: ${utils.address}`)
    console.log(`router: ${router.address}`)
    console.log(`token1: ${token1.address}`)

    await base.transfer(acc1, _.getBN(_.BN2Str(100000 * _.one)))
    await base.transfer(acc1, _.getBN(_.BN2Str(100000 * _.one)))
    await base.approve(router.address, _.BN2Str(500000 * _.one), { from: acc0 })
    await base.approve(router.address, _.BN2Str(500000 * _.one), { from: acc1 })
    await base.approve(router.address, _.BN2Str(500000 * _.one), { from: acc2 })

    let supplyT1 = await token1.totalSupply()
    await token1.transfer(acc1, _.getBN(_.BN2Int(supplyT1)/2))
    await token2.transfer(acc1, _.getBN(_.BN2Int(supplyT1)/2))
    await token1.approve(router.address, supplyT1, { from: acc0 })
    await token1.approve(router.address, supplyT1, { from: acc1 })
    await token2.approve(router.address, supplyT1, { from: acc0 })
    await token2.approve(router.address, supplyT1, { from: acc1 })
})

async function createPool() {
    it("It should deploy Eth Pool", async () => {
        var _pool = await router.createPool.call(_.BN2Str(_.one * 10), _.dot1BN, _.ETH, { value: _.dot1BN })
        await router.createPool(_.BN2Str(_.one * 10), _.dot1BN, _.ETH, { value: _.dot1BN })
        poolETH = await POOL.at(_pool)
        console.log(`Pools: ${poolETH.address}`)
        const baseAddr = await poolETH.BASE()
        assert.equal(baseAddr, base.address, "address is correct")
        assert.equal(_.BN2Str(await base.balanceOf(poolETH.address)), _.BN2Str(_.one * 10), 'base balance')
        assert.equal(_.BN2Str(await web3.eth.getBalance(poolETH.address)), _.BN2Str(_.dot1BN), 'ether balance')

        let supply = await base.totalSupply()
        await base.approve(poolETH.address, supply, { from: acc0 })
        await base.approve(poolETH.address, supply, { from: acc1 })
    })

    it("It should deploy TKN1 Pools", async () => {

        await token1.approve(router.address, '-1', { from: acc0 })
        var _pool = await router.createPool.call(_.BN2Str(_.one * 10), _.BN2Str(_.one * 100), token1.address)
        await router.createPool(_.BN2Str(_.one * 10), _.BN2Str(_.one * 100), token1.address)
        poolTKN1 = await POOL.at(_pool)
        console.log(`Pools1: ${poolTKN1.address}`)
        const baseAddr = await poolTKN1.BASE()
        assert.equal(baseAddr, base.address, "address is correct")

        await base.approve(poolTKN1.address, '-1', { from: acc0 })
        await base.approve(poolTKN1.address, '-1', { from: acc1 })
        await token1.approve(poolTKN1.address, '-1', { from: acc0 })
        await token1.approve(poolTKN1.address, '-1', { from: acc1 })
    })
    it("It should deploy TKN2 Pools", async () => {

        await token2.approve(router.address, '-1', { from: acc0 })
        var _pool = await router.createPool.call(_.BN2Str(_.one * 10), _.BN2Str(_.one * 100), token2.address)
        await router.createPool(_.BN2Str(_.one * 10), _.BN2Str(_.one * 100), token2.address)
        poolTKN2 = await POOL.at(_pool)
        console.log(`Pools2: ${poolTKN2.address}`)
        const baseAddr = await poolTKN2.BASE()
        assert.equal(baseAddr, base.address, "address is correct")

        await base.approve(poolTKN2.address, '-1', { from: acc0 })
        await base.approve(poolTKN2.address, '-1', { from: acc1 })
        await token2.approve(poolTKN2.address, '-1', { from: acc0 })
        await token2.approve(poolTKN2.address, '-1', { from: acc1 })
    })
}

async function stake(acc, b, t) {

    it(`It should stake ETH from ${acc}`, async () => {
        let token = _.ETH
        let pool = poolETH
        let poolData = await utils.getPoolData(token);
        var S = _.getBN(poolData.baseAmt)
        var T = _.getBN(poolData.tokenAmt)
        poolUnits = _.getBN((await pool.totalSupply()))
        console.log('start data', _.BN2Str(S), _.BN2Str(T), _.BN2Str(poolUnits))

        let units = math.calcStakeUnits(t, T.plus(t), b, S.plus(b))
        console.log(_.BN2Str(units), _.BN2Str(b), _.BN2Str(S.plus(b)), _.BN2Str(t), _.BN2Str(T.plus(t)))
        
        let tx = await router.stake(b, t, token, { from: acc, value: t })
        poolData = await utils.getPoolData(token);
        assert.equal(_.BN2Str(poolData.baseAmt), _.BN2Str(S.plus(b)))
        assert.equal(_.BN2Str(poolData.tokenAmt), _.BN2Str(T.plus(t)))
        assert.equal(_.BN2Str((await pool.totalSupply())), _.BN2Str(units.plus(poolUnits)), 'poolUnits')
        // assert.equal(_.BN2Str(await pool.balanceOf(acc)), _.BN2Str(units), 'units')
        assert.equal(_.BN2Str(await base.balanceOf(pool.address)), _.BN2Str(S.plus(b)), 'base balance')
        assert.equal(_.BN2Str(await web3.eth.getBalance(pool.address)), _.BN2Str(T.plus(t)), 'ether balance')

        const tokenBal = _.BN2Token(await web3.eth.getBalance(pool.address));
        const baseBal = _.BN2Token(await base.balanceOf(pool.address));
        console.log(`BALANCES: [ ${tokenBal} ETH | ${baseBal} SPT ]`)
    })
}


async function swapBASEToETH(acc, b) {

    it(`It should buy ETH with BASE from ${acc}`, async () => {
        let token = _.ETH
        let poolData = await utils.getPoolData(token);
        const B = _.getBN(poolData.baseAmt)
        const T = _.getBN(poolData.tokenAmt)
        console.log('start data', _.BN2Str(B), _.BN2Str(T))

        let t = math.calcSwapOutput(b, B, T)
        let fee = math.calcSwapFee(b, B, T)
        console.log(_.BN2Str(t), _.BN2Str(T), _.BN2Str(B), _.BN2Str(b), _.BN2Str(fee))
        
        let tx = await router.buy(b, _.ETH)
        poolData = await utils.getPoolData(token);

        assert.equal(_.BN2Str(tx.receipt.logs[0].args.inputAmount), _.BN2Str(b))
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.outputAmount), _.BN2Str(t))
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.fee), _.BN2Str(fee))

        assert.equal(_.BN2Str(poolData.tokenAmt), _.BN2Str(T.minus(t)))
        assert.equal(_.BN2Str(poolData.baseAmt), _.BN2Str(B.plus(b)))

        assert.equal(_.BN2Str(await web3.eth.getBalance(poolETH.address)), _.BN2Str(T.minus(t)), 'ether balance')
        assert.equal(_.BN2Str(await base.balanceOf(poolETH.address)), _.BN2Str(B.plus(b)), 'base balance')

        await help.logPool(utils, _.ETH, 'ETH')
    })
}

async function swapETHToBASE(acc, t) {

    it(`It should sell ETH to BASE from ${acc}`, async () => {
        let token = _.ETH
        await help.logPool(utils, token, 'ETH')
        let poolData = await utils.getPoolData(token);
        const B = _.getBN(poolData.baseAmt)
        const T = _.getBN(poolData.tokenAmt)
        // console.log('start data', _.BN2Str(B), _.BN2Str(T), stakerCount, _.BN2Str(poolUnits))
        console.log(poolData)

        let b = math.calcSwapOutput(t, T, B)
        let fee = math.calcSwapFee(t, T, B)
        console.log(_.BN2Str(t), _.BN2Str(T), _.BN2Str(B), _.BN2Str(b), _.BN2Str(fee))
        
        let tx = await router.sell(t, token, { from: acc, value: t })
        poolData = await utils.getPoolData(token);
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.inputAmount), _.BN2Str(t))
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.outputAmount), _.BN2Str(b))
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.fee), _.BN2Str(fee))
        console.log(poolData)
        assert.equal(_.BN2Str(poolData.tokenAmt), _.BN2Str(T.plus(t)))
        assert.equal(_.BN2Str(poolData.baseAmt), _.BN2Str(B.minus(b)))
        


        assert.equal(_.BN2Str(await web3.eth.getBalance(poolETH.address)), _.BN2Str(T.plus(t)), 'ether balance')
        assert.equal(_.BN2Str(await base.balanceOf(poolETH.address)), _.BN2Str(B.minus(b)), 'base balance')

        await help.logPool(utils, token, 'ETH')
    })
}


async function unstakeETH(bp, acc) {

    it(`It should unstake ETH for ${acc}`, async () => {
        let poolROI = await utils.getPoolROI(_.ETH)
        console.log('poolROI-ETH', _.BN2Str(poolROI))
        let poolAge = await utils.getPoolAge(_.ETH)
        console.log('poolAge-ETH', _.BN2Str(poolAge))
        let poolAPY = await utils.getPoolAPY(_.ETH)
        console.log('poolAPY-ETH', _.BN2Str(poolAPY))
        // let memberROI0 = await utils.getMemberROI(_.ETH, acc0)
        // console.log('memberROI0', _.BN2Str(memberROI0))
        // let memberROI1 = await utils.getMemberROI(_.ETH, acc1)
        // console.log('memberROI1', _.BN2Str(memberROI1))

        let poolData = await utils.getPoolData(_.ETH);
        var B = _.getBN(poolData.baseAmt)
        var T = _.getBN(poolData.tokenAmt)

        let totalUnits = _.getBN((await poolETH.totalSupply()))
        let stakerUnits = _.getBN(await poolETH.balanceOf(acc))
        let share = (stakerUnits.times(bp)).div(10000)
        let b = _.floorBN((B.times(share)).div(totalUnits))
        let t = _.floorBN((T.times(share)).div(totalUnits))
        // let vs = poolData.baseStaked
        // let as = poolData.tokenStaked
        // let vsShare = _.floorBN((B.times(share)).div(totalUnits))
        // let asShare = _.floorBN((T.times(share)).div(totalUnits))
        console.log(_.BN2Str(totalUnits), _.BN2Str(stakerUnits), _.BN2Str(share), _.BN2Str(b), _.BN2Str(t))
        
        let tx = await router.unstake(bp, _.ETH, { from: acc})
        poolData = await utils.getPoolData(_.ETH);

        assert.equal(_.BN2Str(tx.receipt.logs[0].args.outputBase), _.BN2Str(b), 'outputBase')
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.outputToken), _.BN2Str(t), 'outputToken')
        assert.equal(_.BN2Str(tx.receipt.logs[0].args.unitsClaimed), _.BN2Str(share), 'unitsClaimed')

        assert.equal(_.BN2Str((await poolETH.totalSupply())), totalUnits.minus(share), 'poolUnits')

        assert.equal(_.BN2Str(poolData.baseAmt), _.BN2Str(B.minus(b)))
        assert.equal(_.BN2Str(poolData.tokenAmt), _.BN2Str(T.minus(t)))
        assert.equal(_.BN2Str(await base.balanceOf(poolETH.address)), _.BN2Str(B.minus(b)), 'base balance')
        assert.equal(_.BN2Str(await web3.eth.getBalance(poolETH.address)), _.BN2Str(T.minus(t)), 'ether balance')

        let stakerUnits2 = _.getBN(await poolETH.balanceOf(acc))
        assert.equal(_.BN2Str(stakerUnits2), _.BN2Str(stakerUnits.minus(share)), 'stakerUnits')
    })
}


async function logETH() {
    it("logs", async () => {
        // await help.logPool(utils, _.ETH, 'ETH')
    })
}
function logTKN1() {
    it("logs", async () => {
        // await help.logPool(utils, token1.address, 'TKN1')
    })
}function logTKN2() {
    it("logs", async () => {
        // await help.logPool(utils, token2.address, 'TKN2')
    })
}
