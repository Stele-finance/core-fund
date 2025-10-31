# SteleFund Core

## Project Overview
SteleFund Core is a decentralized fund management system with smart contracts that enable on-chain fund creation, investment, and trading through Uniswap V3.

## Contract Architecture

### Core Contracts
- **SteleFundSetting.sol**: Fund settings management (investable tokens, fees, slippage settings)
- **SteleFund.sol**: Main fund contract (swaps, deposits/withdrawals)
- **SteleFundInfo.sol**: Fund information and investor data management
- **SteleFundManagerNFT.sol**: Manager NFT for fund performance records (soulbound)

### Utilities
- **Token.sol**: ERC20 token base contract
- **PriceOracle.sol**: Uniswap V3 price oracle library
- **Path.sol**: Uniswap path encoding library
- **BytesLib.sol**: Bytes manipulation utilities
- **NFTSVG.sol**: On-chain SVG generation for Manager NFTs

## Deployment Process

### Prerequisites
```bash
npm install
npx hardhat compile
```

### Network Configuration
The project supports the following networks:
- Mainnet
- Arbitrum

### Deployment Scripts

#### Mainnet Deployment
```bash
# 1. Deploy SteleFund ecosystem
npx hardhat run scripts/mainnet/3_deploySteleFund.js --network mainnet

# 2. Deploy SteleFundManagerNFT
npx hardhat run scripts/mainnet/4_deploySteleFundManagerNFT.js --network mainnet
```

#### Arbitrum Deployment
```bash
# 1. Deploy SteleFund ecosystem
npx hardhat run scripts/arbitrum/3_arbitrum_deploySteleFund.js --network arbitrum

# 2. Deploy SteleFundManagerNFT
npx hardhat run scripts/arbitrum/4_arbitrum_deploySteleFundManagerNFT.js --network arbitrum
```

### Token Addresses
- **Mainnet WETH**: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- **Mainnet USDC**: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- **Arbitrum WETH**: `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1`
- **Arbitrum USDC**: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`

## Fund Settings

### Default Settings
- **Manager Fee**: 1% (100 basis points)
- **Max Slippage**: 3% (300 basis points)
- **Investable Tokens**: WETH, USDC (immutable after deployment)

### Constraints
- **Minimum Deposit**: $10 USD equivalent
- **Maximum Swaps per TX**: 10
- **Maximum Funds per Investor**: 100
- **Maximum Fund ID**: 1,000,000,000

## Development Commands

### Testing
```bash
npx hardhat test
```

### Compilation
```bash
npx hardhat compile
```

### Local Development
```bash
npx hardhat node
```

## Project Structure
```
contracts/
├── SteleFund.sol                    # Main fund contract
├── SteleFundInfo.sol                # Fund information management
├── SteleFundSetting.sol             # Fund settings management
├── SteleFundManagerNFT.sol          # Manager NFT contract
├── base/
│   └── Token.sol                    # ERC20 token base
├── interfaces/
│   ├── ISteleFund.sol
│   ├── ISteleFundInfo.sol
│   ├── ISteleFundSetting.sol
│   ├── ISteleFundManagerNFT.sol
│   └── IToken.sol
└── libraries/
    ├── PriceOracle.sol              # Uniswap V3 price oracle
    ├── Path.sol                     # Path encoding
    ├── BytesLib.sol                 # Bytes manipulation
    └── NFTSVG.sol                   # SVG generation

scripts/
├── mainnet/
│   ├── 3_deploySteleFund.js
│   ├── 4_deploySteleFundManagerNFT.js
│   └── 5_deploySteleFundManagerNFTonly.js
└── arbitrum/
    ├── 3_arbitrum_deploySteleFund.js
    ├── 4_arbitrum_deploySteleFundManagerNFT.js
    └── 5_arbitrum_deploySteleFundManagerNFTonly.js
```

## Security Features

### Access Control
- **SteleFundSetting**: Immutable settings (no owner)
- **SteleFundInfo**: SteleFund contract is owner
- **SteleFund**: Owner can set Manager NFT contract
- **Manager Verification**: Only fund managers can execute swaps and withdraw fees

### SafeGuards
- Reentrancy protection on all state-changing functions
- Minimum deposit: $10 USD equivalent
- Maximum swaps per transaction: 10
- Maximum funds per investor: 100
- Slippage protection using Uniswap V3 spot prices
- Manager NFTs are soulbound (non-transferable)
- CEI (Checks-Effects-Interactions) pattern

## Integration Notes

### UniswapV3 Integration
- **Factory**: `0x1F98431c8aD98523631AE4a59f267346ea31F984`
- **SwapRouter**: `0xE592427A0AEce92De3Edee1F18E0157C05861564`
- **Fee Tiers**: 0.05% (500), 0.3% (3000), 1% (10000)

### Token Standards
- ERC20 compatible
- ERC721 for Manager NFTs
- OpenZeppelin standard compliant

## How It Works

### Creating a Fund
1. Call `SteleFundInfo.create()` to create a new fund
2. Fund creator becomes the manager
3. Manager can swap tokens and withdraw fees

### Joining a Fund
1. Call `SteleFundInfo.join(fundId)` to join an existing fund
2. Deposit ETH via fallback function with fundId in calldata
3. Receive proportional shares based on deposit value

### Manager Operations
- **Swap Tokens**: Manager calls `swap()` with trade parameters
- **Withdraw Fees**: Manager calls `withdrawFee()` to claim accumulated fees
- **Mint NFT**: Manager calls `mintManagerNFT()` to mint performance certificate

### Investor Operations
- **Deposit**: Send ETH to contract with fundId (32 bytes) in calldata
- **Withdraw**: Call `withdraw(fundId, percentage)` to withdraw portion of holdings
- **View Portfolio**: Query fund tokens and shares via SteleFundInfo

## Architecture Decisions

### Why No Governance?
- **Simplicity**: Reduces attack surface and complexity
- **Immutability**: Settings are predictable and cannot be changed
- **Gas Efficiency**: No governance overhead
- **Trust**: No centralized control point

### Price Oracle Strategy
- Uses Uniswap V3 spot prices for slippage protection
- Multi-fee-tier selection for best liquidity
- Direct pool queries for minimal gas cost

### Share Calculation
- First deposit: shares = USD value
- Subsequent deposits: proportional to portfolio value
- High precision math using mulDiv to prevent rounding attacks
