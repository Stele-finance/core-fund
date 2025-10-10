const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFund Ecosystem Deployment on mainnet...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // mainnet addresses
  const steleTokenAddress = "0xc4f1E00cCfdF3a068e2e6853565107ef59D96089"; // Existing STELE token on mainnet
  const timeLockAddress = "0x523AeaBc48aFc09c881e9Ff87f9A4FeB63817f69"; // From step 1
  const wethTokenAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // mainnet WETH
  const usdcTokenAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // mainnet USDC

  console.log(`🎯 Stele Token: ${steleTokenAddress}`);
  console.log(`💰 WETH: ${wethTokenAddress}`);
  console.log(`🏛️ TimeLock: ${timeLockAddress}`);

  // Step 1: Deploy SteleFundSetting
  console.log("📝 Step 2: Deploying SteleFundSetting on mainnet...");
  const SteleFundSetting = await ethers.getContractFactory("SteleFundSetting");
  const steleFundSetting = await SteleFundSetting.deploy(
    wethTokenAddress,
    usdcTokenAddress
  );
  await steleFundSetting.deployed();
  const steleFundSettingAddress = await steleFundSetting.address;
  console.log("✅ SteleFundSetting deployed to:", steleFundSettingAddress);

  // Step 2: Deploy SteleFundInfo
  console.log("📊 Step 2: Deploying SteleFundInfo on mainnet...");
  const SteleFundInfo = await ethers.getContractFactory("SteleFundInfo");
  const steleFundInfo = await SteleFundInfo.deploy();
  await steleFundInfo.deployed();
  const steleFundInfoAddress = await steleFundInfo.address;
  console.log(`✅ SteleFundInfo deployed at: ${steleFundInfoAddress}\n`);

  // Step 3: Deploy SteleFund
  console.log("💼 Step 3: Deploying SteleFund on mainnet...");
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
  console.log("🎉 DEPLOYMENT COMPLETE ON MAINNET! 🎉");
  console.log("=".repeat(60));
  console.log(`📝 SteleFundSetting: ${steleFundSettingAddress}`);
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log(`💼 SteleFund: ${steleFundAddress}`);
  console.log(`🏛️ Governance: ${currentOwner === timeLockAddress ? '✅ Enabled' : '❌ Disabled'}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "mainnet",
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