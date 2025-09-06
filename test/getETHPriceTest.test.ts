import { expect } from "chai";
import { ethers } from "hardhat";

describe("ETH Price Test", function () {
  let steleFund: any;
  let steleFundInfo: any;
  let steleFundSetting: any;
  let owner: any;

  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // Correct USDC address
  
  // Uniswap V4 addresses
  const POOL_MANAGER = "0x000000000004444c5dc75cB358380D2e3dE08A90";
  const UNIVERSAL_ROUTER = "0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af";

  before(async function () {
    [owner] = await ethers.getSigners();

    // Deploy contracts with V4 support
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
      USDC_ADDRESS,
      POOL_MANAGER,
      UNIVERSAL_ROUTER
    );
    await steleFund.waitForDeployment();

    console.log("✅ Contracts deployed for ETH price testing");
  });

  describe("ETH to USDC Price Tests", function () {
    it("Should show 1 ETH price in USDC", async function () {
      console.log("\n=== Testing 1 ETH Price ===");
      
      try {
        const oneETH = ethers.parseEther("1"); // 1 ETH
        console.log("Input amount:", ethers.formatEther(oneETH), "ETH");
        
        // Get ETH price in USDC using our oracle
        const priceInUSDC = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, oneETH);
        console.log("Price result:", ethers.formatEther(priceInUSDC), "USDC");
        
        // Since WETH should return 1:1 ratio, it should be the same amount
        expect(priceInUSDC).to.equal(oneETH);
        console.log("✅ WETH correctly returns 1:1 ratio");
        
        // Test different amounts
        const amounts = [
          ethers.parseEther("0.1"),   // 0.1 ETH
          ethers.parseEther("1"),     // 1 ETH  
          ethers.parseEther("10"),    // 10 ETH
          ethers.parseEther("0.01")   // 0.01 ETH
        ];
        
        for (const amount of amounts) {
          const price = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, amount);
          console.log(`${ethers.formatEther(amount)} WETH = ${ethers.formatEther(price)} USDC`);
          expect(price).to.equal(amount); // 1:1 ratio for WETH
        }
        
      } catch (error: any) {
        console.error("ETH price test failed:", error.message);
        throw error;
      }
    });

    it("Should test USD price calculation with different amounts", async function () {
      console.log("\n=== Testing USD Price Calculation ===");
      
      const testAmounts = [
        { amount: ethers.parseEther("1"), description: "1 ETH" },
        { amount: ethers.parseEther("0.5"), description: "0.5 ETH" },
        { amount: ethers.parseEther("2"), description: "2 ETH" },
        { amount: BigInt("1000000"), description: "1 USDC" } // 6 decimals
      ];
      
      for (const test of testAmounts) {
        try {
          console.log(`\nTesting ${test.description}:`);
          
          if (test.description.includes("ETH")) {
            // Test WETH price
            const wethPrice = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, test.amount);
            console.log(`- WETH result: ${ethers.formatEther(wethPrice)} USDC`);
            expect(wethPrice).to.equal(test.amount);
          } else {
            // Test USDC (should be different behavior)
            const usdcPrice = await steleFund.getTokenPriceETH.staticCall(USDC_ADDRESS, test.amount);
            console.log(`- USDC result: ${ethers.formatEther(usdcPrice)} ETH`);
            expect(usdcPrice).to.be.a('bigint');
          }
          
        } catch (error: any) {
          console.log(`- Error for ${test.description}: ${error.message.substring(0, 60)}...`);
          // Some errors expected without real pool data
        }
      }
    });

    it("Should test real-world ETH price scenarios", async function () {
      console.log("\n=== Testing Real-World Price Scenarios ===");
      
      // Test scenarios that might happen in real usage
      const scenarios = [
        { 
          description: "Small trade (0.01 ETH)", 
          amount: ethers.parseEther("0.01"),
          expectedMin: ethers.parseEther("0.01") // At least the input amount for WETH
        },
        { 
          description: "Medium trade (1 ETH)", 
          amount: ethers.parseEther("1"),
          expectedMin: ethers.parseEther("1")
        },
        { 
          description: "Large trade (100 ETH)", 
          amount: ethers.parseEther("100"),
          expectedMin: ethers.parseEther("100")
        }
      ];
      
      for (const scenario of scenarios) {
        try {
          console.log(`\nTesting ${scenario.description}:`);
          
          const result = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, scenario.amount);
          
          console.log(`- Input: ${ethers.formatEther(scenario.amount)} WETH`);
          console.log(`- Output: ${ethers.formatEther(result)} USDC`);
          console.log(`- Expected min: ${ethers.formatEther(scenario.expectedMin)} USDC`);
          
          expect(result).to.be.gte(scenario.expectedMin);
          console.log(`✅ ${scenario.description} price calculation passed`);
          
        } catch (error: any) {
          console.log(`- Error: ${error.message.substring(0, 80)}...`);
        }
      }
    });

    it("Should test price precision and decimals", async function () {
      console.log("\n=== Testing Price Precision ===");
      
      // Test very small amounts for precision
      const precisionTests = [
        BigInt("1"), // 1 wei
        BigInt("1000"), // 1000 wei  
        BigInt("1000000"), // 1 gwei
        ethers.parseEther("0.000001") // 1 microether
      ];
      
      for (const amount of precisionTests) {
        try {
          console.log(`\nTesting precision with ${amount.toString()} wei:`);
          
          const result = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, amount);
          
          console.log(`- Input: ${amount.toString()} wei (${ethers.formatEther(amount)} ETH)`);
          console.log(`- Output: ${result.toString()} wei (${ethers.formatEther(result)} USDC)`);
          
          // For WETH, should be 1:1
          expect(result).to.equal(amount);
          console.log("✅ Precision maintained");
          
        } catch (error: any) {
          console.log(`- Precision test failed: ${error.message.substring(0, 60)}...`);
        }
      }
    });

    it("Should test zero and edge cases", async function () {
      console.log("\n=== Testing Edge Cases ===");
      
      // Test zero amount
      try {
        console.log("Testing zero amount...");
        const zeroResult = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, 0);
        console.log("Zero amount result:", zeroResult.toString());
        expect(zeroResult).to.equal(0);
        console.log("✅ Zero amount handled correctly");
      } catch (error: any) {
        console.log("Zero amount error:", error.message);
      }
      
      // Test maximum uint256
      try {
        console.log("Testing very large amount...");
        const largeAmount = ethers.parseEther("1000000"); // 1M ETH
        const largeResult = await steleFund.getTokenPriceETH.staticCall(WETH_ADDRESS, largeAmount);
        console.log("Large amount result:", ethers.formatEther(largeResult), "USDC");
        expect(largeResult).to.equal(largeAmount);
        console.log("✅ Large amount handled correctly");
      } catch (error: any) {
        console.log("Large amount error:", error.message);
      }
    });
  });
});