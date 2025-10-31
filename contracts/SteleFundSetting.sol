// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import './interfaces/ISteleFundSetting.sol';

contract SteleFundSetting is ISteleFundSetting {
  address public override weth9;
  address public override usdc;

  uint256 public override managerFee = 100; // 100 : 1%
  uint256 public override maxSlippage = 300; // Maximum 3% slippage allowed (300 = 3%)
  
  mapping(address => bool) public override isInvestable;

  constructor(address _weth9, address _usdc, address _wbtc, address _uni, address _link) {
    weth9 = _weth9;
    usdc = _usdc;
    isInvestable[_weth9] = true;
    isInvestable[_usdc] = true;
    isInvestable[_wbtc] = true;
    isInvestable[_uni] = true;
    isInvestable[_link] = true;
    emit AddToken(_weth9);
    emit AddToken(_usdc);
    emit AddToken(_wbtc);
    emit AddToken(_uni);
    emit AddToken(_link);
    emit SettingCreated();
  }
}