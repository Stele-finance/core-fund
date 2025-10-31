const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFund Ecosystem Deployment on mainnet...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // mainnet addresses
  const wethTokenAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // mainnet WETH
  const usdcTokenAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // mainnet USDC
  const wbtcTokenAddress = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"; // mainnet WBTC
  const uniTokenAddress = "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"; // mainnet UNI
  const linkTokenAddress = "0x514910771AF9Ca656af840dff83E8264EcF986CA"; // mainnet LINK

  console.log(`💰 WETH: ${wethTokenAddress}`);
  console.log(`💵 USDC: ${usdcTokenAddress}`);
  console.log(`💎 WBTC: ${wbtcTokenAddress}`);
  console.log(`🎨 UNI: ${uniTokenAddress}`);
  console.log(`🔗 LINK: ${linkTokenAddress}`);

  // Step 1: Deploy SteleFundInfo
  console.log("📊 Step 2: Deploying SteleFundInfo on mainnet...");
  const SteleFundInfo = await ethers.getContractFactory("SteleFundInfo");
  const steleFundInfo = await SteleFundInfo.deploy();
  await steleFundInfo.deployed();
  const steleFundInfoAddress = await steleFundInfo.address;
  console.log(`✅ SteleFundInfo deployed at: ${steleFundInfoAddress}\n`);

  // Step 2: Deploy SteleFund
  console.log("💼 Step 3: Deploying SteleFund on mainnet...");
  const SteleFund = await ethers.getContractFactory("SteleFund");
  const steleFund = await SteleFund.deploy(
    steleFundInfoAddress,
    wethTokenAddress,
    usdcTokenAddress,
    wbtcTokenAddress,
    uniTokenAddress,
    linkTokenAddress
  );
  await steleFund.deployed();
  const steleFundAddress = await steleFund.address;
  console.log(`✅ SteleFund deployed at: ${steleFundAddress}\n`);

  // Step 3: Set SteleFundInfo owner to SteleFund
  console.log("🔗 Step 4: Setting SteleFundInfo owner to SteleFund...");
  const infoOwnershipTx = await steleFundInfo.setOwner(steleFundAddress);
  await infoOwnershipTx.wait();
  console.log(`✅ SteleFundInfo ownership transferred to: ${steleFundAddress}\n`);

  // Step 4: Verify setup
  console.log("🔍 Step 5: Verifying deployment...");
  const infoOwner = await steleFundInfo.owner();
  const weth9 = await steleFund.weth9();
  const usdc = await steleFund.usdToken();
  const wbtc = await steleFund.wbtc();
  const uni = await steleFund.uni();
  const link = await steleFund.link();

  console.log("🎯 Verification Results:");
  console.log(`   SteleFundInfo owner: ${infoOwner}`);
  console.log(`   WETH9: ${weth9}`);
  console.log(`   USDC: ${usdc}`);
  console.log(`   WBTC: ${wbtc}`);
  console.log(`   UNI: ${uni}`);
  console.log(`   LINK: ${link}`);
  console.log(`   Info ownership correct: ${infoOwner === steleFundAddress}\n`);

  // Final Summary
  console.log("🎉 DEPLOYMENT COMPLETE ON MAINNET! 🎉");
  console.log("=".repeat(60));
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log(`💼 SteleFund: ${steleFundAddress}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "mainnet",
    contracts: {
      SteleFund: steleFundAddress,
      SteleFundInfo: steleFundInfoAddress,
      WETH: wethTokenAddress,
      USDC: usdcTokenAddress,
      WBTC: wbtcTokenAddress,
      UNI: uniTokenAddress,
      LINK: linkTokenAddress
    },
    transactions: {
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