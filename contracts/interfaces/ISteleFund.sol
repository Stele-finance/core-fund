// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISteleFund {
  event Deposit(uint256 fundId, address indexed investor, address token, uint256 amount, uint256 investorShare, uint256 fundShare, uint256 managerFee);
  event Withdraw(uint256 fundId, address indexed investor, uint256 percentage, uint256 investorShare, uint256 fundShare);
  event Swap(uint256 fundId, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
  event DepositFee(uint256 fundId, address indexed investor, address token, uint256 amount);
  event WithdrawFee(uint256 fundId, address indexed manager, address token, uint256 amount);
  event ManagerNFTContractSet(address indexed managerNFTContract);

  struct SwapParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  function owner() external view returns (address);
  function withdraw(uint256 fundId, uint256 percentage) external payable;
  function swap(uint256 fundId, SwapParams[] calldata trades) external;
  function withdrawFee(uint256 fundId, address token, uint256 percentage) external payable;
  function setManagerNFTContract(address _managerNFTContract) external;
  function getManagerNFTContract() external view returns (address);
  function mintManagerNFT(uint256 fundId) external returns (uint256);
}