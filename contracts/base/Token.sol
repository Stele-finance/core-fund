// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import '../interfaces/IToken.sol';

abstract contract Token {

  function increaseToken(IToken.Token[] storage tokens, address token, uint256 amount) internal {
    bool isNewToken = true;
    for (uint256 i=0; i<tokens.length; i++) {
      if (tokens[i].token == token) {
        isNewToken = false;
        tokens[i].amount += amount;
        break;
      }
    }
    if (isNewToken) {
      tokens.push(IToken.Token(token, amount));
    }
  }

  function decreaseToken(IToken.Token[] storage tokens, address token, uint256 amount) internal returns (bool) {
    for (uint256 i=0; i<tokens.length; i++) {
      if (tokens[i].token == token) {
        require(tokens[i].amount >= amount, 'NET');
        tokens[i].amount -= amount;
        if (tokens[i].amount == 0) {
          uint256 lastIndex = tokens.length-1;
          address lastToken = tokens[lastIndex].token;
          uint256 lastTokenAmount = tokens[lastIndex].amount;
          tokens[i].token = lastToken;
          tokens[i].amount = lastTokenAmount;
          tokens.pop();
        }
        return true;
      }
    }
    return false;
  }
}