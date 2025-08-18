// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

// Simplified interfaces for Stele integration
import "./interfaces/ISteleFund.sol";
import "./interfaces/ISteleFundInfo.sol";
import "./interfaces/ISteleFundSetting.sol";
import "./libraries/Path.sol";

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


contract SteleFund is ISteleFund {
  uint128 constant MAX_INT = 2**128 - 1;
  address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

  address public weth9;
  address public setting;
  address public info;

  modifier onlyManager(address sender, uint256 fundId) {
    require(fundId == ISteleFundInfo(info).managingFund(sender), "NM");
    _;
  }

  constructor(address _weth9, address _setting, address _info) {
    weth9 = _weth9;
    setting = _setting;
    info = _info;
  }

  function decode(bytes memory data) private pure returns (bytes32 result) {
    assembly {
      result := mload(add(data, 32))
    }
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

    bool isSubscribed = ISteleFundInfo(info).isSubscribed(msg.sender, fundId);
    require(isSubscribed, "US");
    IWETH9(weth9).deposit{value: amount}();
    ISteleFundInfo(info).increaseFundToken(fundId, weth9, amount);
    ISteleFundInfo(info).increaseInvestorToken(fundId, msg.sender, weth9, amount);
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
    bool isSubscribed = ISteleFundInfo(info).isSubscribed(msg.sender, fundId);
    bool isInvestable = ISteleFundSetting(setting).isInvestable(token);
    require(isSubscribed, "US");
    require(isInvestable, "NWT");

    IERC20Minimal(token).transferFrom(msg.sender, address(this), amount);
    ISteleFundInfo(info).increaseFundToken(fundId, token, amount);
    ISteleFundInfo(info).increaseInvestorToken(fundId, msg.sender, token, amount);
    emit Deposit(fundId, msg.sender, token, amount);
  }

  function withdraw(uint256 fundId, address token, uint256 amount) external payable override {
    bool isSubscribed = ISteleFundInfo(info).isSubscribed(msg.sender, fundId);
    uint256 tokenAmount = ISteleFundInfo(info).getInvestorTokenAmount(fundId, msg.sender, token);
    require(isSubscribed, "US");
    require(tokenAmount >= amount, "NET");

    if (msg.sender == ISteleFundInfo(info).manager(fundId)) {
      if (token == weth9) {
        IWETH9(weth9).withdraw(amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "FW");
      } else {
        IERC20Minimal(token).transfer(msg.sender, amount);
      }
      ISteleFundInfo(info).decreaseFundToken(fundId, token, amount);
      ISteleFundInfo(info).decreaseInvestorToken(fundId, msg.sender, token, amount);
      emit Withdraw(fundId, msg.sender, token, amount, 0);

    } else {
      uint256 managerFee = ISteleFundSetting(setting).managerFee();
      uint256 feeAmount = amount * managerFee / 10000 / 100;
      uint256 withdrawAmount = amount - feeAmount;
      ISteleFundInfo(info).decreaseFundToken(fundId, token, withdrawAmount);

      if (token == weth9) {
        IWETH9(weth9).withdraw(withdrawAmount);
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "FW");
      } else {
        IERC20Minimal(token).transfer(msg.sender, withdrawAmount);
      }
      ISteleFundInfo(info).decreaseInvestorToken(fundId, msg.sender, token, amount);
      emit Withdraw(fundId, msg.sender, token, withdrawAmount, feeAmount);
      ISteleFundInfo(info).increaseFeeToken(fundId, token, feeAmount);
      emit DepositFee(fundId, msg.sender, token, feeAmount);
    }
  }

  function handleSwap(
    uint256 fundId,
    address investor, 
    address swapFrom, 
    address swapTo, 
    uint256 swapFromAmount, 
    uint256 swapToAmount
  ) private {
    ISteleFundInfo(info).decreaseFundToken(fundId, swapFrom, swapFromAmount);
    ISteleFundInfo(info).decreaseInvestorToken(fundId, investor, swapFrom, swapFromAmount);
    ISteleFundInfo(info).increaseFundToken(fundId, swapTo, swapToAmount);
    ISteleFundInfo(info).increaseInvestorToken(fundId, investor, swapTo, swapToAmount);
    emit Swap(fundId, investor, swapFrom, swapTo, swapFromAmount, swapToAmount);
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

  function exactInputSingle(uint256 fundId, address investor, SwapParams calldata trade) private {
    require(ISteleFundSetting(setting).isInvestable(trade.tokenOut), "NWT");
    uint256 tokenBalance = ISteleFundInfo(info).getInvestorTokenAmount(fundId, investor, trade.tokenIn);
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
    
    handleSwap(fundId, investor, trade.tokenIn, trade.tokenOut, trade.amountIn, amountOut);
  }

  function exactInput(uint256 fundId, address investor, SwapParams calldata trade) private {
    address tokenOut = getLastTokenFromPath(trade.path);
    (address tokenIn, , ) = Path.decodeFirstPool(trade.path);
    require(ISteleFundSetting(setting).isInvestable(tokenOut), "NWT");
    uint256 tokenBalance = ISteleFundInfo(info).getInvestorTokenAmount(fundId, investor, tokenIn);
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

    handleSwap(fundId, investor, tokenIn, tokenOut, trade.amountIn, amountOut);
  }

  function swap(uint256 fundId, address investor, SwapParams[] calldata trades) 
    external override onlyManager(msg.sender, fundId)
  {
    for(uint256 i=0; i<trades.length; i++)
    {
      if (trades[i].swapType == SwapType.EXACT_INPUT_SINGLE_HOP) 
      {
        exactInputSingle(fundId, investor, trades[i]);
      } 
      else if (trades[i].swapType == SwapType.EXACT_INPUT_MULTI_HOP) 
      {
        exactInput(fundId, investor, trades[i]);
      }
    }
  }

  function withdrawFee(uint256 fundId, address token, uint256 amount) 
    external payable override onlyManager(msg.sender, fundId)
  {
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
