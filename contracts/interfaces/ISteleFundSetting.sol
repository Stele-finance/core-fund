// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISteleFundSetting {
  event SettingCreated();
  event OwnerChanged(address oldOwner, address newOwner);
  event ManagerFeeChanged(uint256 managerFee);
  event AddToken(address indexed token);
  event RemoveToken(address indexed token);

  function owner() external view returns (address);
  function weth9() external view returns (address);
  function usdc() external view returns (address);
  function managerFee() external view returns (uint256);
  function isInvestable(address _token) external view returns (bool);

  function setOwner(address _owner) external;
  function setManagerFee(uint256 _managerFee) external;
  function setToken(address _token) external;
  function resetToken(address _token) external;
}