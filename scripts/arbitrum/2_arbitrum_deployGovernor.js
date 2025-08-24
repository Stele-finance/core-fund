const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying governance contracts on Arbitrum with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Arbitrum addresses
  const tokenAddress = "0x08C9c9EE6F161c6056060BF6AC7fE85e38638619"; // Existing STELE token on Arbitrum
  const timeLockAddress = "0x70Cc91A2B7F91efdb3B756512325AF978bda60F3"; // From step 1
  
  // Governor values
  const QUORUM_PERCENTAGE = 4; // 4%
  const VOTING_PERIOD = 272; // 1 hour for initial testing period, default : 7 days (2,400,000 blocks)
  const VOTING_DELAY = 1; // 1 block

  // Deploy Governor
  console.log("Deploying SteleFundGovernor on Arbitrum...");
  const SteleFundGovernor = await ethers.getContractFactory("SteleFundGovernor");
  const governor = await SteleFundGovernor.deploy(
    tokenAddress,
    timeLockAddress,
    QUORUM_PERCENTAGE,
    VOTING_PERIOD,
    VOTING_DELAY
  );
  await governor.deploymentTransaction().wait();
  const governorAddress = governor.target;
  console.log("SteleFundGovernor deployed to:", governorAddress);

  // Setup roles
  console.log("Setting up roles...");
  
  // TimeLock roles to be set up
  const timeLock = await ethers.getContractAt("TimeLock", timeLockAddress);
  const proposerRole = await timeLock.PROPOSER_ROLE();
  const executorRole = await timeLock.EXECUTOR_ROLE();
  const adminRole = await timeLock.DEFAULT_ADMIN_ROLE();

  // Grant proposer role to governor
  const proposerTx = await timeLock.grantRole(proposerRole, governorAddress);
  await proposerTx.wait();
  console.log("Proposer role granted to governor");

  // Grant executor role to everyone (address zero)
  const executorTx = await timeLock.grantRole(executorRole, ethers.ZeroAddress);
  await executorTx.wait();
  console.log("Executor role granted to everyone");

  // Revoke admin role from deployer
  const revokeTx = await timeLock.revokeRole(adminRole, deployer.address);
  await revokeTx.wait();
  console.log("Admin role revoked from deployer");

  console.log("Governance setup completed on Arbitrum!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});