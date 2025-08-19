// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Functions for manipulating path data for multihop swaps
library Path {
  uint256 private constant ADDR_SIZE = 20;
  uint256 private constant FEE_SIZE = 3;
  uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
  uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
  uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

  /// @notice Returns true if the path contains two or more pools
  /// @param path The encoded swap path
  /// @return True if path contains two or more pools, otherwise false
  function hasMultiplePools(bytes memory path) internal pure returns (bool) {
    return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
  }

  /// @notice Returns the segment corresponding to the first pool in the path
  /// @param path The encoded swap path
  /// @return The segment containing all data necessary to target the first pool in the path
  function skipToken(bytes memory path) internal pure returns (bytes memory) {
    return slice(path, NEXT_OFFSET, path.length - NEXT_OFFSET);
  }

  /// @notice Decodes the first pool in path
  /// @param path The bytes encoded swap path
  /// @return tokenA The first token of the given pool
  /// @return tokenB The second token of the given pool
  /// @return fee The fee level of the pool
  function decodeFirstPool(bytes memory path)
    internal
    pure
    returns (
      address tokenA,
      address tokenB,
      uint24 fee
    )
  {
    tokenA = toAddress(path, 0);
    fee = toUint24(path, ADDR_SIZE);
    tokenB = toAddress(path, NEXT_OFFSET);
  }

  /// @notice Gets a slice of bytes memory
  /// @param _bytes The bytes to slice
  /// @param _start The start index
  /// @param _length The length of the slice
  /// @return The sliced bytes
  function slice(
    bytes memory _bytes,
    uint256 _start,
    uint256 _length
  ) internal pure returns (bytes memory) {
    require(_length + 31 >= _length, "slice_overflow");
    require(_bytes.length >= _start + _length, "slice_outOfBounds");

    bytes memory tempBytes;

    assembly {
      switch iszero(_length)
      case 0 {
        tempBytes := mload(0x40)
        let lengthmod := and(_length, 31)
        let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
        let end := add(mc, _length)

        for {
          let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
        } lt(mc, end) {
          mc := add(mc, 0x20)
          cc := add(cc, 0x20)
        } {
          mstore(mc, mload(cc))
        }

        mstore(tempBytes, _length)
        mstore(0x40, and(add(mc, 31), not(31)))
      }
      default {
        tempBytes := mload(0x40)
        mstore(tempBytes, 0)
        mstore(0x40, add(tempBytes, 0x20))
      }
    }

    return tempBytes;
  }

  /// @notice Converts bytes to address
  /// @param _bytes The bytes to convert
  /// @param _start The start index
  /// @return The converted address
  function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
    require(_start + 20 >= _start, "toAddress_overflow");
    require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
    address tempAddress;

    assembly {
      tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
    }

    return tempAddress;
  }

  /// @notice Converts bytes to uint24
  /// @param _bytes The bytes to convert
  /// @param _start The start index
  /// @return The converted uint24
  function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
    require(_start + 3 >= _start, "toUint24_overflow");
    require(_bytes.length >= _start + 3, "toUint24_outOfBounds");
    uint24 tempUint;

    assembly {
      tempUint := mload(add(add(_bytes, 0x3), _start))
    }

    return tempUint;
  }
}