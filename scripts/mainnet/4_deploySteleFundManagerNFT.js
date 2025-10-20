const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFundManagerNFT Deployment on mainnet...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // mainnet addresses - Update with actual deployed addresses from step 3
  const steleFundAddress = "0x7D38435F9D78DFc9FDe6E9547C7f96F57D6430d3";
  const steleFundInfoAddress = "0x331E2988f235471C7b8B4aa991962A72d8C02b5A";
  const timeLockAddress = "0x86e3Ee34d75D1B688D2a061B53B686299bcF3355"; // From step 1

  // Validate addresses
  if (!steleFundInfoAddress) {
    console.error("❌ Error: Please set the SteleFundInfo address from step 3 deployment");
    console.log("   Update the steleFundInfoAddress variable with the deployed address");
    process.exit(1);
  }

  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);

  // Step 1: Deploy SteleFundManagerNFT
  console.log("🎨 Step 1: Deploying SteleFundManagerNFT on mainnet...");
  const SteleFundManagerNFT = await ethers.getContractFactory("SteleFundManagerNFT");
  const steleFundManagerNFT = await SteleFundManagerNFT.deploy(steleFundAddress, steleFundInfoAddress);
  await steleFundManagerNFT.deployed();
  const steleFundManagerNFTAddress = steleFundManagerNFT.address;
  console.log(`✅ SteleFundManagerNFT deployed at: ${steleFundManagerNFTAddress}\n`);

  // Step 2: Set NFT contract address in SteleFund
  console.log("🔗 Step 2: Setting SteleFundManagerNFT address in SteleFund...");
  const steleFund = await ethers.getContractAt("SteleFund", steleFundAddress);
  const setNFTTx = await steleFund.setManagerNFTContract(steleFundManagerNFTAddress);
  await setNFTTx.wait();
  console.log(`✅ SteleFundManagerNFT address set in SteleFund\n`);

  // Step 3: Transfer SteleFund ownership to TimeLock
  console.log("🏛️ Step 3: Transferring SteleFund ownership to TimeLock...");
  try {
    const ownershipTx = await steleFund.transferOwnership(timeLockAddress);
    await ownershipTx.wait();
    console.log(`✅ SteleFund ownership transferred to: ${timeLockAddress}\n`);
  } catch (error) {
    console.log("⚠️  SteleFund ownership transfer failed:", error.message);
    console.log("   Please transfer ownership manually after deployment\n");
  }

  // Step 4: Verify setup
  console.log("🔍 Step 4: Verifying deployment...");
  const fundInfo = await steleFundManagerNFT.steleFundInfo();
  const fundContract = await steleFundManagerNFT.steleFundContract();
  const managerNFTAddress = await steleFund.managerNFTContract();
  const steleFundOwner = await steleFund.owner();
  const name = await steleFundManagerNFT.name();
  const symbol = await steleFundManagerNFT.symbol();

  console.log("🎯 Verification Results:");
  console.log(`   NFT Name: ${name}`);
  console.log(`   NFT Symbol: ${symbol}`);
  console.log(`   SteleFund Contract: ${fundContract}`);
  console.log(`   SteleFund Owner: ${steleFundOwner}`);
  console.log(`   FundInfo address: ${fundInfo}`);
  console.log(`   Manager NFT in SteleFund: ${managerNFTAddress}`);
  console.log(`   FundInfo correctly set: ${fundInfo === steleFundInfoAddress}`);
  console.log(`   SteleFund correctly set: ${fundContract === steleFundAddress}`);
  console.log(`   NFT address correctly set: ${managerNFTAddress === steleFundManagerNFTAddress}`);
  console.log(`   SteleFund governance enabled: ${steleFundOwner === timeLockAddress}\n`);

  // Final Summary
  console.log("🎉 DEPLOYMENT COMPLETE ON MAINNET! 🎉");
  console.log("=".repeat(60));
  console.log(`🎨 SteleFundManagerNFT: ${steleFundManagerNFTAddress}`);
  console.log(`📊 FundInfo: ${steleFundInfoAddress}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "mainnet",
    contracts: {
      SteleFundManagerNFT: steleFundManagerNFTAddress,
      SteleFund: steleFundAddress,
      SteleFundInfo: steleFundInfoAddress
    },
    transactions: {
      steleFundManagerNFT: steleFundManagerNFT.deploymentTransaction
    }
  };

  console.log("\n📋 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Instructions for next steps
  console.log("\n📝 Next Steps:");
  console.log("1. Update the steleFundInfoAddress variable with address from 3_deploySteleFund.js");
  console.log("2. Verify contracts on Arbiscan:");
  console.log(`   npx hardhat verify --network mainnet ${steleFundManagerNFTAddress} ${steleFundInfoAddress}`);
  console.log("3. Fund managers can mint NFTs by calling mintManagerNFT() with their fund parameters");
}

main()
  .then(() => console.log("✅ Deployment completed successfully"))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
  });