// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundSetting.sol";
import "./interfaces/ISteleFundManagerNFT.sol";
import "./libraries/PriceOracle.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IWETH9 {
  function deposit() external payable;
  function withdraw(uint256 wad) external;
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

interface IERC20Minimal {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function decimals() external view returns (uint8);
}


contract SteleFund is ISteleFund, ReentrancyGuard {
  using PriceOracle for address;

  address public override owner;

  // Uniswap V3 Contract
  address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // For price oracle

  // Precision scaling for more accurate calculations
  uint256 private constant BASIS_POINTS = 10000; // 100% = 10000 basis points
  
  // Minimum thresholds to prevent dust issues
  uint256 private constant MIN_DEPOSIT_USD = 10; // Minimum $10 deposit
  
  // Maximum fund ID to prevent abuse
  uint256 private constant MAX_FUND_ID = 1000000000; // Maximum 1 billion funds
  
  // Maximum swaps per transaction to prevent DoS
  uint256 private constant MAX_SWAPS_PER_TX = 10;

  address public weth9;
  address public setting;
  address public info;
  address public usdToken; // USDC address for price calculation
  address public managerNFTContract; // SteleFundManagerNFT contract address

  modifier onlyOwner() {
      require(msg.sender == owner, 'NO');
      _;
  }

  modifier onlyManager(address sender, uint256 fundId) {
    require(fundId == ISteleFundInfo(info).managingFund(sender), "NM");
    _;
  }

  constructor(
    address _weth9, 
    address _setting, 
    address _info, 
    address _usdToken
  ) {
    weth9 = _weth9;
    setting = _setting;
    info = _info;
    usdToken = _usdToken;
    owner = msg.sender;
  }

  // Safe fund ID parsing from calldata
  function parseFundId(bytes memory data) private pure returns (uint256 fundId) {
    require(data.length == 32, "IDL"); // Must be exactly 32 bytes for uint256
    
    // Use standard ABI decoding for safety
    fundId = abi.decode(data, (uint256));
    
    // Prevent unreasonably large fund IDs
    require(fundId > 0 && fundId <= MAX_FUND_ID, "FID");
  }
  
  // Calculate portfolio total value in USD
  function getPortfolioValueUSD(uint256 fundId) internal view returns (uint256) {
    IToken.Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 totalValueUSD = 0;

    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        uint256 tokenValueUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, fundTokens[i].token, fundTokens[i].amount, weth9, usdToken);
        totalValueUSD += tokenValueUSD;
      }
    }

    return totalValueUSD;
  }

  // Calculate shares to mint based on USD value with improved precision
  function _calculateSharesToMint(uint256 fundId, address token, uint256 amount) private view returns (uint256) {
    uint256 fundShare = ISteleFundInfo(info).getFundShare(fundId);

    // First deposit: shares = USD value of deposit
    if (fundShare == 0) {
      uint256 usdValue = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
      return usdValue;
    }
    
    // Get deposit value in USD
    uint256 depositValueUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
    if (depositValueUSD == 0) return 0;
    
    // Get current portfolio value in USD
    uint256 portfolioValueUSD = getPortfolioValueUSD(fundId);
    if (portfolioValueUSD == 0) {
      return depositValueUSD;
    }
    
    // Use mulDiv for maximum precision: (depositValue * existingShares) / portfolioValue
    // This avoids intermediate overflow and maintains precision
    uint256 shares = PriceOracle.mulDiv(depositValueUSD, fundShare, portfolioValueUSD);

    // Round up to favor the protocol (prevent rounding attacks)
    if ((depositValueUSD * fundShare) % portfolioValueUSD > 0) {
      shares += 1;
    }
    
    return shares;
  }

  fallback() external payable nonReentrant { 
    // Safe fund ID parsing with validation
    uint256 fundId = parseFundId(msg.data);
    
    // Verify fund exists (fundId > 0 already checked in parseFundId)
    require(fundId <= ISteleFundInfo(info).fundIdCount(), "FNE");
    require(ISteleFundInfo(info).isJoined(msg.sender, fundId), "US");
    
    // Check minimum USD deposit amount
    {
      uint256 depositUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, weth9, msg.value, weth9, usdToken);
      uint8 decimals = IERC20Minimal(usdToken).decimals();
      require(decimals <= 18, "ID"); // Prevent overflow
      require(depositUSD >= MIN_DEPOSIT_USD * (10 ** uint256(decimals)), "MDA"); // Minimum $10 deposit
    }
    
    // Calculate manager fee (only for investors, not manager)
    uint256 feeAmount = 0;
    uint256 fundAmount = msg.value;
    if (msg.sender != ISteleFundInfo(info).manager(fundId)) {
      uint256 feeRate = ISteleFundSetting(setting).managerFee();
      feeAmount = PriceOracle.mulDiv(msg.value, feeRate, BASIS_POINTS);
      fundAmount = msg.value - feeAmount;
    }
    
    // Calculate shares based on net deposit amount (after fee deduction)
    uint256 sharesToMint = _calculateSharesToMint(fundId, weth9, fundAmount);
    require(sharesToMint > 0, "ZS"); // Zero shares
    
    // Update state FIRST (before external calls)
    ISteleFundInfo(info).increaseFundToken(fundId, weth9, fundAmount); // Net amount to fund pool
    if (feeAmount > 0) {
      ISteleFundInfo(info).increaseFeeToken(fundId, weth9, feeAmount); // Fee amount to fee pool
    }
    (uint256 investorShare, uint256 fundShare) = ISteleFundInfo(info).increaseShare(fundId, msg.sender, sharesToMint);
    
    emit Deposit(fundId, msg.sender, weth9, msg.value, investorShare, fundShare, fundAmount, feeAmount);

    // External call LAST
    IWETH9(weth9).deposit{value: msg.value}();
  }

  receive() external payable {
    if (msg.sender == weth9) {
      // when call IWETH9(weth9).withdraw(amount) in this contract
    } else {
      // when deposit ETH with no data
    }
  }

  function withdraw(uint256 fundId, uint256 percentage) external payable override nonReentrant {
    bool isJoined = ISteleFundInfo(info).isJoined(msg.sender, fundId);
    require(isJoined, "US");
    require(percentage > 0 && percentage <= 10000, "IP"); // 0.01% to 100%
    
    uint256 investorShare = ISteleFundInfo(info).getInvestorShare(fundId, msg.sender);
    require(investorShare > 0, "NS");
    
    _withdraw(fundId, investorShare, percentage);
  }
  
  function _withdraw(uint256 fundId, uint256 investorShareBefore, uint256 percentage) private {
    IToken.Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 fundShare = ISteleFundInfo(info).getFundShare(fundId);
    require(fundShare > 0, "ZFS"); // Zero fund shares

    uint256 shareToWithdraw = PriceOracle.mulDiv(investorShareBefore, percentage, 10000);
    
    // If shareToWithdraw is 0 due to rounding, just return - no need to complicate
    if (shareToWithdraw == 0) {
      return; // No withdrawal, save gas
    }

    // Update state FIRST (before external calls)
    (uint256 investorShareAfter, uint256 fundShareAfter) = ISteleFundInfo(info).decreaseShare(fundId, msg.sender, shareToWithdraw);
    emit Withdraw(fundId, msg.sender, percentage, investorShareAfter, fundShareAfter);

    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        // Calculate token amount with overflow protection using mulDiv
        // Calculate token share directly: (amount * investorShareBefore * percentage) / (fundShare * 10000)
        uint256 tokenShare = PriceOracle.mulDiv(
          PriceOracle.mulDiv(fundTokens[i].amount, investorShareBefore, fundShare),
          percentage,
          10000
        );
        
        // Ensure we don't withdraw more than available
        if (tokenShare > fundTokens[i].amount) {
          tokenShare = fundTokens[i].amount;
        }
        
        if (tokenShare > 0) {
          address token = fundTokens[i].token;
          
          // Update state FIRST (before external calls)
          ISteleFundInfo(info).decreaseFundToken(fundId, token, tokenShare);
          
          // External calls LAST
          if (token == weth9) {
            IWETH9(weth9).withdraw(tokenShare);
            (bool success, ) = payable(msg.sender).call{value: tokenShare}("");
            require(success, "FW");
          } else {
            IERC20Minimal(token).transfer(msg.sender, tokenShare);
          }
        }
      }
    }
  }

  // Uniswap V3 Swap Implementation with slippage protection
  function executeV3Swap(uint256 fundId, SwapParams calldata trade) private {
    require(ISteleFundSetting(setting).isInvestable(trade.tokenOut), "NWT");
    require(trade.amountIn <= ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenIn), "NET");
    
    // Validate slippage and check token limits
    _validateSwapParameters(fundId, trade);
    
    // Calculate effective minimum output
    uint256 effectiveMinOutput = _calculateEffectiveMinOutput(trade);
    
    // Update state FIRST - decrease the token we're swapping from
    ISteleFundInfo(info).decreaseFundToken(fundId, trade.tokenIn, trade.amountIn);

    // Execute the swap
    uint256 amountOut = _executeSwapCall(trade, effectiveMinOutput);
    
    // Validate output and update state
    require(amountOut >= effectiveMinOutput, "SLP");
    ISteleFundInfo(info).increaseFundToken(fundId, trade.tokenOut, amountOut);
    emit Swap(fundId, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
  }
  
  // Helper function to validate swap parameters
  function _validateSwapParameters(uint256 fundId, SwapParams calldata trade) private view {
    // Check maxTokens limit for new tokens
    if (ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenOut) == 0) {
      IToken.Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
      uint256 currentTokenTypes = 0;
      for (uint256 i = 0; i < fundTokens.length; i++) {
        if (fundTokens[i].amount > 0) {
          currentTokenTypes++;
        }
      }
      require(currentTokenTypes < ISteleFundSetting(setting).maxTokens(), "MAX");
    }
  }
  
  // Helper function to calculate effective minimum output
  function _calculateEffectiveMinOutput(SwapParams calldata trade) private view returns (uint256) {
    uint256 expectedOutput = PriceOracle.getBestQuote(
      uniswapV3Factory,
      trade.tokenIn,
      trade.tokenOut,
      uint128(trade.amountIn),
      300
    );

    uint256 slippage = ISteleFundSetting(setting).maxSlippage();
    uint256 minOutputWithSlippage = PriceOracle.mulDiv(expectedOutput, BASIS_POINTS - slippage, BASIS_POINTS);

    return minOutputWithSlippage;
  }
  
  // Helper function to execute swap call
  function _executeSwapCall(SwapParams calldata trade, uint256 effectiveMinOutput) private returns (uint256) {
    // Safe approve pattern: reset to 0 first, then set new amount
    // This prevents issues with tokens like USDT that don't allow changing non-zero allowances
    IERC20Minimal(trade.tokenIn).approve(swapRouter, 0);
    IERC20Minimal(trade.tokenIn).approve(swapRouter, trade.amountIn);
    
    bytes memory swapCall = abi.encodeWithSignature(
      "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
      trade.tokenIn,
      trade.tokenOut,
      trade.fee,
      address(this),
      block.timestamp + 300,
      trade.amountIn,
      effectiveMinOutput,
      0
    );
    
    uint256 balanceBefore = IERC20Minimal(trade.tokenOut).balanceOf(address(this));
    (bool success, ) = swapRouter.call(swapCall);
    require(success, "SWF");
    
    return IERC20Minimal(trade.tokenOut).balanceOf(address(this)) - balanceBefore;
  }

  function swap(uint256 fundId, SwapParams[] calldata trades) 
    external override onlyManager(msg.sender, fundId) nonReentrant
  {
    require(trades.length <= MAX_SWAPS_PER_TX, "TMS"); // Too Many Swaps
    for(uint256 i=0; i<trades.length; i++)
    {
      // Use Uniswap V3 SwapRouter for all swaps
      executeV3Swap(fundId, trades[i]);
    }
  }

  function withdrawFee(uint256 fundId, address token, uint256 percentage) 
    external payable override onlyManager(msg.sender, fundId) nonReentrant
  {
    require(percentage > 0 && percentage <= 10000, "IP"); // 0.01% to 100%
    
    uint256 totalFeeAmount = ISteleFundInfo(info).getFeeTokenAmount(fundId, token);
    require(totalFeeAmount > 0, "NF"); // No fee available
    
    // Calculate amount to withdraw using high precision
    uint256 amount = PriceOracle.precisionMul(totalFeeAmount, percentage, 10000);
    
    // If amount is 0 due to rounding, return
    if (amount == 0) {
      return; // Save gas
    }
    
    // Ensure we don't withdraw more than available
    if (amount > totalFeeAmount) {
      amount = totalFeeAmount;
    }
    
    // Update state FIRST (before external calls)
    bool isSuccess = ISteleFundInfo(info).decreaseFeeToken(fundId, token, amount);
    require(isSuccess, "FD");
    
    // This line should not be here - fee tokens are separate from fund tokens
    // ISteleFundInfo(info).decreaseFundToken(fundId, token, amount);
    
    emit WithdrawFee(fundId, msg.sender, token, amount);
    
    // External calls LAST
    if (token == weth9) {
      IWETH9(weth9).withdraw(amount);
      (bool success, ) = payable(msg.sender).call{value: amount}("");
      require(success, "FW");
    } else {
      IERC20Minimal(token).transfer(msg.sender, amount);
    }
  }

  // Transfer ownership (only owner)
  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "ZA"); // Zero Address
    owner = newOwner;
    emit OwnershipTransferred(msg.sender, newOwner);
  }

  // Set Manager NFT Contract (only callable by info contract owner)
  function setManagerNFTContract(address _managerNFTContract) external override onlyOwner {
    require(_managerNFTContract != address(0), "NZ");
    managerNFTContract = _managerNFTContract;
    emit ManagerNFTContractSet(_managerNFTContract);
  }

  // Get Manager NFT Contract address
  function getManagerNFTContract() external view override returns (address) {
    return managerNFTContract;
  }

  // Mint Manager NFT (only callable by fund manager)
  function mintManagerNFT(uint256 fundId) external override onlyManager(msg.sender, fundId) nonReentrant returns (uint256) {
    require(managerNFTContract != address(0), "NNC"); // NFT Contract Not set
    address manager = ISteleFundInfo(info).manager(fundId);
    require(manager == msg.sender, "NM");

    // Create mint parameters
    MintParams memory params = MintParams({
      fundId: fundId,
      fundCreated: ISteleFundInfo(info).fundCreationBlock(fundId), // Get actual fund creation block
      investment: ISteleFundInfo(info).getFundShare(fundId),
      currentTVL: getPortfolioValueUSD(fundId)
    });

    // Call NFT contract to mint
    return ISteleFundManagerNFT(managerNFTContract).mintManagerNFT(params);
  }
}
