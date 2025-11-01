const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SteleFundManagerNFT-only Deployment on Arbitrum...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses - Update with actual deployed addresses
  const steleFundAddress = "0x24Ab64Da6a6A985921aDBe494e55c10571121F52";
  const steleFundInfoAddress = "0xb0D008124C85180e5E9F242FA69d32686b59674A";

  // Validate addresses
  if (!steleFundAddress || !steleFundInfoAddress) {
    console.error("❌ Error: Please set the SteleFund and SteleFundInfo addresses");
    console.log("   Update the addresses variables with the deployed addresses");
    process.exit(1);
  }

  console.log(`📊 SteleFund: ${steleFundAddress}`);
  console.log(`📊 SteleFundInfo: ${steleFundInfoAddress}`);

  // Deploy SteleFundManagerNFT
  console.log("\n🎨 Deploying SteleFundManagerNFT on Arbitrum...");
  const SteleFundManagerNFT = await ethers.getContractFactory("SteleFundManagerNFT");
  const steleFundManagerNFT = await SteleFundManagerNFT.deploy(steleFundAddress, steleFundInfoAddress);
  await steleFundManagerNFT.deployed();
  const steleFundManagerNFTAddress = steleFundManagerNFT.address;
  console.log(`✅ SteleFundManagerNFT deployed at: ${steleFundManagerNFTAddress}\n`);

  // Verify deployment
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
  console.log("🎉 DEPLOYMENT COMPLETE ON ARBITRUM! 🎉");
  console.log("=".repeat(60));
  console.log(`🎨 SteleFundManagerNFT: ${steleFundManagerNFTAddress}`);
  console.log("=".repeat(60));

  // Save deployment info
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    network: "arbitrum",
    contracts: {
      SteleFundManagerNFT: steleFundManagerNFTAddress,
      SteleFund: steleFundAddress,
      SteleFundInfo: steleFundInfoAddress
    }
  };

  console.log("\n📋 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Next steps
  console.log("\n📝 Next Steps:");
  console.log("1. Set NFT contract address in SteleFund by calling:");
  console.log(`   steleFund.setManagerNFTContract("${steleFundManagerNFTAddress}")`);
  console.log("2. Verify contract on Arbiscan:");
  console.log(`   npx hardhat verify --network arbitrum ${steleFundManagerNFTAddress} ${steleFundAddress} ${steleFundInfoAddress}`);
}

main()
  .then(() => console.log("✅ Deployment completed successfully"))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
  });
