// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/ISteleFundSetting.sol';
import './libraries/FullMath.sol';

interface IERC20Decimals {
  function decimals() external view returns (uint8);
  function balanceOf(address account) external view returns (uint256);
}

contract SteleFundSetting is ISteleFundSetting {
  address public override owner;
  address public override weth9;
  address public override usdc;

  uint256 public override managerFee = 10000; // 10000 : 1%, 3000 : 0.3%
  
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