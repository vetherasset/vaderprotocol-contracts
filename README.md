# Vader Protocol - Incentivised Liquidity, Stablecoin and Lending Protocol.

VADER is a liquidity protocol that combines a collateralized stablecoin with liquidity pools. The stablecoin, USDV, is issued by burning VADER tokens, which is issued by burning VETH tokens. Liquidity pools use both USDV as the settlement asset, as well as VADER in order to send the correct purchasing power of VADER. A daily emission rate of VADER funds liquidity incentives, a protocol interest rate, and impermanent loss protection. Pooled capital can be lent out by borrowers, who lock collateral such as synths, pool share or VADER. The collateral is used to pay an interest rate which is added into the pools to increase returns. 

## Smart Contracts

VADER (VADER)
* 1,000,000,000 to VETH holders
* 2,000,000,000 maxSupply
* Burn USDV to get VADER
* Daily Emission Rate

VADER USD (USDV)
* Burn VADER to get USDV
* Deposit USDV/SYNTHS to get interest rate
* Harvest, withdraw
* Has a reserve for interest payments

ROUTER 
* Add liquidity to Asset or Anchor pools
* Remove liquidity with 100 Days IL Protection
* Swap between Asset <> USDV or VADER <> Anchor
* Get Anchor pricing, replace any Anchor
* Borrow debt from locked collateral, repay
* Has a reserve to pay incentives

POOLS
* Stores funds and member details for the pools

FACTORY
* Deploys Synthetic Assets

SYNTH
* ERC20 for Synths

DAO
* Has Governance Ability on the ecosystem, senses Weight in the USDV Contract

UTILS
* Various utility functions

### Setup
All contracts need to be initialised for the first time, else the system will not work. 

```
await utils.init(pools.address)
 
await usdv.init(vader.address)
  await dao.init(vether.address, vader.address, usdv.address, reserve.address,
    vault.address, router.address, lender.address, pools.address, factory.address, utils.address);
 
  await vader.changeDAO(dao.address)
await reserve.init(vader.address)
  
    await vader.changeDAO(dao.address)
await reserve.init(vader.address)
    await vault.init(vader.address)
await router.init(vader.address);
await pools.init(vader.address);
await factory.init(pools.address);
```


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
0x0000000000000000000000000000000000000000 /0x0
```

## Testing - Hardhat

```
npx hardhat compile
```

Execute all at once:
```
npx hardhat test
```

Or execute individually:
```
npx hardhat test test/1_vader
```

## CI Pipeline
Github Actions are used to perform a number of automated code quality checks. 

#### Executing/Debugging the Pipeline Locally 
These checks can be run locally by installing the [act](https://github.com/nektos/act) utility.
The default suggested image (medium) supplied with `act` does not contain the necessary dependencies to run 
Vader's pipeline.  Instead, use the larger (18GB~) image using:

```act -vP ubuntu-latest=nektos/act-environments-ubuntu:18.04```

This will download a more complete image with the required dependencies, 
and run the pipeline as defined in [.github/workflows/build.yml](.github/workflows/build.yml).
