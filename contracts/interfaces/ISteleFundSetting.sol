// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

interface ISteleFundSetting {
  event SettingCreated();
  event AddToken(address indexed token);

  function weth9() external view returns (address);
  function usdc() external view returns (address);
  function managerFee() external view returns (uint256);
  function maxSlippage() external view returns (uint256);
  function isInvestable(address _token) external view returns (bool);
}