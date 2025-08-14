// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import './interfaces/ISteleFundSetting.sol';
import './libraries/FullMath.sol';

interface IERC20Decimals {
  function decimals() external view returns (uint8);
  function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV3Factory {
  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function slot0() external view returns (
    uint160 sqrtPriceX96,
    int24 tick,
    uint16 observationIndex,
    uint16 observationCardinality,
    uint16 observationCardinalityNext,
    uint8 feeProtocol,
    bool unlocked
  );
}

contract SteleFundSetting is ISteleFundSetting {
  address public constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address public override owner;
  address public override weth9;
  address public steleToken;

  uint256 public override managerFee = 10000; // 10000 : 1%, 3000 : 0.3%
  uint256 public override minPoolAmount = 1e18; // to be whiteListToken, needed min weth9 value
  
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

  function setMinPoolAmount(uint256 amount) external override onlyOwner {
    minPoolAmount = amount;
    emit MinPoolAmountChanged(amount);
  }

  function setManagerFee(uint256 _managerFee) external override onlyOwner {
    managerFee = _managerFee;
    emit ManagerFeeChanged(_managerFee);
  }

  function checkWhiteListToken(address _token) private view returns (bool) {
    uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];
    uint256 poolAmount = 0;

    for (uint256 i=0; i<fees.length; i++) {
      address pool = IUniswapV3Factory(uniswapV3Factory).getPool(_token, weth9, fees[i]);
      if (pool == address(0)) {
        continue;
      }
      address token0 = IUniswapV3Pool(pool).token0();
      address token1 = IUniswapV3Pool(pool).token1();
      uint256 token0Decimal = 10 ** IERC20Decimals(token0).decimals();
      uint256 token1Decimal = 10 ** IERC20Decimals(token1).decimals();

      uint256 amount0 = IERC20Decimals(token0).balanceOf(pool);
      uint256 amount1 = IERC20Decimals(token1).balanceOf(pool);
      (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

      uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
      uint256 price0 = FullMath.mulDiv(numerator, token0Decimal, 1 << 192);
      
      if (token0 == weth9) {
        poolAmount += ((amount1 / price0) * token1Decimal) + amount0;
      } else if (token1 == weth9) {
        poolAmount += ((amount0 / token0Decimal) * price0) + amount1;
      } else {
        continue;
      }        
    }

    return poolAmount >= minPoolAmount;
  }

  function setWhiteListToken(address _token) external override onlyOwner {
    require(whiteListTokens[_token] == false, 'WLT');
    require(checkWhiteListToken(_token), 'CWLT');
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