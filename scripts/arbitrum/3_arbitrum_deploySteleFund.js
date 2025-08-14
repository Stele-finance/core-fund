const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFund Ecosystem Deployment on Arbitrum...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses
  const steleTokenAddress = "0xF26A6c38E011E428B2DaC5E874BF26fb12665136"; // Existing STELE token on Arbitrum
  const timeLockAddress = "YOUR_TIMELOCK_ADDRESS"; // From step 1
  const wethTokenAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // Arbitrum WETH

  console.log(`🎯 Stele Token: ${steleTokenAddress}`);
  console.log(`💰 WETH: ${wethTokenAddress}`);
  console.log(`🏛️ TimeLock: ${timeLockAddress}\n`);

  // Step 1: Deploy SteleFundSetting
  console.log("📝 Step 1: Deploying SteleFundSetting on Arbitrum...");
  const SteleFundSetting = await ethers.getContractFactory("SteleFundSetting");
  const steleFundSetting = await SteleFundSetting.deploy(
    steleTokenAddress,
    wethTokenAddress
  );
  await steleFundSetting.waitForDeployment();
  const steleFundSettingAddress = await steleFundSetting.getAddress();
  console.log(`✅ SteleFundSetting deployed at: ${steleFundSettingAddress}\n`);

  // Step 2: Deploy SteleFundInfo
  console.log("📊 Step 2: Deploying SteleFundInfo on Arbitrum...");
  const SteleFundInfo = await ethers.getContractFactory("SteleFundInfo");
  const steleFundInfo = await SteleFundInfo.deploy();
  await steleFundInfo.waitForDeployment();
  const steleFundInfoAddress = await steleFundInfo.getAddress();
  console.log(`✅ SteleFundInfo deployed at: ${steleFundInfoAddress}\n`);

  // Step 3: Deploy SteleFund with all required addresses
  console.log("💼 Step 3: Deploying SteleFund on Arbitrum...");
  const SteleFund = await ethers.getContractFactory("SteleFund");
  const steleFund = await SteleFund.deploy(
    wethTokenAddress,
    steleFundSettingAddress,
    steleFundInfoAddress
  );
  await steleFund.waitForDeployment();
  const steleFundAddress = await steleFund.getAddress();
  console.log(`✅ SteleFund deployed at: ${steleFundAddress}\n`);

  // Step 4: Set SteleFundInfo owner to SteleFund
  console.log("🔗 Step 4: Setting SteleFundInfo owner to SteleFund...");
  const infoOwnershipTx = await steleFundInfo.setOwner(steleFundAddress);
  await infoOwnershipTx.wait();
  console.log(`✅ SteleFundInfo ownership transferred to: ${steleFundAddress}\n`);

  // Step 5: Transfer SteleFundSetting ownership to TimeLock
  console.log("🏛️ Step 5: Transferring SteleFundSetting ownership to TimeLock...");
  try {
    const ownershipTx = await steleFundSetting.setOwner(timeLockAddress);
    await ownershipTx.wait();
    console.log(`✅ SteleFundSetting ownership transferred to: ${timeLockAddress}\n`);
  } catch (error) {
    console.log("⚠️  Ownership transfer skipped (update TimeLock address manually)\n");
  }

  // Step 6: Verify setup
  console.log("🔍 Step 6: Verifying deployment...");
  const currentOwner = await steleFundSetting.owner();
  const infoOwner = await steleFundInfo.owner();
  const weth9 = await steleFundSetting.weth9();
  const stele = await steleFundSetting.stele();
  
  console.log("🎯 Verification Results:");
  console.log(`   SteleFundSetting owner: ${currentOwner}`);
  console.log(`   SteleFundInfo owner: ${infoOwner}`);
  console.log(`   WETH9: ${weth9}`);
  console.log(`   STELE: ${stele}`);
  console.log(`   Governance enabled: ${currentOwner === timeLockAddress}`);
  console.log(`   Info ownership correct: ${infoOwner === steleFundAddress}\n`);

  // Final Summary
  console.log("🎉 DEPLOYMENT COMPLETE ON ARBITRUM! 🎉");
  console.log("=".repeat(60));
  console.log(`📝 SteleFundSetting: ${steleFundSettingAddress}`);
  console.log(`💼 SteleFund: ${steleFundAddress}`);
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log(`🏛️ Governance: ${currentOwner === timeLockAddress ? '✅ Enabled' : '❌ Disabled'}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "arbitrum",
    contracts: {
      SteleFundSetting: steleFundSettingAddress,
      SteleFund: steleFundAddress,
      SteleFundInfo: steleFundInfoAddress,
      SteleToken: steleTokenAddress,
      WETH: wethTokenAddress,
      TimeLock: timeLockAddress
    },
    governance: {
      enabled: currentOwner === timeLockAddress,
      owner: currentOwner
    },
    transactions: {
      steleFundSetting: steleFundSetting.deploymentTransaction().hash,
      steleFund: steleFund.deploymentTransaction().hash,
      steleFundInfo: steleFundInfo.deploymentTransaction().hash
    }
  };

  console.log("\n📋 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });