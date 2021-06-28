const secret = require("../.secret.json");

async function main() {
  // We get the contract to deploy
  const Vether = await ethers.getContractFactory("Vether");
  const Vader = await ethers.getContractFactory("Vader");
  const USDV = await ethers.getContractFactory("USDV");
  const Reserve = await ethers.getContractFactory("Reserve");
  const Vault = await ethers.getContractFactory("Vault");
  const Router = await ethers.getContractFactory("Router");
  const Lender = await ethers.getContractFactory("Lender");
  const Pools = await ethers.getContractFactory("Pools");
  const Factory = await ethers.getContractFactory("Factory");
  const Utils = await ethers.getContractFactory("Utils");
  const DAO = await ethers.getContractFactory("DAO");
  
  //========================================= VETHER =========================================
  console.log("Deploying Vether...");
  const vether = await Vether.deploy();
  await vether.deployed();
  console.log("Vether deployed to:", vether.address);
  
  //========================================= VADER ==========================================
  console.log("Deploying Vader...");
  const vader = await Vader.deploy();
  await vader.deployed();
  console.log("Vader deployed to:", vader.address);
  
  //========================================= RESERVE ========================================
  console.log("Deploying Reserve...");
  const reserve = await Reserve.deploy();
  await reserve.deployed();
  console.log("Reserve deployed to:", reserve.address);
  
  //========================================== USDV ==========================================
  console.log("Deploying USDV...");
  const usdv = await USDV.deploy(vader.address);
  await usdv.deployed();
  console.log("USDV deployed to:", usdv.address);
  
  //========================================= VAULT ==========================================
  console.log("Deploying Vault...");
  const vault = await Vault.deploy(vader.address);
  await vault.deployed();
  console.log("Vault deployed to:", vault.address);
  
  //========================================= ROUTER =========================================
  console.log("Deploying Router...");
  const router = await Router.deploy(vader.address);
  await router.deployed();
  console.log("Router deployed to:", router.address);
  
  //========================================= LENDER =========================================
  console.log("Deploying Lender...");
  const lender = await Lender.deploy(vader.address);
  await lender.deployed();
  console.log("Lender deployed to:", lender.address);
  
  //========================================= POOLS ==========================================
  console.log("Deploying Pools...");
  const pools = await Pools.deploy(vader.address);
  await pools.deployed();
  console.log("Pools deployed to:", pools.address);
  
  //========================================= FACTORY ========================================
  console.log("Deploying Factory...");
  const factory = await Factory.deploy(pools.address);
  await factory.deployed();
  console.log("Factory deployed to:", factory.address);
  
  //========================================= UTILS ==========================================
  console.log("Deploying Utils...");
  const utils = await Utils.deploy(vader.address);
  await utils.deployed();
  console.log("Utils deployed to:", utils.address);
  
  //========================================== DAO ===========================================
  console.log("Deploying DAO...");
  const dao = await DAO.deploy();
  await dao.deployed();
  console.log("DAO deployed to:", dao.address);

  //==================================== Verify Contracts ====================================
  await run("verify:verify", { address: vether.address });
  await run("verify:verify", { address: vader.address });
  await run("verify:verify", { address: reserve.address });
  await run("verify:verify", { address: usdv.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: vault.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: router.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: lender.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: pools.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: factory.address, constructorArguments: [pools.address] });
  await run("verify:verify", { address: utils.address, constructorArguments: [vader.address] });
  await run("verify:verify", { address: dao.address });

  //==================================== Init Contracts ======================================
  await dao.init(
    vether.address,
    vader.address,
    usdv.address,
    reserve.address,
    vault.address,
    router.address,
    lender.address,
    pools.address,
    factory.address,
    utils.address
  );
  await vader.changeDAO(dao.address);
  await reserve.init(vader.address);

  //======================================= ADDRESSES ========================================
  console.log('================================== Contracts ==================================');
  console.log('Deployer: ', secret.address);
  console.log('Vether: ', vether.address);
  console.log('Vader: ', vader.address);
  console.log('USDV: ', usdv.address);
  console.log('Reserve: ', reserve.address);
  console.log('Vault: ', vault.address);
  console.log('Router: ', router.address);
  console.log('Lender: ', lender.address);
  console.log('Pools: ', pools.address);
  console.log('Factory: ', factory.address);
  console.log('Utils: ', utils.address);
  console.log('DAO: ', dao.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });