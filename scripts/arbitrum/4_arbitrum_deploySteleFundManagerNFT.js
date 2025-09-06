const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFundManagerNFT Deployment on Arbitrum...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses - Update with actual deployed addresses from step 3
  const steleFundInfoAddress = "0x2B2Dc05E42CAfCa1b1d6839F41d2F27069d602Aa";
  const timeLockAddress = "0xa6e62AaaD807E9ffc276c7045bd06F2b064Ca9d7";

  // Validate addresses
  if (!steleFundInfoAddress) {
    console.error("❌ Error: Please set the SteleFundInfo address from step 3 deployment");
    console.log("   Update the steleFundInfoAddress variable with the deployed address");
    process.exit(1);
  }

  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log(`🏛️ TimeLock: ${timeLockAddress}\n`);

  // Step 1: Deploy NFTSVG library
  console.log("📚 Step 1: Deploying NFTSVG library on Arbitrum...");
  const NFTSVG = await ethers.getContractFactory("NFTSVG");
  const nftSVG = await NFTSVG.deploy();
  await nftSVG.deployed();
  const nftSVGAddress = nftSVG.address;
  console.log(`✅ NFTSVG library deployed at: ${nftSVGAddress}\n`);

  // Step 2: Deploy SteleFundManagerNFT with library linking
  console.log("🎨 Step 2: Deploying SteleFundManagerNFT on Arbitrum...");
  const SteleFundManagerNFT = await ethers.getContractFactory("SteleFundManagerNFT", {
    libraries: {
      NFTSVG: nftSVGAddress
    }
  });
  
  const steleFundManagerNFT = await SteleFundManagerNFT.deploy(steleFundInfoAddress);
  await steleFundManagerNFT.deployed();
  const steleFundManagerNFTAddress = steleFundManagerNFT.address;
  console.log(`✅ SteleFundManagerNFT deployed at: ${steleFundManagerNFTAddress}\n`);

  // Step 3: Transfer ownership to TimeLock (optional - for governance control)
  console.log("🏛️ Step 3: Transferring SteleFundManagerNFT ownership to TimeLock...");
  try {
    const ownershipTx = await steleFundManagerNFT.transferOwnership(timeLockAddress);
    await ownershipTx.wait();
    console.log(`✅ SteleFundManagerNFT ownership transferred to: ${timeLockAddress}\n`);
  } catch (error) {
    console.log("⚠️  Ownership transfer skipped (you may want to keep owner control)\n");
  }

  // Step 4: Verify setup
  console.log("🔍 Step 4: Verifying deployment...");
  const currentOwner = await steleFundManagerNFT.owner();
  const fundInfo = await steleFundManagerNFT.fundInfo();
  const name = await steleFundManagerNFT.name();
  const symbol = await steleFundManagerNFT.symbol();

  console.log("🎯 Verification Results:");
  console.log(`   NFT Name: ${name}`);
  console.log(`   NFT Symbol: ${symbol}`);
  console.log(`   SteleFundManagerNFT owner: ${currentOwner}`);
  console.log(`   FundInfo address: ${fundInfo}`);
  console.log(`   Governance enabled: ${currentOwner === timeLockAddress}`);
  console.log(`   FundInfo correctly set: ${fundInfo === steleFundInfoAddress}\n`);

  // Final Summary
  console.log("🎉 DEPLOYMENT COMPLETE ON ARBITRUM! 🎉");
  console.log("=".repeat(60));
  console.log(`🎨 SteleFundManagerNFT: ${steleFundManagerNFTAddress}`);
  console.log(`📚 NFTSVG Library: ${nftSVGAddress}`);
  console.log(`📊 FundInfo: ${steleFundInfoAddress}`);
  console.log(`🏛️ Owner: ${currentOwner}`);
  console.log(`🏛️ Governance: ${currentOwner === timeLockAddress ? '✅ Enabled' : '❌ Disabled'}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "arbitrum",
    contracts: {
      SteleFundManagerNFT: steleFundManagerNFTAddress,
      NFTSVG: nftSVGAddress,
      SteleFundInfo: steleFundInfoAddress,
      TimeLock: timeLockAddress
    },
    governance: {
      enabled: currentOwner === timeLockAddress,
      owner: currentOwner
    },
    transactions: {
      nftSVG: nftSVG.deploymentTransaction,
      steleFundManagerNFT: steleFundManagerNFT.deploymentTransaction
    }
  };

  console.log("\n📋 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Instructions for next steps
  console.log("\n📝 Next Steps:");
  console.log("1. Update the steleFundInfoAddress variable with address from 3_arbitrum_deploySteleFund.js");
  console.log("2. Verify contracts on Arbiscan:");
  console.log(`   npx hardhat verify --network arbitrum ${steleFundManagerNFTAddress} ${steleFundInfoAddress}`);
  console.log(`   npx hardhat verify --network arbitrum ${nftSVGAddress}`);
  console.log("3. Fund managers can mint NFTs by calling mintManagerNFT() with their fund parameters");
}

main()
  .then(() => console.log("✅ Deployment completed successfully"))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
  });