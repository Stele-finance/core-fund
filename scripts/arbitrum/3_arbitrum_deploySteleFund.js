const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFund Ecosystem Deployment on Arbitrum...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses
  const steleTokenAddress = "0xb4fb28a64c946c909d86388be279f8222fd42599"; // Existing STELE token on Arbitrum
  const timeLockAddress = "0x1ea89dC5FD40F5c15313b77E12833563F6C33730"; // From step 1
  const wethTokenAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // Arbitrum WETH
  const usdcTokenAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"; // Arbitrum USDC

  console.log(`🎯 Stele Token: ${steleTokenAddress}`);
  console.log(`💰 WETH: ${wethTokenAddress}`);
  console.log(`🏛️ TimeLock: ${timeLockAddress}`);

  // Step 1: Deploy SteleFundSetting
  console.log("📝 Step 2: Deploying SteleFundSetting on Arbitrum...");
  const SteleFundSetting = await ethers.getContractFactory("SteleFundSetting");
  const steleFundSetting = await SteleFundSetting.deploy(
    wethTokenAddress,
    usdcTokenAddress
  );
  await steleFundSetting.deployed();
  const steleFundSettingAddress = await steleFundSetting.address;
  console.log("✅ SteleFundSetting deployed to:", steleFundSettingAddress);

  // Step 2: Deploy SteleFundInfo
  console.log("📊 Step 2: Deploying SteleFundInfo on Arbitrum...");
  const SteleFundInfo = await ethers.getContractFactory("SteleFundInfo");
  const steleFundInfo = await SteleFundInfo.deploy();
  await steleFundInfo.deployed();
  const steleFundInfoAddress = await steleFundInfo.address;
  console.log(`✅ SteleFundInfo deployed at: ${steleFundInfoAddress}\n`);

  // Step 3: Deploy SteleFund
  console.log("💼 Step 3: Deploying SteleFund on Arbitrum...");
  const SteleFund = await ethers.getContractFactory("SteleFund");
  const steleFund = await SteleFund.deploy(
    wethTokenAddress,
    steleFundSettingAddress,
    steleFundInfoAddress,
    usdcTokenAddress
  );
  await steleFund.deployed();
  const steleFundAddress = await steleFund.address;
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
  const usdc = await steleFundSetting.usdc();

  console.log("🎯 Verification Results:");
  console.log(`   SteleFundSetting owner: ${currentOwner}`);
  console.log(`   SteleFundInfo owner: ${infoOwner}`);
  console.log(`   WETH9: ${weth9}`);
  console.log(`   USDC: ${usdc}`);
  console.log(`   Governance enabled: ${currentOwner === timeLockAddress}`);
  console.log(`   Info ownership correct: ${infoOwner === steleFundAddress}\n`);

  // Final Summary
  console.log("🎉 DEPLOYMENT COMPLETE ON ARBITRUM! 🎉");
  console.log("=".repeat(60));
  console.log(`📝 SteleFundSetting: ${steleFundSettingAddress}`);
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log(`💼 SteleFund: ${steleFundAddress}`);
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
      steleFundSetting: steleFundSetting.deploymentTransaction,
      steleFund: steleFund.deploymentTransaction,
      steleFundInfo: steleFundInfo.deploymentTransaction
    }
  };

  console.log("\n📋 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));
}

main()
  .then(() => console.log("✅ Deployment completed successfully"))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
  });