// SPDX-License-Identifier: GPL-2.0-or-later
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
  address public override steleToken;

  uint256 public override managerFee = 10000; // 10000 : 1%, 3000 : 0.3%
  
  mapping(address => bool) public override whiteListTokens;

  modifier onlyOwner() {
    require(msg.sender == owner, 'NO');
    _;
  }

  constructor(address _stele, address _weth9) {
    owner = msg.sender;
    steleToken = _stele;
    weth9 = _weth9;
    whiteListTokens[steleToken] = true;
    whiteListTokens[weth9] = true;
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

  function setWhiteListToken(address _token) external override onlyOwner {
    require(whiteListTokens[_token] == false, 'WLT');
    whiteListTokens[_token] = true;
    emit WhiteListTokenAdded(_token);
  }

  function resetWhiteListToken(address _token) external override onlyOwner {
    require(whiteListTokens[_token] == true, 'WLT');
    require(_token != weth9 && _token != steleToken, 'WLT2');
    whiteListTokens[_token] = false;
    emit WhiteListTokenRemoved(_token);
  }
}