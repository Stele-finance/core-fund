// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IToken.sol';

interface ISteleFundInfo is IToken {
  event InfoCreated();
  event OwnerChanged(address owner, address newOwner);
  event Create(uint256 fundId, address indexed manager);
  event Join(uint256 fundId, address indexed investor);
  event UpdateShare(uint256 fundId, address indexed investor, uint256 share, uint256 totalShare);

  function owner() external view returns (address _owner);
  function manager(uint256 fundId) external view returns (address _manager);
  function managingFund(address _manager) external view returns (uint256 fundId);
  function fundIdCount() external view returns (uint256 fundCount);

  function setOwner(address newOwner) external;
  function create() external returns (uint256 fundId);
  function isJoined(address investor, uint256 fundId) external view returns (bool);
  function getInvestingFunds(address investor) external view returns (uint256[] memory);
  function join(uint256 fundId) external;

  function getFundTokens(uint256 fundId) external view returns (Token[] memory);
  function getFeeTokens(uint256 fundId) external view returns (Token[] memory);
  function getFundTokenAmount(uint256 fundId, address token) external view returns (uint256);
  function getFeeTokenAmount(uint256 fundId, address token) external view returns (uint256);
  function getInvestorShare(uint256 fundId, address investor) external view returns (uint256);
  function getInvestorSharePercentage(uint256 fundId, address investor) external view returns (uint256);
  function getTotalFundValue(uint256 fundId) external view returns (uint256);

  function increaseFundToken(uint256 fundId, address token, uint256 amount) external;
  function decreaseFundToken(uint256 fundId, address token, uint256 amount) external returns (bool);
  function increaseInvestorShare(uint256 fundId, address investor, uint256 amount) external;
  function decreaseInvestorShare(uint256 fundId, address investor, uint256 amount) external returns (bool);
  function increaseFeeToken(uint256 fundId, address token, uint256 amount) external;
  function decreaseFeeToken(uint256 fundId, address token, uint256 amount) external returns (bool);
}