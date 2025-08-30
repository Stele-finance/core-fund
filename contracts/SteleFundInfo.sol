// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './base/Token.sol';
import './interfaces/ISteleFundInfo.sol';

contract SteleFundInfo is Token, ISteleFundInfo {
  address public override owner;
  mapping(uint256 => address) public override manager;                    // manager[fundId]
  uint256 public override fundIdCount = 0;
  
  // Maximum funds per investor to prevent DoS attacks
  uint256 public constant MAX_FUNDS_PER_INVESTOR = 100;

  // fundId
  mapping(address => uint256) public override managingFund;               // managingFund[manager]
  mapping(address => mapping(uint256 => uint256)) public investingFunds;  // investingFunds[investor][index]
  mapping(address => uint256) public investingFundCount;

  // Token
  mapping(uint256 => IToken.Token[]) public fundTokens;                        // fundTokens[fundId]
  mapping(uint256 => IToken.Token[]) public feeTokens;                         // feeTokens[fundId]

  // Investor Shares
  mapping(uint256 => mapping(address => uint256)) public investorShares;  // investorShares[fundId][investor]
  mapping(uint256 => uint256) public fundShares;                     // fundShares[fundId]

  modifier onlyOwner() {
    require(msg.sender == owner, 'NO');
    _;
  }

  constructor() {
    owner = msg.sender;
    emit InfoCreated();
  }

  function setOwner(address newOwner) external override onlyOwner {
    address oldOwner = owner;
    owner = newOwner;
    emit OwnerChanged(oldOwner, newOwner);
  }

  function getFundTokens(uint256 fundId) external override view returns (IToken.Token[] memory) {
    return fundTokens[fundId];
  }

  function getInvestorShare(uint256 fundId, address investor) external override view returns (uint256) {
    return investorShares[fundId][investor];
  }

  function getFundShare(uint256 fundId) external override view returns (uint256) {
    return fundShares[fundId];
  }
  
  function getFeeTokens(uint256 fundId) external override view returns (IToken.Token[] memory) {
    return feeTokens[fundId];
  }

  function getFundTokenAmount(uint256 fundId, address token) public override view returns (uint256) {
    IToken.Token[] memory tokens = fundTokens[fundId];
    for (uint256 i=0; i<tokens.length; i++) {
      if (tokens[i].token == token) {
        return tokens[i].amount;
      }
    }
    return 0;
  }

  function getFeeTokenAmount(uint256 fundId, address token) public override view returns (uint256) {
    IToken.Token[] memory tokens = feeTokens[fundId];
    for (uint256 i=0; i<tokens.length; i++) {
      if (tokens[i].token == token) {
        return tokens[i].amount;
      }
    }
    return 0;
  }
  
  function create() external override returns (uint256 fundId) {
    require(managingFund[msg.sender] == 0, 'EXIST');
    uint256 fundCount = investingFundCount[msg.sender];
    require(fundCount < MAX_FUNDS_PER_INVESTOR, 'MFR'); // Max Funds Reached
    fundId = ++fundIdCount;
    managingFund[msg.sender] = fundId;
    investingFunds[msg.sender][fundCount] = fundId;
    investingFundCount[msg.sender] += 1;
    manager[fundId] = msg.sender;
    emit Create(fundId, msg.sender);
  }

  function isJoined(address investor, uint256 fundId) public override view returns (bool) {
    uint256 fundCount = investingFundCount[investor];
    for (uint256 i=0; i<fundCount; i++) {
      if (fundId == investingFunds[investor][i]) {
        return true;
      }
    }
    return false;
  }

  function join(uint256 fundId) external override {
    require(fundId > 0 && fundId <= fundIdCount, 'FNE'); // Fund Not Exists
    require(manager[fundId] != address(0), 'NFM'); // No Fund Manager
    require(!isJoined(msg.sender, fundId), 'EXIST');
    uint256 fundCount = investingFundCount[msg.sender];
    require(fundCount < MAX_FUNDS_PER_INVESTOR, 'MFR'); // Max Funds Reached
    investingFunds[msg.sender][fundCount] = fundId;
    investingFundCount[msg.sender] += 1;
    emit Join(fundId, msg.sender);
  }

  function increaseShare(uint256 fundId, address investor, uint256 amount) external override onlyOwner returns (uint256, uint256) {
    investorShares[fundId][investor] += amount;
    fundShares[fundId] += amount;
    uint256 investorShare = investorShares[fundId][investor];
    uint256 fundShare = fundShares[fundId];
    return (investorShare, fundShare);
  }

  function decreaseShare(uint256 fundId, address investor, uint256 amount) external override onlyOwner returns (uint256, uint256) {
    require(investorShares[fundId][investor] >= amount, "IS");
    require(fundShares[fundId] >= amount, "ITS");

    investorShares[fundId][investor] -= amount;
    fundShares[fundId] -= amount;
    uint256 investorShare = investorShares[fundId][investor];
    uint256 fundShare = fundShares[fundId];
    return (investorShare, fundShare);
  }

  function increaseFundToken(uint256 fundId, address token, uint256 amount) external override onlyOwner {
    increaseToken(fundTokens[fundId], token, amount);
  }

  function decreaseFundToken(uint256 fundId, address token, uint256 amount) external override onlyOwner returns (bool) {
    return decreaseToken(fundTokens[fundId], token, amount);
  }

  function increaseFeeToken(uint256 fundId, address token, uint256 amount) external override onlyOwner {
    increaseToken(feeTokens[fundId], token, amount);
  }

  function decreaseFeeToken(uint256 fundId, address token, uint256 amount) external override onlyOwner returns (bool) {
    return decreaseToken(feeTokens[fundId], token, amount);
  }
}