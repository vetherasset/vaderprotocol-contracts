# Vader Protocol - Incentivised Liquidity, Stablecoin and Lending Protocol.

VADER is a liquidity protocol that combines a collateralized stablecoin with liquidity pools. The stablecoin, USDV, is issued by burning VADER tokens, which is issued by burning VETH tokens. Liquidity pools use USDV as the settlement asset. A daily emission rate of VADER funds liquidity incentives, a protocol interest rate, and impermanent loss protection. Pooled capital can be lent out by borrowers, who lock collateral such as pool shares or VADER. The collateral is used to pay an interest rate which is added into the pools to increase returns. 

## Smart Contracts

VADER (VADER)
* 1m to VETH holders
* 2m maxSupply
* Burn USDV to get VADER
* Daily Emission Rate

VADER USD (USDV)
* Burn VADER to get USDV
* Deposit USDV to get interest rate
* Harvest, withdraw
* Has a reserve for interest payments

POOLS
* Add liquidity to Asset or Anchor pools
* Remove liquidity with 100 Days IL Protection
* Swap between Asset <> USDV <> VADER <> Anchor
* Get Anchor pricing, replace any Anchor
* Borrow debt from locked collateral, repay
* Has a reserve to pay incentives

### Setup

* Deploy UTILS
* Deploy VETHER
* Deploy VADER(vether.address)
* Deploy USDV(vader.address, utils.address)
* Deploy POOLS(vader.address, usdv.address, utils.address)
* Set VADER.setUSDV(USDV.address)
* Set USDV.setPools(pools.address)

## Addresses

### Kovan
0xdA9e97139937BaD5e6d1d1aBB4C9Ab937a432B7C vether
0x3CF73D6E97cB3A8EA3aEd66E0AE22e0257CD1100 USDT

#### Mainnet
0x4Ba6dDd7b89ed838FEd25d208D4f644106E34279 vether



## Helpers


```
1000000000000000000 // 10**18
1000000000000000000000000 //1m
0x0000000000000000000000000000000000000000
```

## Testing - Buidler

The test suite uses [Buidler](https://buidler.dev/) as the preferred testing suite, since it compiles and tests faster. 
The test suite implements 7 routines that can be tested individually.

```
npx buidler compile
```

Execute all at once:
```
npx builder test
```

Or execute individually:
```
npx builder test/1_vader.js
```
