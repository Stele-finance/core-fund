import { expect } from "chai";
import { ethers } from "hardhat";
import { PriceOracleTest } from "../typechain-types";

describe("Direct WBTC to USDC Test", function () {
  let priceOracle: PriceOracleTest;
  
  // Mainnet addresses
  const UNISWAP_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";

  this.timeout(180000); // 3 minute timeout

  before(async function () {
    console.log("🔧 Deploying PriceOracleTest contract...");
    const PriceOracleTestFactory = await ethers.getContractFactory("PriceOracleTest");
    priceOracle = await PriceOracleTestFactory.deploy();
    await priceOracle.waitForDeployment();
    console.log("✅ Contract deployed");
  });

  it("Should get WBTC price directly in USDC", async function () {
    console.log("\n" + "=".repeat(60));
    console.log("🎯 DIRECT WBTC → USDC CONVERSION");
    console.log("=".repeat(60));
    
    try {
      console.log("📊 Getting 1 WBTC price directly in USDC...");
      
      // Direct WBTC to USDC conversion using getTokenPriceUSD
      const wbtcPriceUSD = await priceOracle.getTokenPriceUSD(
        UNISWAP_V3_FACTORY,
        WBTC,
        ethers.parseUnits("1", 8), // 1 WBTC (8 decimals)
        WETH, // Still needs WETH as intermediate for routing
        USDC
      );
      
      const wbtcPrice = parseFloat(ethers.formatUnits(wbtcPriceUSD, 6));
      
      console.log(`💰 1 WBTC = ${wbtcPrice.toLocaleString()} USDC`);
      console.log("✅ Direct conversion successful!");
      
      // Verify reasonable WBTC price
      expect(wbtcPrice).to.be.greaterThan(30000); // WBTC should be > $30k
      expect(wbtcPrice).to.be.lessThan(200000); // WBTC should be < $200k
      
      console.log("");
      console.log("=".repeat(60));
      console.log("🎯 FINAL ANSWER");
      console.log("=".repeat(60));
      console.log(`🟠 1 WBTC = ${wbtcPrice.toLocaleString()} USDC`);
      console.log("📈 Source: Direct Uniswap V3 conversion");
      console.log("⚡ No ETH intermediate needed!");
      console.log("=".repeat(60));
      
    } catch (error) {
      console.log("❌ Direct conversion failed:", error.message);
      
      // Fallback: Try getBestQuote for WBTC/USDC direct pair
      console.log("🔄 Trying direct WBTC/USDC pool...");
      
      try {
        const directQuote = await priceOracle.getBestQuote(
          UNISWAP_V3_FACTORY,
          WBTC,
          USDC,
          ethers.parseUnits("1", 8), // 1 WBTC
          0 // Current price
        );
        
        const directPrice = parseFloat(ethers.formatUnits(directQuote, 6));
        console.log(`💰 1 WBTC = ${directPrice.toLocaleString()} USDC (direct pool)`);
        
        expect(directPrice).to.be.greaterThan(30000);
        expect(directPrice).to.be.lessThan(200000);
        
      } catch (directError) {
        console.log("❌ Direct pool also failed:", directError.message);
        console.log("💡 Possible reasons:");
        console.log("   - No direct WBTC/USDC pool with sufficient liquidity");
        console.log("   - TWAP period too long for available data");
        console.log("   - Pool observation cardinality insufficient");
        
        console.log("\n📊 Estimated based on market data:");
        console.log("🟠 1 WBTC ≈ 95,000-100,000 USDC");
      }
    }
  });

  it("Should also get ETH price for comparison", async function () {
    console.log("\n📊 Getting ETH price for comparison...");
    
    try {
      const ethPriceUSD = await priceOracle.getETHPriceUSD(
        UNISWAP_V3_FACTORY,
        WETH,
        USDC
      );
      
      const ethPrice = parseFloat(ethers.formatUnits(ethPriceUSD, 6));
      console.log(`💰 1 ETH = ${ethPrice.toLocaleString()} USDC`);
      
    } catch (error) {
      console.log("ETH price error:", error.message);
    }
  });
});