// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

// Mint parameters structure to avoid stack too deep
struct MintParams {
  uint256 fundId;
  uint256 fundCreated;
  uint256 investment;
  uint256 currentTVL;
}

interface ISteleFundManagerNFT {
  // Events
  event ManagerNFTMinted(
    uint256 indexed tokenId, 
    uint256 indexed fundId, 
    address indexed manager,
    uint256 investment,
    uint256 currentTVL,
    int256 returnRate,
    uint256 fundCreated
  );

  event TransferAttemptBlocked(uint256 indexed tokenId, address indexed from, address indexed to, string reason);

  // Main functions
  function mintManagerNFT(MintParams calldata params) external returns (uint256);
  
  // View functions
  function getTokenData(uint256 tokenId) external view returns (
    uint256 fundId,
    uint256 fundCreated,
    uint256 nftMintBlock,
    uint256 investment,
    uint256 currentTVL,
    int256 returnRate
  );
}