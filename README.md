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

VAULT
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
* Deploy VAULT(vader.address, usdv.address, utils.address)
* Set VADER.setVSD(USDV.address)
* Set USDV.setVault(vault.address)

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

### Core Math

```solidity

function  calcSwapOutput(uint x, uint X, uint Y) public pure returns (uint output){
        // y = (x * Y * X)/(x + X)^2
        uint numerator = x.mul(Y.mul(X));
        uint denominator = (x.add(X)).mul(x.add(X));
        return numerator.div(denominator);
    }

    function  calcSwapFee(uint x, uint X, uint Y) public pure returns (uint output){
        // y = (x * Y * x) / (x + X)^2
        uint numerator = x.mul(Y.mul(x));
        uint denominator = (x.add(X)).mul(x.add(X));
        return numerator.div(denominator);
    }

    function calcStakeUnits(uint a, uint A, uint v, uint V) public pure returns (uint units){
        // units = ((V + A) * (v * A + V * a))/(4 * V * A)
        // (part1 * (part2 + part3)) / part4
        uint part1 = V.add(A);
        uint part2 = v.mul(A);
        uint part3 = V.mul(a);
        uint numerator = part1.mul((part2.add(part3)));
        uint part4 = 4 * (V.mul(A));
        return numerator.div(part4);
    }

    function calcAsymmetricShare(uint s, uint T, uint A) public pure returns (uint share){
        // share = (s * A * (2 * T^2 - 2 * T * s + s^2))/T^3
        // (part1 * (part2 - part3 + part4)) / part5
        uint part1 = s.mul(A);
        uint part2 = T.mul(T).mul(2);
        uint part3 = T.mul(s).mul(2);
        uint part4 = s.mul(s);
        uint numerator = part1.mul(part2.sub(part3).add(part4));
        uint part5 = T.mul(T).mul(T);
        return numerator.div(part5);
    }
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
