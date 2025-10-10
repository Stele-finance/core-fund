const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying governance contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Mainnet
  const tokenAddress = "0xc4f1E00cCfdF3a068e2e6853565107ef59D96089"; // Stele Token
  const timeLockAddress = "0x523AeaBc48aFc09c881e9Ff87f9A4FeB63817f69";
  // Governor values
  const QUORUM_PERCENTAGE = 4; // 4%
  const VOTING_PERIOD = 272; // 1 hour for initial testing period, default : 7 days (50400 blocks)
  const VOTING_DELAY = 1; // 1 block

  // Deploy Governor
  console.log("Deploying SteleFundGovernor...");
  const SteleFundGovernor = await ethers.getContractFactory("SteleFundGovernor");
  const governor = await SteleFundGovernor.deploy(
    tokenAddress,
    timeLockAddress,
    QUORUM_PERCENTAGE,
    VOTING_PERIOD,
    VOTING_DELAY
  );
  await governor.deployed();
  const governorAddress = await governor.address;
  console.log("SteleFundGovernor deployed to:", governorAddress);

  // Setup roles
  console.log("Setting up roles...");
  
  // TimeLock roles to be set up
  const timeLock = await ethers.getContractAt("TimeLock", timeLockAddress)
  const proposerRole = await timeLock.PROPOSER_ROLE();
  const executorRole = await timeLock.EXECUTOR_ROLE();
  const adminRole = await timeLock.TIMELOCK_ADMIN_ROLE();

  // Grant proposer role to governor
  const proposerTx = await timeLock.grantRole(proposerRole, governorAddress);
  await proposerTx.wait();
  console.log("Proposer role granted to governor");

  // Grant executor role to everyone (address zero)
  const executorTx = await timeLock.grantRole(executorRole, "0x0000000000000000000000000000000000000000");
  await executorTx.wait();
  console.log("Executor role granted to everyone");

  // Revoke admin role from deployer
  const revokeTx = await timeLock.revokeRole(adminRole, deployer.address);
  await revokeTx.wait();
  console.log("Admin role revoked from deployer");

  console.log("Governance setup completed!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 