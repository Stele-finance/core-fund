import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, formatEther, formatUnits } from "ethers";

describe("SteleFund Swap Function Test", function () {
  let steleFund: any;
  let steleFundInfo: any;
  let steleFundSetting: any;
  let owner: any;
  let manager: any;
  let investor: any;

  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

  before(async function () {
    this.timeout(300000);
    
    console.log("\n🚀 Testing SteleFund.swap() Function");
    
    [owner, manager, investor] = await ethers.getSigners();
    
    await ethers.provider.send("hardhat_setBalance", [
      investor.address,
      "0x56BC75E2D630E100000"
    ]);
    
    // Deploy contracts
    const SteleFundSetting = await ethers.getContractFactory("SteleFundSetting");
    steleFundSetting = await SteleFundSetting.deploy(WETH_ADDRESS, USDC_ADDRESS);
    await steleFundSetting.waitForDeployment();

    const SteleFundInfo = await ethers.getContractFactory("SteleFundInfo");
    steleFundInfo = await SteleFundInfo.deploy();
    await steleFundInfo.waitForDeployment();

    const SteleFund = await ethers.getContractFactory("SteleFund");
    steleFund = await SteleFund.deploy(
      WETH_ADDRESS,
      await steleFundSetting.getAddress(),
      await steleFundInfo.getAddress(),
      USDC_ADDRESS
    );
    await steleFund.waitForDeployment();

    await steleFundInfo.setOwner(await steleFund.getAddress());
    
    console.log("✅ Contracts deployed");
  });

  it("Should test 1 ETH → USDC swap via SteleFund.swap()", async function () {
    console.log("\n💱 Testing 1 ETH → USDC Swap");
    
    // 1. Create fund and join
    await steleFundInfo.connect(manager).create();
    const fundId = 1;
    await steleFundInfo.connect(investor).join(fundId);
    
    // 2. Deposit 5 ETH
    const depositAmount = parseEther("5.0");
    const fundIdBytes = ethers.zeroPadValue(ethers.toBeHex(fundId), 32);
    
    await investor.sendTransaction({
      to: await steleFund.getAddress(),
      value: depositAmount,
      data: fundIdBytes,
      gasLimit: 500000
    });
    
    console.log("  ✅ Deposited 5 ETH to fund");
    
    // 3. Check initial balances
    const wethBefore = await steleFundInfo.getFundTokenAmount(fundId, WETH_ADDRESS);
    const usdcBefore = await steleFundInfo.getFundTokenAmount(fundId, USDC_ADDRESS);
    
    console.log("\n📊 BEFORE SWAP:");
    console.log("  WETH Balance:", formatEther(wethBefore));
    console.log("  USDC Balance:", formatUnits(usdcBefore, 6));
    
    // 4. Execute 1 ETH swap
    const swapAmount = parseEther("1.0");
    const swapParams = [{
      swapType: 0,
      tokenIn: WETH_ADDRESS,
      tokenOut: USDC_ADDRESS,
      fee: 3000, // 0.3%
      amountIn: swapAmount,
      amountOut: 0,
      amountInMaximum: 0,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
      path: "0x"
    }];
    
    console.log("\n⚡ EXECUTING SWAP: 1 ETH → USDC");
    
    const swapTx = await steleFund.connect(manager).swap(fundId, swapParams, {
      gasLimit: 1000000
    });
    const receipt = await swapTx.wait();
    
    console.log("  ✅ Swap transaction completed");
    console.log("  Gas Used:", receipt.gasUsed.toString());
    
    // 5. Check final balances
    const wethAfter = await steleFundInfo.getFundTokenAmount(fundId, WETH_ADDRESS);
    const usdcAfter = await steleFundInfo.getFundTokenAmount(fundId, USDC_ADDRESS);
    
    console.log("\n📊 AFTER SWAP:");
    console.log("  WETH Balance:", formatEther(wethAfter));
    console.log("  USDC Balance:", formatUnits(usdcAfter, 6));
    
    // 6. Calculate swap results
    const wethUsed = wethBefore - wethAfter;
    const usdcReceived = usdcAfter - usdcBefore;
    
    console.log("\n🎯 SWAP RESULTS:");
    console.log("  WETH Used:", formatEther(wethUsed));
    console.log("  USDC Received:", formatUnits(usdcReceived, 6));
    
    if (usdcReceived > 0) {
      const ethPrice = Number(formatUnits(usdcReceived, 6)) / Number(formatEther(wethUsed));
      console.log("  Effective ETH Price: $" + ethPrice.toFixed(2));
    }
    
    // Verify swap worked
    expect(wethUsed).to.be.gt(0);
    expect(usdcReceived).to.be.gt(0);
    expect(wethUsed).to.be.closeTo(swapAmount, parseEther("0.01"));
    
    console.log("\n🎉 SUCCESS! SteleFund.swap() works correctly");
    console.log("📊 ANSWER: 1 ETH swapped to", formatUnits(usdcReceived, 6), "USDC");
  });
  
  it("Should test 0.003 ETH → USDC swap (original problem amount)", async function () {
    console.log("\n💱 Testing 0.003 ETH → USDC Swap (original overflow amount)");
    
    const fundId = 1;
    const swapAmount = parseEther("0.003");
    
    const wethBefore = await steleFundInfo.getFundTokenAmount(fundId, WETH_ADDRESS);
    const usdcBefore = await steleFundInfo.getFundTokenAmount(fundId, USDC_ADDRESS);
    
    const swapParams = [{
      swapType: 0,
      tokenIn: WETH_ADDRESS,
      tokenOut: USDC_ADDRESS,
      fee: 3000,
      amountIn: swapAmount,
      amountOut: 0,
      amountInMaximum: 0,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
      path: "0x"
    }];
    
    console.log("⚡ EXECUTING 0.003 ETH SWAP...");
    
    try {
      const swapTx = await steleFund.connect(manager).swap(fundId, swapParams, {
        gasLimit: 1000000
      });
      await swapTx.wait();
      
      const wethAfter = await steleFundInfo.getFundTokenAmount(fundId, WETH_ADDRESS);
      const usdcAfter = await steleFundInfo.getFundTokenAmount(fundId, USDC_ADDRESS);
      
      const wethUsed = wethBefore - wethAfter;
      const usdcReceived = usdcAfter - usdcBefore;
      
      console.log("\n🎯 0.003 ETH SWAP RESULTS:");
      console.log("  WETH Used:", formatEther(wethUsed));
      console.log("  USDC Received:", formatUnits(usdcReceived, 6));
      
      console.log("\n📊 FINAL ANSWER: 0.003 ETH swapped to", formatUnits(usdcReceived, 6), "USDC");
      console.log("✅ NO OVERFLOW ERROR - V3 implementation works!");
      
      expect(usdcReceived).to.be.gt(0);
      
    } catch (error: any) {
      if (error.message.includes("OVERFLOW")) {
        console.error("❌ OVERFLOW ERROR STILL EXISTS!");
        throw error;
      } else {
        console.log("Different error:", error.message);
        throw error;
      }
    }
  });
});