// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./libraries/NFTSVG.sol";
import "./interfaces/ISteleFundInfo.sol";

// NFT metadata structure for fund manager records
struct FundManagerNFT {
  uint256 fundId;
  uint256 fundCreated;    // Fund creation block number
  uint256 nftMintBlock;        // NFT mint block number
  uint256 investment;          // Investment Amount at NFT mint time
  uint256 currentTVL;          // Current Total Value Locked (TVL)
  int256 returnRate;           // Return rate in basis points (10000 = 100%), can be negative
}

// Mint parameters structure
struct MintParams {
  uint256 fundId;
  uint256 fundCreated;
  uint256 investment;
  uint256 currentTVL;
}

contract SteleFundManagerNFT is ERC721, ERC721Enumerable {
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
    uint256 fundCreated
  );
  event BaseURIUpdated(string newBaseURI);
  event TransferAttemptBlocked(uint256 indexed tokenId, address from, address to, string reason);

  // State variables
  ISteleFundInfo public steleFundInfo;
  address public steleFundContract;
  uint256 private _nextTokenId = 1;
  
  // NFT storage
  mapping(uint256 => FundManagerNFT) public managerNFTs;
  mapping(address => uint256[]) public userManagerNFTs;

  constructor(address _steleFund, address _steleFundInfo) ERC721("Stele Fund Manager NFT", "SFMN") {
    require(_steleFundInfo != address(0), "ZA");
    steleFundInfo = ISteleFundInfo(_steleFundInfo);
    steleFundContract = _steleFund;
  }

  modifier onlySteleFundContract() {
    require(msg.sender == steleFundContract, "NSFC"); // Not Stele Fund Contract
    _;
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



  // Mint Manager NFT (only callable by fund manager)
  function mintManagerNFT(MintParams calldata params) external onlySteleFundContract returns (uint256) {
    address manager = steleFundInfo.manager(params.fundId);
    require(manager != address(0), "ZA");
    require(manager == msg.sender, "OM"); // Only Manager
    require(params.fundCreated > 0, "IP"); // Invalid Period
    
    // Calculate return rate
    int256 returnRate = calculateReturnRate(params.currentTVL, params.investment);
    
    // Get next token ID
    uint256 tokenId = _nextTokenId;
    _nextTokenId++;
        
    // Store NFT metadata
    managerNFTs[tokenId] = FundManagerNFT({
      fundId: params.fundId,
      fundCreated: params.fundCreated,
      nftMintBlock: block.number,
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
      params.fundCreated
    );
    
    return tokenId;
  }

  // Get NFT metadata
  function getFundData(uint256 tokenId) external view returns (
    uint256 fundId,
    uint256 fundCreated,
    uint256 nftMintBlock,
    uint256 investment,
    uint256 currentTVL,
    int256 returnRate
  ) {
    require(_exists(tokenId), "TNE"); // Token Not Exists

    FundManagerNFT memory nft = managerNFTs[tokenId];
    return (
      nft.fundId,
      nft.fundCreated,
      nft.nftMintBlock,
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
    uint256 mintBlock
  ) {
    if (!_exists(tokenId)) {
      return (false, 0, address(0), 0);
    }
    
    FundManagerNFT memory nft = managerNFTs[tokenId];
    return (
      true,
      nft.fundId,
      ownerOf(tokenId),
      nft.nftMintBlock
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
      fundCreated: nft.fundCreated,
      nftMintBlock: nft.nftMintBlock,
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