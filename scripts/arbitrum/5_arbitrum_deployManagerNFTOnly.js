const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFundManagerNFT Only Deployment on Arbitrum...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses - Update with actual deployed addresses
  const steleFundAddress = "0xc29D843526B857986B1Dd3b51E226307e7c1868b";
  const steleFundInfoAddress = "0xA6585D4aDb191852bf95c260a2e2bEcdC9d44209";

  // Validate addresses
  if (!steleFundAddress || !steleFundInfoAddress) {
    console.error("❌ Error: Please set the SteleFund and SteleFundInfo addresses");
    console.log("   Update the steleFundAddress and steleFundInfoAddress variables with the deployed addresses");
    process.exit(1);
  }

  console.log(`📊 Using existing contracts:`);
  console.log(`   SteleFund: ${steleFundAddress}`);
  console.log(`   SteleFundInfo: ${steleFundInfoAddress}\n`);

  // Deploy SteleFundManagerNFT
  console.log("🎨 Deploying SteleFundManagerNFT on Arbitrum...");
  const SteleFundManagerNFT = await ethers.getContractFactory("SteleFundManagerNFT");
  const steleFundManagerNFT = await SteleFundManagerNFT.deploy(steleFundAddress, steleFundInfoAddress);
  await steleFundManagerNFT.deployed();
  const steleFundManagerNFTAddress = steleFundManagerNFT.address;
  console.log(`✅ SteleFundManagerNFT deployed at: ${steleFundManagerNFTAddress}\n`);

  // Verify setup
  console.log("🔍 Verifying deployment...");
  const fundInfo = await steleFundManagerNFT.steleFundInfo();
  const fundContract = await steleFundManagerNFT.steleFundContract();
  const name = await steleFundManagerNFT.name();
  const symbol = await steleFundManagerNFT.symbol();

  console.log("🎯 Verification Results:");
  console.log(`   NFT Name: ${name}`);
  console.log(`   NFT Symbol: ${symbol}`);
  console.log(`   SteleFund Contract: ${fundContract}`);
  console.log(`   FundInfo address: ${fundInfo}`);
  console.log(`   FundInfo correctly set: ${fundInfo === steleFundInfoAddress}`);
  console.log(`   SteleFund correctly set: ${fundContract === steleFundAddress}\n`);

  // Final Summary
  console.log("🎉 MANAGER NFT DEPLOYMENT COMPLETE ON ARBITRUM! 🎉");
  console.log("=".repeat(60));
  console.log(`🎨 SteleFundManagerNFT: ${steleFundManagerNFTAddress}`);
  console.log(`📊 SteleFund: ${steleFundAddress}`);
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);
  console.log("=".repeat(60));

  // Save deployment addresses for verification
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "arbitrum",
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
  console.log("1. Verify the SteleFundManagerNFT contract on Arbiscan:");
  console.log(`   npx hardhat verify --network arbitrum ${steleFundManagerNFTAddress} ${steleFundAddress} ${steleFundInfoAddress}`);
  console.log("2. Set the NFT address in SteleFund through governance proposal:");
  console.log(`   Call setManagerNFTContract(${steleFundManagerNFTAddress})`);
  console.log("3. After governance approval, fund managers can mint NFTs");
}

main()
  .then(() => console.log("\n✅ Manager NFT deployment completed successfully"))
  .catch((error) => {
    console.error("\n❌ Manager NFT deployment failed:", error);
  });