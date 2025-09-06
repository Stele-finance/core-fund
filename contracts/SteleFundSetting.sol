// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/ISteleFundSetting.sol';

interface IERC20Decimals {
  function decimals() external view returns (uint8);
  function balanceOf(address account) external view returns (uint256);
}

contract SteleFundSetting is ISteleFundSetting {
  address public override owner;
  address public override weth9;
  address public override usdc;

  uint256 public override managerFee = 100; // 100 : 1%
  uint256 public override maxTokens = 20; // Maximum number of different tokens in portfolio
  uint256 public override maxSlippage = 300; // Maximum 3% slippage allowed (300 = 3%)
  
  mapping(address => bool) public override isInvestable;

  modifier onlyOwner() {
    require(msg.sender == owner, 'NO');
    _;
  }

  constructor(address _weth9, address _usdc) {
    owner = msg.sender;
    weth9 = _weth9;
    usdc = _usdc;
    isInvestable[weth9] = true;
    isInvestable[usdc] = true;
    emit SettingCreated();
  }

  function setOwner(address newOwner) external override onlyOwner {
    address oldOwner = owner;
    owner = newOwner;
    emit OwnerChanged(oldOwner, newOwner);
  }

  function setManagerFee(uint256 _managerFee) external override onlyOwner {
    managerFee = _managerFee;
    emit ManagerFeeChanged(_managerFee);
  }

  function setMaxTokens(uint256 _maxTokens) external override onlyOwner {
    require(_maxTokens > 0, 'Invalid max tokens');
    maxTokens = _maxTokens;
    emit MaxTokensChanged(_maxTokens);
  }

  function setMaxSlippage(uint256 _maxSlippage) external override onlyOwner {
    require(_maxSlippage <= 5000, 'Slippage too high'); // Maximum 50% to prevent abuse
    maxSlippage = _maxSlippage;
    emit MaxSlippageChanged(_maxSlippage);
  }

  function setToken(address _token) external override onlyOwner {
    require(isInvestable[_token] == false, 'WLT');
    isInvestable[_token] = true;
    emit AddToken(_token);
  }

  function resetToken(address _token) external override onlyOwner {
    require(_token != weth9 && isInvestable[_token] == true, 'WLT');
    isInvestable[_token] = false;
    emit RemoveToken(_token);
  }
}