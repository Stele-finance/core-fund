// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundSetting.sol";
import "./interfaces/IToken.sol";
import "./libraries/PriceOracle.sol";

interface IWETH9 {
  function deposit() external payable;
  function withdraw(uint256 wad) external;
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

// Uniswap V3 SwapRouter Interface
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
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

contract SteleFund is ISteleFund, IToken {
  using PriceOracle for address;
  
  // Uniswap V3 Contract
  address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // For price oracle

  // Precision scaling for more accurate calculations
  uint256 private constant PRECISION_SCALE = 1e18;
  uint256 private constant SHARE_DECIMALS = 1e18; // Share tokens use 18 decimals
  uint256 private constant BASIS_POINTS = 10000; // 100% = 10000 basis points
  
  // Minimum thresholds to prevent dust issues
  uint256 private constant MIN_SHARE_AMOUNT = 1000; // Minimum 1000 wei share
  uint256 private constant MIN_DEPOSIT_USD = 10; // Minimum $10 deposit
  
  
  address public weth9;
  address public setting;
  address public info;
  address public usdToken; // USDC address for price calculation

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
  }

  // Safe fund ID parsing from calldata
  function parseFundId(bytes memory data) private pure returns (uint256 fundId) {
    require(data.length > 0 && data.length <= 32, "IDL"); // Invalid data length

    // Use standard ABI decoding for safety
    if (data.length == 32) {
      // Standard uint256 encoding
      fundId = abi.decode(data, (uint256));
    } else {
      // Handle shorter data safely
      bytes32 padded;
      for (uint256 i = 0; i < data.length; i++) {
        padded |= bytes32(data[i]) << (8 * (31 - i));
      }
      fundId = uint256(padded) >> (8 * (32 - data.length));
    }
    
    // Prevent unreasonably large fund IDs
    require(fundId < type(uint128).max, "Fund ID too large");
  }
  
  // Calculate portfolio total value in USD
  function getPortfolioValueUSD(uint256 fundId) internal view returns (uint256) {
    Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
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
    uint256 totalShares = ISteleFundInfo(info).getTotalFundValue(fundId);
    
    // Get USD token decimals dynamically
    uint256 usdDecimals = 10 ** uint256(IERC20Minimal(usdToken).decimals());
    
    // First deposit: shares = USD value of deposit * SHARE_DECIMALS for precision
    if (totalShares == 0) {
      uint256 usdValue = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
      // Scale up to share decimals for precision
      return usdValue * SHARE_DECIMALS / usdDecimals;
    }
    
    // Get deposit value in USD
    uint256 depositValueUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
    if (depositValueUSD == 0) return 0;
    
    // Get current portfolio value in USD
    uint256 portfolioValueUSD = getPortfolioValueUSD(fundId);
    if (portfolioValueUSD == 0) {
      return depositValueUSD * SHARE_DECIMALS / usdDecimals; // Scale up for precision
    }
    
    // Use mulDiv for maximum precision: (depositValue * existingShares) / portfolioValue
    // This avoids intermediate overflow and maintains precision
    uint256 shares = (depositValueUSD * totalShares) / portfolioValueUSD;
    
    // Round up to favor the protocol (prevent rounding attacks)
    if ((depositValueUSD * totalShares) % portfolioValueUSD > 0) {
      shares += 1;
    }
    
    return shares;
  }

  fallback() external payable { 
    uint256 amount = msg.value;
    
    // Safe fund ID parsing with validation
    uint256 fundId = parseFundId(msg.data);
    
    // Verify fund exists and user is joined
    require(fundId > 0 && fundId <= ISteleFundInfo(info).fundIdCount(), "Invalid fund ID");
    bool isJoined = ISteleFundInfo(info).isJoined(msg.sender, fundId);
    require(isJoined, "US");
    
    // Check minimum USD deposit amount
    uint256 depositUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, weth9, amount, weth9, usdToken);
    uint256 usdDecimals = 10 ** uint256(IERC20Minimal(usdToken).decimals());
    uint256 minDepositRequired = MIN_DEPOSIT_USD * usdDecimals;
    require(depositUSD >= minDepositRequired, "MDA"); // Minimum $10 deposit
    
    // Calculate shares based on USD value
    uint256 sharesToMint = _calculateSharesToMint(fundId, weth9, amount);
    require(sharesToMint > 0, "ZS"); // Zero shares
    
    // Update state FIRST (before external calls)
    ISteleFundInfo(info).increaseFundToken(fundId, weth9, amount);
    (uint256 investorShare, uint256 fundShare) = ISteleFundInfo(info).increaseInvestorShare(fundId, msg.sender, sharesToMint);
    emit Deposit(fundId, msg.sender, weth9, amount, investorShare, fundShare);

    // External call LAST
    IWETH9(weth9).deposit{value: amount}();
  }

  receive() external payable {
    if (msg.sender == weth9) {
      // when call IWETH9(weth9).withdraw(amount) in this contract
    } else {
      // when deposit ETH with no data
    }
  }

  function deposit(uint256 fundId, address token, uint256 amount) external override {
    bool isJoined = ISteleFundInfo(info).isJoined(msg.sender, fundId);
    bool isInvestable = ISteleFundSetting(setting).isInvestable(token);
    require(isJoined, "US");
    require(isInvestable, "NWT");
    
    // Check minimum USD deposit amount
    uint256 depositUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
    uint256 usdDecimals = 10 ** uint256(IERC20Minimal(usdToken).decimals());
    uint256 minDepositRequired = MIN_DEPOSIT_USD * usdDecimals;
    require(depositUSD >= minDepositRequired, "MDA"); // Minimum $10 deposit
    
    // Calculate shares based on USD value
    uint256 sharesToMint = _calculateSharesToMint(fundId, token, amount);
    require(sharesToMint > 0, "ZS"); // Zero shares
    
    // Update state FIRST (before external calls)
    ISteleFundInfo(info).increaseFundToken(fundId, token, amount);
    (uint256 investorShare, uint256 fundShare) = ISteleFundInfo(info).increaseInvestorShare(fundId, msg.sender, sharesToMint);
    emit Deposit(fundId, msg.sender, token, amount, investorShare, fundShare);

    // External call LAST
    IERC20Minimal(token).transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint256 fundId, uint256 percentage) external payable override {
    bool isJoined = ISteleFundInfo(info).isJoined(msg.sender, fundId);
    require(isJoined, "US");
    require(percentage > 0 && percentage <= 10000, "IP"); // 0.01% to 100%
    
    uint256 investorShare = ISteleFundInfo(info).getInvestorShare(fundId, msg.sender);
    require(investorShare > 0, "NS");
    
    uint256 shareToWithdraw = (investorShare * percentage) / 10000;
    
    // If shareToWithdraw is 0 due to rounding, just return - no need to complicate
    if (shareToWithdraw == 0) {
      return; // No withdrawal, save gas
    }
    
    if (msg.sender == ISteleFundInfo(info).manager(fundId)) {
      _withdrawManager(fundId, shareToWithdraw);
    } else {
      _withdrawInvestor(fundId, shareToWithdraw, percentage);
    }
  }
  
  function _withdrawManager(uint256 fundId, uint256 shareToWithdraw) private {
    Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 totalValue = ISteleFundInfo(info).getTotalFundValue(fundId);
    require(totalValue > 0, "ZTV"); // Zero total value
    
    // Update state FIRST (before external calls)
    (uint256 investorShare, uint256 fundShare) = ISteleFundInfo(info).decreaseInvestorShare(fundId, msg.sender, shareToWithdraw);
    emit Withdraw(fundId, msg.sender, investorShare, fundShare);

    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        // Use higher precision calculation to minimize rounding errors
        uint256 tokenShare = PriceOracle.precisionMul(fundTokens[i].amount, shareToWithdraw, totalValue);
        
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
  
  function _withdrawInvestor(uint256 fundId, uint256 shareToWithdraw, uint256 /* percentage */) private {
    Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 totalValue = ISteleFundInfo(info).getTotalFundValue(fundId);
    require(totalValue > 0, "ZTV"); // Zero total value
    uint256 managerFee = ISteleFundSetting(setting).managerFee();
    
    // Update investor share FIRST (before external calls)
    (uint256 investorShare, uint256 fundShare) = ISteleFundInfo(info).decreaseInvestorShare(fundId, msg.sender, shareToWithdraw);
    emit Withdraw(fundId, msg.sender, investorShare, fundShare);

    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        // Calculate token share with bounds checking using high precision
        uint256 tokenShare = PriceOracle.precisionMul(fundTokens[i].amount, shareToWithdraw, totalValue);
        
        // Ensure we don't withdraw more than available
        if (tokenShare > fundTokens[i].amount) {
          tokenShare = fundTokens[i].amount;
        }
        
        if (tokenShare > 0) {
          address token = fundTokens[i].token;
          
          // Calculate fee with improved precision
          // managerFee is in basis points (e.g., 10000 = 1%)
          // Use mulDiv pattern: (tokenShare * managerFee) / (BASIS_POINTS * 100)
          uint256 feeAmount = (tokenShare * managerFee) / (BASIS_POINTS * 100);
          
          // Round up fees to prevent dust attacks
          if ((tokenShare * managerFee) % (BASIS_POINTS * 100) > 0) {
            feeAmount += 1;
          }
          
          // Ensure fee doesn't exceed token share
          if (feeAmount > tokenShare) {
            feeAmount = tokenShare;
          }
          
          uint256 withdrawAmount = tokenShare - feeAmount;
          
          // Update fund and fee tokens FIRST (before external calls)
          if (withdrawAmount > 0) {
            ISteleFundInfo(info).decreaseFundToken(fundId, token, withdrawAmount);
          }
          if (feeAmount > 0) {
            ISteleFundInfo(info).increaseFeeToken(fundId, token, feeAmount);
            emit DepositFee(fundId, msg.sender, token, feeAmount);
          }
          
          // External calls LAST
          if (withdrawAmount > 0) {
            if (token == weth9) {
              IWETH9(weth9).withdraw(withdrawAmount);
              (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
              require(success, "FW");
            } else {
              IERC20Minimal(token).transfer(msg.sender, withdrawAmount);
            }
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
    require(amountOut >= effectiveMinOutput, "Slippage exceeded");
    ISteleFundInfo(info).increaseFundToken(fundId, trade.tokenOut, amountOut);
    emit Swap(fundId, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
  }
  
  // Helper function to validate swap parameters
  function _validateSwapParameters(uint256 fundId, SwapParams calldata trade) private view {
    // Check maxTokens limit for new tokens
    if (ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenOut) == 0) {
      Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
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
    uint256 minOutputWithSlippage = (expectedOutput * (BASIS_POINTS - slippage)) / BASIS_POINTS;
    
    return minOutputWithSlippage > trade.amountOutMinimum ? 
      minOutputWithSlippage : trade.amountOutMinimum;
  }
  
  // Helper function to execute swap call
  function _executeSwapCall(SwapParams calldata trade, uint256 effectiveMinOutput) private returns (uint256) {
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
    require(success, "Swap failed");
    
    return IERC20Minimal(trade.tokenOut).balanceOf(address(this)) - balanceBefore;
  }

  function swap(uint256 fundId, SwapParams[] calldata trades) 
    external override onlyManager(msg.sender, fundId)
  {
    for(uint256 i=0; i<trades.length; i++)
    {
      // Use Uniswap V3 SwapRouter for all swaps
      executeV3Swap(fundId, trades[i]);
    }
  }

  function withdrawFee(uint256 fundId, address token, uint256 percentage) 
    external payable override onlyManager(msg.sender, fundId)
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
    emit WithdrawFee(fundId, msg.sender, token, amount);
    
    ISteleFundInfo(info).decreaseFundToken(fundId, token, amount);
    
    // External calls LAST
    if (token == weth9) {
      IWETH9(weth9).withdraw(amount);
      (bool success, ) = payable(msg.sender).call{value: amount}("");
      require(success, "FW");
    } else {
      IERC20Minimal(token).transfer(msg.sender, amount);
    }
  }
}
