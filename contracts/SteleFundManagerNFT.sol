// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./libraries/NFTSVG.sol";
import "./interfaces/ISteleFundInfo.sol";

// NFT metadata structure for fund manager records
struct FundManagerNFT {
  uint256 fundId;
  uint256 fundCreatedTime;     // Fund creation timestamp
  uint256 nftMintTime;         // NFT mint timestamp
  uint256 investment;          // Investment Amount at NFT mint time
  uint256 currentTVL;          // Current Total Value Locked (TVL)
  int256 returnRate;           // Return rate in basis points (10000 = 100%), can be negative
}

// Mint parameters structure
struct MintParams {
  uint256 fundId;
  uint256 fundCreatedBlock;
  uint256 investment;
  uint256 currentTVL;
}

contract SteleFundManagerNFT is ERC721, ERC721Enumerable, Ownable {
  using Strings for uint256;
  using NFTSVG for NFTSVG.SVGParams;

  // Events
  event ManagerNFTMinted(
    uint256 indexed tokenId, 
    uint256 indexed fundId, 
    address indexed manager,
    uint256 investment,
    uint256 currentTVL,
    int256 returnRate,
    uint256 fundCreatedBlock
  );
  event BaseURIUpdated(string newBaseURI);
  event TransferAttemptBlocked(uint256 indexed tokenId, address from, address to, string reason);

  // State variables
  ISteleFundInfo public fundInfo;
  uint256 private _nextTokenId = 1;
  
  // NFT storage
  mapping(uint256 => FundManagerNFT) public managerNFTs;
  mapping(address => uint256[]) public userManagerNFTs;
  
  constructor(address _fundInfo) ERC721("Stele Fund Manager NFT", "SFMN") {
    require(_fundInfo != address(0), "ZA");
    fundInfo = ISteleFundInfo(_fundInfo);
  }

  // Calculate return rate (can be negative)
  function calculateReturnRate(uint256 finalValue, uint256 initialValue) internal pure returns (int256) {
    if (initialValue == 0) return 0;
    
    if (finalValue >= initialValue) {
      uint256 profit = finalValue - initialValue;
      return int256((profit * 10000) / initialValue);
    } else {
      uint256 loss = initialValue - finalValue;
      return -int256((loss * 10000) / initialValue);
    }
  }

  // Convert block number to approximate timestamp
  function blockToTimestamp(uint256 blockNumber) internal pure returns (uint256) {
    // Ethereum mainnet genesis block: 0 (July 30, 2015)
    // Average block time: ~12 seconds
    // Genesis timestamp: 1438269973 (July 30, 2015 15:26:13 UTC)
    
    uint256 genesisTimestamp = 1438269973; // July 30, 2015
    uint256 averageBlockTime = 12; // seconds
    
    // Calculate approximate timestamp
    return genesisTimestamp + (blockNumber * averageBlockTime);
  }

  // Convert block number to approximate date string (YYYY-MM-DD format)
  function blockToDateString(uint256 blockNumber) internal pure returns (string memory) {
    uint256 estimatedTimestamp = blockToTimestamp(blockNumber);
    return timestampToDateString(estimatedTimestamp);
  }

  // Convert timestamp to date string (YYYY-MM-DD)
  function timestampToDateString(uint256 timestamp) internal pure returns (string memory) {
    // Days since Unix epoch (January 1, 1970)
    uint256 daysSinceEpoch = timestamp / 86400; // 86400 seconds in a day
    
    // Calculate year (approximate)
    uint256 year = 1970 + (daysSinceEpoch / 365);
    
    // Adjust for leap years (rough approximation)
    uint256 leapYearAdjustment = (year - 1970) / 4;
    uint256 adjustedDays = daysSinceEpoch - leapYearAdjustment;
    year = 1970 + (adjustedDays / 365);
    
    // Calculate remaining days in the year
    uint256 yearStartDays = (year - 1970) * 365 + ((year - 1970) / 4);
    uint256 dayOfYear = daysSinceEpoch - yearStartDays;
    
    // Simple month calculation (approximate)
    uint256 month;
    uint256 day;
    
    if (dayOfYear <= 31) {
      month = 1; day = dayOfYear;
    } else if (dayOfYear <= 59) {
      month = 2; day = dayOfYear - 31;
    } else if (dayOfYear <= 90) {
      month = 3; day = dayOfYear - 59;
    } else if (dayOfYear <= 120) {
      month = 4; day = dayOfYear - 90;
    } else if (dayOfYear <= 151) {
      month = 5; day = dayOfYear - 120;
    } else if (dayOfYear <= 181) {
      month = 6; day = dayOfYear - 151;
    } else if (dayOfYear <= 212) {
      month = 7; day = dayOfYear - 181;
    } else if (dayOfYear <= 243) {
      month = 8; day = dayOfYear - 212;
    } else if (dayOfYear <= 273) {
      month = 9; day = dayOfYear - 243;
    } else if (dayOfYear <= 304) {
      month = 10; day = dayOfYear - 273;
    } else if (dayOfYear <= 334) {
      month = 11; day = dayOfYear - 304;
    } else {
      month = 12; day = dayOfYear - 334;
    }
    
    // Handle edge cases
    if (day == 0) day = 1;
    if (day > 31) day = 31;
    
    return string(abi.encodePacked(
      Strings.toString(year),
      "-",
      month < 10 ? "0" : "", Strings.toString(month),
      "-",
      day < 10 ? "0" : "", Strings.toString(day)
    ));
  }

  // Mint Manager NFT (only callable by fund manager)
  function mintManagerNFT(MintParams calldata params) external returns (uint256) {
    address manager = fundInfo.manager(params.fundId);
    require(manager != address(0), "ZA");
    require(manager == msg.sender, "OM"); // Only Manager
    require(params.fundCreatedBlock > 0, "IP"); // Invalid Period
    
    // Calculate return rate
    int256 returnRate = calculateReturnRate(params.currentTVL, params.investment);
    
    // Get next token ID
    uint256 tokenId = _nextTokenId;
    _nextTokenId++;
        
    // Store NFT metadata
    managerNFTs[tokenId] = FundManagerNFT({
      fundId: params.fundId,
      fundCreatedTime: blockToTimestamp(params.fundCreatedBlock),
      nftMintTime: block.timestamp,
      investment: params.investment,
      currentTVL: params.currentTVL,
      returnRate: returnRate
    });
    
    // Mint NFT to manager
    _mint(manager, tokenId);
    
    // Track manager's NFTs
    userManagerNFTs[manager].push(tokenId);
    
    emit ManagerNFTMinted(
      tokenId, 
      params.fundId, 
      manager,
      params.investment,
      params.currentTVL,
      returnRate,
      blockToTimestamp(params.fundCreatedBlock)
    );
    
    return tokenId;
  }

  // Get NFT metadata
  function getFundData(uint256 tokenId) external view returns (
    uint256 fundId,
    uint256 fundCreatedTime,
    uint256 nftMintTime,
    uint256 investment,
    uint256 currentTVL,
    int256 returnRate
  ) {
    require(_exists(tokenId), "TNE"); // Token Not Exists

    FundManagerNFT memory nft = managerNFTs[tokenId];
    return (
      nft.fundId,
      nft.fundCreatedTime,
      nft.nftMintTime,
      nft.investment,
      nft.currentTVL,
      nft.returnRate
    );
  }

  // Get all NFTs for a manager
  function getManagerNFTs(address manager) external view returns (uint256[] memory) {
    return userManagerNFTs[manager];
  }

  // ============ SOULBOUND NFT FUNCTIONS ============
  
  // Transfer functions are blocked for soulbound functionality
  function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
    emit TransferAttemptBlocked(tokenId, from, to, "Soulbound NFT cannot be transferred");
    revert("SBT"); // Soulbound Token
  }
  
  function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
    emit TransferAttemptBlocked(tokenId, from, to, "Soulbound NFT cannot be transferred");
    revert("SBT");
  }
  
  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory /* data */) public override(ERC721, IERC721) {
    emit TransferAttemptBlocked(tokenId, from, to, "Soulbound NFT cannot be transferred");
    revert("SBT");
  }
  
  // Approval functions are blocked since transfers are not allowed
  function approve(address /* to */, uint256 /* tokenId */) public pure override(ERC721, IERC721) {
    revert("SBT");
  }
  
  function setApprovalForAll(address /* operator */, bool /* approved */) public pure override(ERC721, IERC721) {
    revert("SBT");
  }
  
  function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
    require(_exists(tokenId), "TNE");
    return address(0); // Always return zero address for soulbound tokens
  }
  
  function isApprovedForAll(address /* owner */, address /* operator */) public pure override(ERC721, IERC721) returns (bool) {
    return false; // Always return false for soulbound tokens
  }
  
  // Check if this is a soulbound token
  function isSoulbound() external pure returns (bool) {
    return true;
  }
  
  // Get soulbound token information
  function getSoulboundInfo(uint256 tokenId) external view returns (
    bool isSoulboundToken,
    address boundTo,
    string memory reason
  ) {
    require(_exists(tokenId), "TNE");
    return (true, ownerOf(tokenId), "Fund Manager NFT bound to fund manager");
  }

  // Verify if NFT was minted by this contract
  function verifyNFTAuthenticity(uint256 tokenId) external view returns (
    bool isAuthentic,
    uint256 fundId,
    address originalManager,
    uint256 mintTime
  ) {
    if (!_exists(tokenId)) {
      return (false, 0, address(0), 0);
    }
    
    FundManagerNFT memory nft = managerNFTs[tokenId];
    return (
      true,
      nft.fundId,
      ownerOf(tokenId),
      nft.nftMintTime
    );
  }

  // Format return rate for display
  function formatReturnRate(int256 returnRate) internal pure returns (string memory) {
    uint256 absRate = returnRate >= 0 ? uint256(returnRate) : uint256(-returnRate);
    uint256 wholePart = absRate / 100;
    uint256 decimalPart = absRate % 100;
    
    string memory sign = returnRate >= 0 ? "+" : "-";
    string memory decimal = decimalPart < 10 
      ? string(abi.encodePacked("0", Strings.toString(decimalPart)))
      : Strings.toString(decimalPart);
      
    return string(abi.encodePacked(
      sign,
      Strings.toString(wholePart),
      ".",
      decimal,
      "%"
    ));
  }


  // Token URI with on-chain SVG image
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "TNE");

    FundManagerNFT memory nft = managerNFTs[tokenId];

    // Generate SVG image
    NFTSVG.SVGParams memory svgParams = NFTSVG.SVGParams({
      fundId: nft.fundId,
      manager: ownerOf(tokenId),
      fundCreatedTime: nft.fundCreatedTime,
      nftMintTime: nft.nftMintTime,
      investment: nft.investment,
      currentValue: nft.currentTVL,
      returnRate: nft.returnRate
    });
    
    string memory svg = svgParams.generateSVG();
    
    string memory image = string(abi.encodePacked(
      "data:image/svg+xml;base64,",
      Base64.encode(bytes(svg))
    ));
    
    string memory returnRateText = formatReturnRate(nft.returnRate);
    
    string memory json = string(abi.encodePacked(
      '{"name":"Fund #',
      Strings.toString(nft.fundId),
      ' Manager Certificate",',
      '"description":"On-chain certificate for Fund #',
      Strings.toString(nft.fundId),
      ' with ',
      returnRateText,
      ' return rate",',
      '"image":"',
      image,
      '",',
      '"attributes":[',
      '{"trait_type":"Fund ID","value":',
      Strings.toString(nft.fundId),
      '},',
      '{"trait_type":"Return Rate","value":"',
      returnRateText,
      '"},',
      '{"trait_type":"Fund TVL","value":"',
      Strings.toString(nft.currentTVL / 1e18),
      '"}]}'
    ));

    return string(abi.encodePacked(
      "data:application/json;base64,",
      Base64.encode(bytes(json))
    ));
  }

  // Override required functions
  function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
    internal
    override(ERC721, ERC721Enumerable)
  {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  // Helper function to check if token exists
  function _exists(uint256 tokenId) internal view virtual override returns (bool) {
    return _ownerOf(tokenId) != address(0);
  }
}