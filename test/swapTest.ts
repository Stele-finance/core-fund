import { expect } from "chai";
import { ethers } from "hardhat";
import { SteleFund, SteleFundInfo, SteleFundSetting } from "../typechain-types";

describe("SteleFund Swap Test", function () {
  let steleFund: SteleFund;
  let steleFundInfo: SteleFundInfo;
  let steleFundSetting: SteleFundSetting;

  let manager: any;
  let investor: any;
  let fundId: bigint;

  // Mainnet addresses
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
  const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";

  before(async function () {
    [manager, investor] = await ethers.getSigners();

    console.log("Deploying contracts...");
    console.log("Manager:", manager.address);

    // 1. Deploy SteleFundSetting
    const SettingFactory = await ethers.getContractFactory("SteleFundSetting");
    steleFundSetting = await SettingFactory.deploy(WETH, USDC);
    await steleFundSetting.waitForDeployment();
    console.log("SteleFundSetting deployed to:", await steleFundSetting.getAddress());

    // 2. Deploy SteleFundInfo
    const InfoFactory = await ethers.getContractFactory("SteleFundInfo");
    steleFundInfo = await InfoFactory.deploy();
    await steleFundInfo.waitForDeployment();
    console.log("SteleFundInfo deployed to:", await steleFundInfo.getAddress());

    // 3. Deploy SteleFund
    const FundFactory = await ethers.getContractFactory("SteleFund");
    steleFund = await FundFactory.deploy(
      WETH,
      await steleFundSetting.getAddress(),
      await steleFundInfo.getAddress(),
      USDC
    );
    await steleFund.waitForDeployment();
    console.log("SteleFund deployed to:", await steleFund.getAddress());

    // 4. Set SteleFund as owner in Info
    await steleFundInfo.setOwner(await steleFund.getAddress());
    console.log("SteleFund set as owner in Info");

    // 5. Setup investable tokens
    await steleFundSetting.setToken(LINK); // LINK
    console.log("Investable tokens set (WETH and USDC already set in constructor)");

    // 6. Create fund (manager creates)
    const tx = await steleFundInfo.create();
    const receipt = await tx.wait();

    // Get fundId from event
    const event = receipt?.logs.find((log: any) => {
      try {
        const parsed = steleFundInfo.interface.parseLog(log);
        return parsed?.name === "Create";
      } catch {
        return false;
      }
    });

    if (event) {
      const parsed = steleFundInfo.interface.parseLog(event);
      fundId = parsed?.args[0];
      console.log("Fund created with ID:", fundId.toString());
    }

    // 7. Join fund as investor
    await steleFundInfo.connect(investor).join(fundId);
    console.log("Investor joined fund");
  });

  it("Should swap ETH to LINK (Single Hop)", async function () {
    const swapAmount = ethers.parseEther("1"); // 1 ETH

    console.log("\n=== ETH → LINK Swap Test ===");

    // 1. Deposit ETH
    console.log("1. Depositing 1 ETH...");
    const depositTx = await manager.sendTransaction({
      to: await steleFund.getAddress(),
      value: swapAmount,
      data: ethers.toBeHex(fundId, 32)
    });
    await depositTx.wait();

    const wethBalance = await steleFundInfo.getFundTokenAmount(fundId, WETH);
    console.log("   WETH balance:", ethers.formatEther(wethBalance), "WETH");
    expect(wethBalance).to.equal(swapAmount);

    // 2. Set slippage protection
    console.log("\n2. Setting slippage protection...");
    console.log("   Minimum LINK: 0 (testing mode)");

    // 3. Execute swap
    console.log("\n3. Executing swap...");
    const swapTx = await steleFund.swap(fundId, [
      {
        swapType: 0, // EXACT_INPUT_SINGLE_HOP
        tokenIn: WETH,
        tokenOut: LINK,
        path: "0x",
        fee: 3000,
        amountIn: swapAmount,
        amountOutMinimum: 0 // Accept any amount for testing
      }
    ]);
    const swapReceipt = await swapTx.wait();
    console.log("   Swap executed! Gas used:", swapReceipt?.gasUsed.toString());

    // 4. Check balances
    console.log("\n4. Checking balances...");
    const wethBalanceAfter = await steleFundInfo.getFundTokenAmount(fundId, WETH);
    const linkBalance = await steleFundInfo.getFundTokenAmount(fundId, LINK);

    console.log("   WETH balance:", ethers.formatEther(wethBalanceAfter), "WETH");
    console.log("   LINK balance:", ethers.formatEther(linkBalance), "LINK");

    // Assertions
    expect(wethBalanceAfter).to.equal(0);
    expect(linkBalance).to.be.gt(0);

    console.log("\n✅ Swap successful!");
    console.log("   Swapped:", ethers.formatEther(swapAmount), "ETH");
    console.log("   Received:", ethers.formatEther(linkBalance), "LINK");
  });

  it("Should swap LINK to WBTC (Multi Hop via ETH)", async function () {
    // First, we need to get LINK from the previous test
    // We'll swap all LINK balance to WBTC
    const linkBalance = await steleFundInfo.getFundTokenAmount(fundId, LINK);
    console.log("\n=== LINK → ETH → WBTC Swap Test (Multi Hop) ===");
    console.log("Starting LINK balance:", ethers.formatEther(linkBalance), "LINK");

    // 1. Add WBTC as investable token
    console.log("\n1. Adding WBTC as investable token...");
    await steleFundSetting.setToken(WBTC);
    console.log("   WBTC added");

    // 2. Encode multi-hop path: LINK → WETH (0.3%) → WBTC (0.3%)
    console.log("\n2. Encoding multi-hop path...");
    const path = ethers.solidityPacked(
      ["address", "uint24", "address", "uint24", "address"],
      [
        LINK,
        3000,  // LINK-WETH 0.3% fee
        WETH,
        3000,  // WETH-WBTC 0.3% fee
        WBTC
      ]
    );
    console.log("   Path:", path);

    // 3. Execute multi-hop swap
    console.log("\n3. Executing multi-hop swap...");
    const swapTx = await steleFund.swap(fundId, [
      {
        swapType: 1, // EXACT_INPUT_MULTI_HOP
        tokenIn: LINK,
        tokenOut: WBTC,
        path: path,
        fee: 0,
        amountIn: linkBalance,
        amountOutMinimum: 0 // Accept any amount for testing
      }
    ]);
    const swapReceipt = await swapTx.wait();
    console.log("   Swap executed! Gas used:", swapReceipt?.gasUsed.toString());

    // 4. Check balances
    console.log("\n4. Checking balances...");
    const linkBalanceAfter = await steleFundInfo.getFundTokenAmount(fundId, LINK);
    const wbtcBalance = await steleFundInfo.getFundTokenAmount(fundId, WBTC);

    console.log("   LINK balance:", ethers.formatEther(linkBalanceAfter), "LINK");
    console.log("   WBTC balance:", ethers.formatUnits(wbtcBalance, 8), "WBTC");

    // Assertions
    expect(linkBalanceAfter).to.equal(0);
    expect(wbtcBalance).to.be.gt(0);

    console.log("\n✅ Multi-hop swap successful!");
    console.log("   Route: LINK → ETH → WBTC");
    console.log("   Received:", ethers.formatUnits(wbtcBalance, 8), "WBTC");
  });
});
