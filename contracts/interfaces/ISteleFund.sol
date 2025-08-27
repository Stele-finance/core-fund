// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISteleFund {
  event Deposit(uint256 fundId, address indexed investor, address token, uint256 amount, uint256 share, uint256 totalShare);
  event Withdraw(uint256 fundId, address indexed investor, uint256 share, uint256 totalShare);
  event Swap(uint256 fundId, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
  event DepositFee(uint256 fundId, address indexed investor, address token, uint256 amount);
  event WithdrawFee(uint256 fundId, address indexed manager, address token, uint256 amount);

  struct SwapParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  function withdraw(uint256 fundId, uint256 percentage) external payable;
  function swap(uint256 fundId, SwapParams[] calldata trades) external;
  function withdrawFee(uint256 fundId, address token, uint256 percentage) external payable;
}