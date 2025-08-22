// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundSetting.sol";
import "./libraries/Path.sol";
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
}

contract SteleFund is ISteleFund, IToken {
  using PriceOracle for address;
  
  // Uniswap V3 Contract
  address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // For price oracle

  // Precision scaling for more accurate calculations
  uint256 private constant PRECISION_SCALE = 1e18;
  
  // Minimum thresholds to prevent dust issues
  uint256 private constant MIN_SHARE_AMOUNT = 1000; // Minimum 1000 wei share
  
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

  function decode(bytes memory data) private pure returns (bytes32 result) {
    assembly {
      result := mload(add(data, 32))
    }
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

  // Calculate shares to mint based on USD value
  function _calculateSharesToMint(uint256 fundId, address token, uint256 amount) private view returns (uint256) {
    uint256 totalShares = ISteleFundInfo(info).getTotalFundValue(fundId);
    
    // First deposit: shares = USD value of deposit
    if (totalShares == 0) {
      return PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
    }
    
    // Get deposit value in USD
    uint256 depositValueUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, token, amount, weth9, usdToken);
    if (depositValueUSD == 0) return 0;
    
    // Get current portfolio value in USD
    uint256 portfolioValueUSD = getPortfolioValueUSD(fundId);
    if (portfolioValueUSD == 0) {
      return depositValueUSD; // Fallback to USD value
    }
    
    // Calculate shares: (depositValue / portfolioValue) * existingShares
    return PriceOracle.precisionMul(depositValueUSD, totalShares, portfolioValueUSD);
  }

  fallback() external payable { 
    uint256 amount = msg.value;
    uint256 length = msg.data.length;
    (bytes32 byteData) = decode(msg.data);

    uint256 converted = 0;
    for (uint256 i=0; i<length; i++) {
      converted += uint8(byteData[i]) * (256 ** (length-i-1));
    }
    uint256 fundId = converted;

    bool isJoined = ISteleFundInfo(info).isJoined(msg.sender, fundId);
    require(isJoined, "US");
    IWETH9(weth9).deposit{value: amount}();
    
    // Calculate shares based on USD value
    uint256 sharesToMint = _calculateSharesToMint(fundId, weth9, amount);
    
    ISteleFundInfo(info).increaseFundToken(fundId, weth9, amount);
    ISteleFundInfo(info).increaseInvestorShare(fundId, msg.sender, sharesToMint);
    emit Deposit(fundId, msg.sender, weth9, amount);
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

    IERC20Minimal(token).transferFrom(msg.sender, address(this), amount);
    
    // Calculate shares based on USD value
    uint256 sharesToMint = _calculateSharesToMint(fundId, token, amount);
    
    ISteleFundInfo(info).increaseFundToken(fundId, token, amount);
    ISteleFundInfo(info).increaseInvestorShare(fundId, msg.sender, sharesToMint);
    emit Deposit(fundId, msg.sender, token, amount);
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
    
    // For very small shares, recommend 100% withdrawal to avoid dust
    if (shareToWithdraw < MIN_SHARE_AMOUNT && percentage < 10000) {
      // Allow small withdrawals but emit a warning event
      // Users might want to consider 100% withdrawal instead
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
    
    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        // Use higher precision calculation to minimize rounding errors
        uint256 tokenShare = PriceOracle.precisionMul(fundTokens[i].amount, shareToWithdraw, totalValue);
        
        // Ensure we don't withdraw more than available
        if (tokenShare > fundTokens[i].amount) {
          tokenShare = fundTokens[i].amount;
        }
        
        // If tokenShare is 0 due to rounding, skip this token
        // Very small amounts can be considered dust and ignored
        
        if (tokenShare > 0) {
          address token = fundTokens[i].token;
          
          if (token == weth9) {
            IWETH9(weth9).withdraw(tokenShare);
            (bool success, ) = payable(msg.sender).call{value: tokenShare}("");
            require(success, "FW");
          } else {
            IERC20Minimal(token).transfer(msg.sender, tokenShare);
          }
          
          ISteleFundInfo(info).decreaseFundToken(fundId, token, tokenShare);
          emit Withdraw(fundId, msg.sender, token, tokenShare, 0);
        }
      }
    }
    
    ISteleFundInfo(info).decreaseInvestorShare(fundId, msg.sender, shareToWithdraw);
  }
  
  function _withdrawInvestor(uint256 fundId, uint256 shareToWithdraw, uint256 /* percentage */) private {
    Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 totalValue = ISteleFundInfo(info).getTotalFundValue(fundId);
    require(totalValue > 0, "ZTV"); // Zero total value
    uint256 managerFee = ISteleFundSetting(setting).managerFee();
    
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
          
          // Calculate fee more precisely using high precision calculation
          // managerFee is in basis points, so we need to divide by 1000000 (10000 * 100)
          uint256 feeAmount = PriceOracle.precisionMul(tokenShare, managerFee, 1000000);
          
          // Ensure fee doesn't exceed token share
          if (feeAmount > tokenShare) {
            feeAmount = tokenShare;
          }
          
          uint256 withdrawAmount = tokenShare - feeAmount;
          
          if (withdrawAmount > 0) {
            if (token == weth9) {
              IWETH9(weth9).withdraw(withdrawAmount);
              (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
              require(success, "FW");
            } else {
              IERC20Minimal(token).transfer(msg.sender, withdrawAmount);
            }
          }
          
          // Update fund and fee tokens with actual amounts
          if (withdrawAmount > 0) {
            ISteleFundInfo(info).decreaseFundToken(fundId, token, withdrawAmount);
          }
          if (feeAmount > 0) {
            ISteleFundInfo(info).increaseFeeToken(fundId, token, feeAmount);
            emit DepositFee(fundId, msg.sender, token, feeAmount);
          }
          
          emit Withdraw(fundId, msg.sender, token, withdrawAmount, feeAmount);
        }
      }
    }
    
    ISteleFundInfo(info).decreaseInvestorShare(fundId, msg.sender, shareToWithdraw);
  }

  function handleSwap(
    uint256 fundId,
    address swapFrom, 
    address swapTo, 
    uint256 swapFromAmount, 
    uint256 swapToAmount
  ) private {
    ISteleFundInfo(info).decreaseFundToken(fundId, swapFrom, swapFromAmount);
    ISteleFundInfo(info).increaseFundToken(fundId, swapTo, swapToAmount);
    emit Swap(fundId, swapFrom, swapTo, swapFromAmount, swapToAmount);
  }

  // Uniswap V3 Swap Implementation
  function executeV3Swap(uint256 fundId, SwapParams calldata trade) private {
    require(ISteleFundSetting(setting).isInvestable(trade.tokenOut), "NWT");
    uint256 tokenBalance = ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenIn);
    require(trade.amountIn <= tokenBalance, "NET");

    // Approve V3 router for testing
    IERC20Minimal(trade.tokenIn).approve(swapRouter, trade.amountIn);

    // Use V3 exactInputSingle for swapping
    bytes memory swapCall = abi.encodeWithSignature(
      "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
      trade.tokenIn,
      trade.tokenOut,
      trade.fee,
      address(this),
      block.timestamp + 300,
      trade.amountIn,
      trade.amountOutMinimum,
      0
    );
    
    uint256 balanceBefore = IERC20Minimal(trade.tokenOut).balanceOf(address(this));

    (bool success, ) = swapRouter.call(swapCall);
    require(success, "Swap failed");
    
    uint256 balanceAfter = IERC20Minimal(trade.tokenOut).balanceOf(address(this));
    uint256 amountOut = balanceAfter - balanceBefore;
    
    require(amountOut >= trade.amountOutMinimum, "Insufficient output amount");
    
    handleSwap(fundId, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
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
    
    bool isSuccess = ISteleFundInfo(info).decreaseFeeToken(fundId, token, amount);
    require(isSuccess, "FD");
    
    if (token == weth9) {
      IWETH9(weth9).withdraw(amount);
      (bool success, ) = payable(msg.sender).call{value: amount}("");
      require(success, "FW");
    } else {
      IERC20Minimal(token).transfer(msg.sender, amount);
    }
    
    ISteleFundInfo(info).decreaseFundToken(fundId, token, amount);
    emit WithdrawFee(fundId, msg.sender, token, amount);
  }
}
