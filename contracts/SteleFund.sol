// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundManagerNFT.sol";
import "./libraries/PriceOracle.sol";
import "./libraries/Path.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
  function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}


contract SteleFund is ISteleFund, ReentrancyGuard {
  using PriceOracle for address;
  using Path for bytes;
  using SafeERC20 for IERC20;

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

  address public info;
  address public managerNFTContract; // SteleFundManagerNFT contract address

  uint256 public override managerFee = 100; // 100 : 1%
  uint256 public override maxSlippage = 300; // Maximum 3% slippage allowed (300 = 3%)

  address public weth9;
  address public usdToken;
  address public wbtc;
  address public uni;
  address public link;

  mapping(address => bool) public override isInvestable;


  modifier onlyOwner() {
      require(msg.sender == owner, 'NO');
      _;
  }

  modifier onlyManager(address sender, uint256 fundId) {
    require(fundId == ISteleFundInfo(info).managingFund(sender), "NM");
    _;
  }

  constructor(
    address _info,
    address _weth9,
    address _usdToken,
    address _wbtc,
    address _uni,
    address _link
  ) {
    info = _info;

    isInvestable[_weth9] = true;
    isInvestable[_usdToken] = true;
    isInvestable[_wbtc] = true;
    isInvestable[_uni] = true;
    isInvestable[_link] = true;

    emit AddToken(_weth9);
    emit AddToken(_usdToken);
    emit AddToken(_wbtc);
    emit AddToken(_uni);
    emit AddToken(_link);

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
    // ETH deposit with fundId (requires 32 bytes calldata)
    uint256 fundId = parseFundId(msg.data);

    // Verify fund exists (fundId > 0 already checked in parseFundId)
    require(fundId <= ISteleFundInfo(info).fundIdCount(), "FNE");
    require(ISteleFundInfo(info).isJoined(msg.sender, fundId), "US");
    
    // Check minimum USD deposit amount
    {
      uint256 depositUSD = PriceOracle.getTokenPriceUSD(uniswapV3Factory, weth9, msg.value, weth9, usdToken);
      uint8 decimals = IERC20Metadata(usdToken).decimals();
      require(decimals <= 18, "ID"); // Prevent overflow
      require(depositUSD >= MIN_DEPOSIT_USD * (10 ** uint256(decimals)), "MDA"); // Minimum $10 deposit
    }
    
    // Calculate manager fee (only for investors, not manager)
    uint256 feeAmount = 0;
    uint256 fundAmount = msg.value;
    if (msg.sender != ISteleFundInfo(info).manager(fundId)) {
      feeAmount = PriceOracle.mulDiv(msg.value, managerFee, BASIS_POINTS);
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
    
    // External call LAST
    IWETH9(weth9).deposit{value: msg.value}();

    emit Deposit(fundId, msg.sender, weth9, msg.value, investorShare, fundShare, fundAmount, feeAmount);
  }

  receive() external payable {
    require(msg.sender == weth9, "OW"); // Only WETH unwrap
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

          // External calls
          if (token == weth9) {
            IWETH9(weth9).withdraw(tokenShare);
            (bool success, ) = payable(msg.sender).call{value: tokenShare}("");
            require(success, "FW");
          } else {
            IERC20(token).safeTransfer(msg.sender, tokenShare);
          }
        }
      }
    }

    emit Withdraw(fundId, msg.sender, percentage, investorShareAfter, fundShareAfter);
  }

  // Get last token from multi-hop path and validate intermediate tokens
  function getLastTokenFromPath(bytes memory path) private view returns (address) {
    address tokenOut;
    uint256 hopCount = 0;
    uint256 MAX_HOPS = 3;

    while (true) {
      require(hopCount < MAX_HOPS, "TMP"); // Too Many Pools

      bool hasMultiplePools = path.hasMultiplePools();
      (, tokenOut, ) = path.decodeFirstPool();

      // Validate intermediate tokens (not first, not last)
      if (hasMultiplePools && hopCount > 0) {
        // Intermediate token must be WETH or USDC
        require(tokenOut == weth9 || tokenOut == usdToken, "IIT"); // Invalid Intermediate Token
      }

      if (!hasMultiplePools) break;
      path = path.skipToken();
      hopCount++;
    }
    return tokenOut;
  }

  // Execute single-hop swap
  function exactInputSingle(uint256 fundId, SwapParams calldata trade) private {
    require(isInvestable[trade.tokenOut], "NWT");
    require(trade.amountIn <= ISteleFundInfo(info).getFundTokenAmount(fundId, trade.tokenIn), "NET");

    // Calculate minimum output with slippage protection (ignores Manager's input)
    uint256 minOutput = _calculateMinOutput(trade.tokenIn, trade.tokenOut, trade.amountIn);

    // Approve with SafeERC20 to prevent approve race condition
    IERC20(trade.tokenIn).safeApprove(swapRouter, 0);
    IERC20(trade.tokenIn).safeApprove(swapRouter, trade.amountIn);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: trade.tokenIn,
      tokenOut: trade.tokenOut,
      fee: trade.fee,
      recipient: address(this),
      deadline: block.timestamp + 180, // 3 minutes deadline
      amountIn: trade.amountIn,
      amountOutMinimum: minOutput, // Use calculated minOutput
      sqrtPriceLimitX96: 0
    });

    uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

    handleSwap(fundId, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
  }

  // Execute multi-hop swap
  function exactInput(uint256 fundId, SwapParams calldata trade) private {
    address tokenOut = getLastTokenFromPath(trade.path);
    (address tokenIn, , ) = trade.path.decodeFirstPool();

    require(isInvestable[tokenOut], "NWT");
    require(trade.amountIn <= ISteleFundInfo(info).getFundTokenAmount(fundId, tokenIn), "NET");

    // Calculate minimum output with slippage protection (ignores Manager's input)
    uint256 minOutput = _calculateMinOutput(tokenIn, tokenOut, trade.amountIn);

    // Approve with SafeERC20 to prevent approve race condition
    IERC20(tokenIn).safeApprove(swapRouter, 0);
    IERC20(tokenIn).safeApprove(swapRouter, trade.amountIn);

    ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
      path: trade.path,
      recipient: address(this),
      deadline: block.timestamp + 180, // 3 minutes deadline
      amountIn: trade.amountIn,
      amountOutMinimum: minOutput // Use calculated minOutput
    });

    uint256 amountOut = ISwapRouter(swapRouter).exactInput(params);

    handleSwap(fundId, tokenIn, tokenOut, trade.amountIn, amountOut);
  }

  // Handle swap state updates
  function handleSwap(
    uint256 fundId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
  ) private {
    ISteleFundInfo(info).decreaseFundToken(fundId, tokenIn, amountIn);
    ISteleFundInfo(info).increaseFundToken(fundId, tokenOut, amountOut);
    emit Swap(fundId, tokenIn, tokenOut, amountIn, amountOut);
  }

  // Calculate minimum output with slippage protection using spot price
  function _calculateMinOutput(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) private view returns (uint256) {
    // Get expected output from oracle (spot price)
    uint256 amountInETH = PriceOracle.getTokenPriceETH(uniswapV3Factory, tokenIn, weth9, amountIn);
    uint256 expectedOutput = PriceOracle.getTokenPriceETH(uniswapV3Factory, weth9, tokenOut, amountInETH);

    // Calculate minimum acceptable output: expectedOutput * (10000 - maxSlippage) / 10000
    uint256 minOutput = PriceOracle.mulDiv(expectedOutput, 10000 - maxSlippage, 10000);

    return minOutput;
  }

  function swap(uint256 fundId, SwapParams[] calldata trades)
    external override onlyManager(msg.sender, fundId) nonReentrant
  {
    require(trades.length <= MAX_SWAPS_PER_TX, "TMS");

    for (uint256 i = 0; i < trades.length; i++) {
      if (trades[i].swapType == SwapType.EXACT_INPUT_SINGLE_HOP) {
        exactInputSingle(fundId, trades[i]);
      } else if (trades[i].swapType == SwapType.EXACT_INPUT_MULTI_HOP) {
        exactInput(fundId, trades[i]);
      }
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

    // External calls BEFORE event emission (CEI pattern)
    if (token == weth9) {
      IWETH9(weth9).withdraw(amount);
      (bool success, ) = payable(msg.sender).call{value: amount}("");
      require(success, "FW");
    } else {
      IERC20(token).safeTransfer(msg.sender, amount);
    }

    // Event LAST - only emit after successful transfer
    emit WithdrawFee(fundId, msg.sender, token, amount);
  }

  // Transfer ownership (only owner)
  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "ZA"); // Zero Address
    owner = newOwner;
    emit OwnershipTransferred(msg.sender, newOwner);
  }

  // Renounce ownership of the contract
  function renounceOwnership() external onlyOwner {
    emit OwnershipTransferred(owner, address(0));
    owner = address(0);
  }

  // Set Manager NFT Contract (only callable by info contract owner)
  function setManagerNFTContract(address _managerNFTContract) external override onlyOwner {
    require(_managerNFTContract != address(0), "NZ");
    managerNFTContract = _managerNFTContract;
    emit ManagerNFTContractSet(_managerNFTContract);
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
