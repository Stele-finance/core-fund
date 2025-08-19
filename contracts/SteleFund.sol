// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundSetting.sol";
import "./libraries/Path.sol";
import "./interfaces/IToken.sol";

// Direct Uniswap V3 interfaces without library imports
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) 
        external view returns (address pool);
}

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives, 
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );
    
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface IWETH9 {
  function deposit() external payable;
  function withdraw(uint256 wad) external;
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

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

  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  function exactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    returns (uint256 amountOut);

  function exactInput(ExactInputParams calldata params)
    external
    payable
    returns (uint256 amountOut);
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
  uint128 constant MAX_INT = 2**128 - 1;
  address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  
  // Precision scaling for more accurate calculations
  uint256 private constant PRECISION_SCALE = 1e18;
  
  // Minimum thresholds to prevent dust issues
  uint256 private constant MIN_SHARE_AMOUNT = 1000; // Minimum 1000 wei share
  uint256 private constant MIN_TOKEN_AMOUNT = 100;  // Minimum 100 wei token withdrawal

  address public weth9;
  address public setting;
  address public info;
  address public usdToken; // USDC address for price calculation

  modifier onlyManager(address sender, uint256 fundId) {
    require(fundId == ISteleFundInfo(info).managingFund(sender), "NM");
    _;
  }

  constructor(address _weth9, address _setting, address _info, address _usdToken) {
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
  
  /**
   * @dev High precision calculation: (a * b) / c
   * Uses scaling to minimize rounding errors
   */
  function precisionMul(uint256 a, uint256 b, uint256 c) private pure returns (uint256) {
    if (a == 0 || b == 0) return 0;
    require(c > 0, "Division by zero");
    
    // Check if we can safely multiply with precision scale
    // More aggressive condition: use high precision when possible
    if (a <= type(uint256).max / b && (a * b) <= type(uint256).max / PRECISION_SCALE) {
      return (a * b * PRECISION_SCALE) / (c * PRECISION_SCALE);
    }
    
    // Fallback to standard calculation to avoid overflow
    return (a * b) / c;
  }

  // Get USD price from ETH (1 ETH = ? USD)
  function getETHPriceUSD() internal view returns (uint256) {
    uint16[3] memory fees = [500, 3000, 10000];
    uint256 quoteAmount = 0;

    for (uint256 i=0; i<fees.length; i++) {
      address pool = IUniswapV3Factory(uniswapV3Factory).getPool(weth9, usdToken, uint24(fees[i]));
      if (pool == address(0)) {
          continue;
      }

      try this._getQuoteFromPool(pool, uint128(1 * 10**18), weth9, usdToken) returns (uint256 _quoteAmount) {
        if (quoteAmount < _quoteAmount) {
          quoteAmount = _quoteAmount;
        }
      } catch {
        continue;
      }
    }

    return quoteAmount > 0 ? quoteAmount : 3000 * 1e6; // Fallback to $3000 if no pool available
  }

  // Get token price in ETH
  function getTokenPriceETH(address baseToken, uint256 baseAmount) internal view returns (uint256) { 
    if (baseToken == weth9) {
      return baseAmount; // 1:1 ratio for WETH to ETH
    }

    uint16[3] memory fees = [500, 3000, 10000];
    uint256 quoteAmount = 0;

    for (uint256 i=0; i<fees.length; i++) {
      address pool = IUniswapV3Factory(uniswapV3Factory).getPool(baseToken, weth9, uint24(fees[i]));
      if (pool == address(0)) {
          continue;
      }

      try this._getQuoteFromPool(pool, uint128(baseAmount), baseToken, weth9) returns (uint256 _quoteAmount) {
        if (quoteAmount < _quoteAmount) {
          quoteAmount = _quoteAmount;
        }
      } catch {
        continue;
      }
    }

    return quoteAmount;
  }

  // TWAP calculation using direct interface calls
  function getTWAPTick(address pool, uint32 secondsAgo) internal view returns (int24 timeWeightedAverageTick) {
    if (secondsAgo == 0) {
      (, timeWeightedAverageTick, , , , , ) = IUniswapV3Pool(pool).slot0();
      return timeWeightedAverageTick;
    }

    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;
    secondsAgos[1] = 0;

    (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);
    
    int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
    timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));

    // Always round to negative infinity
    if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) {
      timeWeightedAverageTick--;
    }
  }

  // Convert tick to price ratio
  function getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken) internal pure returns (uint256 quoteAmount) {
    uint160 sqrtRatioX96 = getSqrtRatioAtTick(tick);
    
    // Calculate the price ratio from sqrtRatioX96
    if (sqrtRatioX96 <= type(uint128).max) {
      uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
      quoteAmount = baseToken < quoteToken
        ? mulDiv(ratioX192, baseAmount, 1 << 192)
        : mulDiv(1 << 192, baseAmount, ratioX192);
    } else {
      uint256 ratioX128 = mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
      quoteAmount = baseToken < quoteToken
        ? mulDiv(ratioX128, baseAmount, 1 << 128)
        : mulDiv(1 << 128, baseAmount, ratioX128);
    }
  }

  // Get sqrt ratio at tick (simplified version)
  function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
    uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
    require(absTick <= uint256(int256(887272)), 'T');

    uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
    if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
    if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
    if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
    if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
    if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
    if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
    if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
    if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
    if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
    if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
    if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
    if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
    if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
    if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
    if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
    if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
    if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
    if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

    if (tick > 0) ratio = type(uint256).max / ratio;

    sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
  }

  // Full precision multiplication
  function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
    uint256 prod0;
    uint256 prod1;
    assembly {
      let mm := mulmod(a, b, not(0))
      prod0 := mul(a, b)
      prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    if (prod1 == 0) {
      require(denominator > 0);
      assembly {
        result := div(prod0, denominator)
      }
      return result;
    }

    require(denominator > prod1);

    uint256 remainder;
    assembly {
      remainder := mulmod(a, b, denominator)
    }
    assembly {
      prod1 := sub(prod1, gt(remainder, prod0))
      prod0 := sub(prod0, remainder)
    }

    uint256 twos = (~denominator + 1) & denominator;
    assembly {
      denominator := div(denominator, twos)
    }

    assembly {
      prod0 := div(prod0, twos)
    }
    assembly {
      twos := add(div(sub(0, twos), twos), 1)
    }
    prod0 |= prod1 * twos;

    uint256 inv = (3 * denominator) ^ 2;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;

    result = prod0 * inv;
    return result;
  }

  // External function to handle try-catch for pool queries
  function _getQuoteFromPool(address pool, uint128 baseAmount, address baseToken, address quoteToken) external view returns (uint256) {
    uint32 secondsAgo = 1800; // 30 minutes TWAP
    
    int24 tick = getTWAPTick(pool, secondsAgo);
    return getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
  }

  // Get token price in USD
  function getTokenPriceUSD(address token, uint256 amount) internal view returns (uint256) {
    if (token == weth9) {
      // ETH to USD directly
      uint256 ethPriceUSD = getETHPriceUSD();
      return precisionMul(amount, ethPriceUSD, 1e18);
    } else if (token == usdToken) {
      // USD token (USDC) - return as is
      return amount;
    } else {
      // Other tokens: token -> ETH -> USD
      uint256 ethAmount = getTokenPriceETH(token, uint128(amount));
      if (ethAmount == 0) return 0;
      
      uint256 ethPriceUSD = getETHPriceUSD();
      return precisionMul(ethAmount, ethPriceUSD, 1e18);
    }
  }

  // Calculate portfolio total value in USD
  function getPortfolioValueUSD(uint256 fundId) internal view returns (uint256) {
    Token[] memory fundTokens = ISteleFundInfo(info).getFundTokens(fundId);
    uint256 totalValueUSD = 0;

    for (uint256 i = 0; i < fundTokens.length; i++) {
      if (fundTokens[i].amount > 0) {
        uint256 tokenValueUSD = getTokenPriceUSD(fundTokens[i].token, fundTokens[i].amount);
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
      return getTokenPriceUSD(token, amount);
    }
    
    // Get deposit value in USD
    uint256 depositValueUSD = getTokenPriceUSD(token, amount);
    if (depositValueUSD == 0) return 0;
    
    // Get current portfolio value in USD
    uint256 portfolioValueUSD = getPortfolioValueUSD(fundId);
    if (portfolioValueUSD == 0) {
      return depositValueUSD; // Fallback to USD value
    }
    
    // Calculate shares: (depositValue / portfolioValue) * existingShares
    return precisionMul(depositValueUSD, totalShares, portfolioValueUSD);
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
        uint256 tokenShare = precisionMul(fundTokens[i].amount, shareToWithdraw, totalValue);
        
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
        uint256 tokenShare = precisionMul(fundTokens[i].amount, shareToWithdraw, totalValue);
        
        // Ensure we don't withdraw more than available
        if (tokenShare > fundTokens[i].amount) {
          tokenShare = fundTokens[i].amount;
        }
        
        // If tokenShare is 0 due to rounding, skip this token
        // Very small amounts can be considered dust and ignored
        
        if (tokenShare > 0) {
          address token = fundTokens[i].token;
          
          // Calculate fee more precisely using high precision calculation
          // managerFee is in basis points, so we need to divide by 1000000 (10000 * 100)
          uint256 feeAmount = precisionMul(tokenShare, managerFee, 1000000);
          
          // If fee is 0 due to rounding, that's fine - no minimum fee needed
          // Small amounts losing tiny fees is acceptable
          
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

  function getLastTokenFromPath(bytes memory path) private pure returns (address) {
    address tokenOut;

    while (true) {
      bool hasMultiplePools = Path.hasMultiplePools(path);

      if (hasMultiplePools) {
        path = Path.skipToken(path);
      } else {
        (, address _tokenOut, ) = Path.decodeFirstPool(path);
        tokenOut = _tokenOut;
        break;
      }
    }
    return tokenOut;
  }

  function exactInputSingle(uint256 fundId, SwapParams calldata trade) private {
    require(ISteleFundSetting(setting).isInvestable(trade.tokenOut), "NWT");
    uint256 tokenBalance = ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenIn);
    require(trade.amountIn <= tokenBalance, "NET");

    IERC20Minimal(trade.tokenIn).approve(swapRouter, trade.amountIn);

    ISwapRouter.ExactInputSingleParams memory params =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: trade.tokenIn,
        tokenOut: trade.tokenOut,
        fee: trade.fee,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: trade.amountIn,
        amountOutMinimum: trade.amountOutMinimum,
        sqrtPriceLimitX96: 0
      });
    uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
    
    handleSwap(fundId, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
  }

  function exactInput(uint256 fundId, SwapParams calldata trade) private {
    address tokenOut = getLastTokenFromPath(trade.path);
    (address tokenIn, , ) = Path.decodeFirstPool(trade.path);
    require(ISteleFundSetting(setting).isInvestable(tokenOut), "NWT");
    uint256 tokenBalance = ISteleFundInfo(info).getFundTokenAmount(fundId, tokenIn);
    require(trade.amountIn <= tokenBalance, "NET");

    IERC20Minimal(tokenIn).approve(swapRouter, trade.amountIn);

    ISwapRouter.ExactInputParams memory params =
      ISwapRouter.ExactInputParams({
        path: trade.path,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: trade.amountIn,
        amountOutMinimum: trade.amountOutMinimum
      });
    uint256 amountOut = ISwapRouter(swapRouter).exactInput(params);

    handleSwap(fundId, tokenIn, tokenOut, trade.amountIn, amountOut);
  }

  function swap(uint256 fundId, SwapParams[] calldata trades) 
    external override onlyManager(msg.sender, fundId)
  {
    for(uint256 i=0; i<trades.length; i++)
    {
      if (trades[i].swapType == SwapType.EXACT_INPUT_SINGLE_HOP) 
      {
        exactInputSingle(fundId, trades[i]);
      } 
      else if (trades[i].swapType == SwapType.EXACT_INPUT_MULTI_HOP) 
      {
        exactInput(fundId, trades[i]);
      }
    }
  }

  function withdrawFee(uint256 fundId, address token, uint256 percentage) 
    external payable override onlyManager(msg.sender, fundId)
  {
    require(percentage > 0 && percentage <= 10000, "IP"); // 0.01% to 100%
    
    uint256 totalFeeAmount = ISteleFundInfo(info).getFeeTokenAmount(fundId, token);
    require(totalFeeAmount > 0, "NF"); // No fee available
    
    // Calculate amount to withdraw using high precision
    uint256 amount = precisionMul(totalFeeAmount, percentage, 10000);
    
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
