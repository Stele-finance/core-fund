# SteleFund Core - Claude Code Documentation

## Project Overview
SteleFund Core is a decentralized fund management system with smart contracts that enable governance-controlled fund settings management through voting mechanisms.

## Contract Architecture

### Core Contracts
- **SteleFundSetting.sol**: Fund settings management (whitelist tokens, fees, minimum pool amounts)
- **SteleFund.sol**: Main fund contract (swaps, deposits/withdrawals)
- **SteleFundInfo.sol**: Fund information and investor data management

### Governance Contracts
- **SteleFundGovernor.sol**: OpenZeppelin-based governance contract
- **TimeLock.sol**: Governance execution delay contract

### Utilities
- **Token.sol**: ERC20 token implementation
- **FullMath.sol**: Mathematical operations library
- **Path.sol**: Uniswap path encoding library

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
# 1. Deploy TimeLock
npx hardhat run scripts/mainnet/1_deployTimeLock.js --network mainnet

# 2. Deploy Governor (requires TimeLock address from step 1)
npx hardhat run scripts/mainnet/2_deployGovernor.js --network mainnet

# 3. Deploy SteleFund ecosystem (requires TimeLock address from step 1)
npx hardhat run scripts/mainnet/3_deploySteleFund.js --network mainnet
```

#### Arbitrum Deployment
```bash
# 1. Deploy TimeLock
npx hardhat run scripts/arbitrum/1_arbitrum_deployTimeLock.js --network arbitrum

# 2. Deploy Governor (requires TimeLock address from step 1)
npx hardhat run scripts/arbitrum/2_arbitrum_deployGovernor.js --network arbitrum

# 3. Deploy SteleFund ecosystem (requires TimeLock address from step 1)
npx hardhat run scripts/arbitrum/3_arbitrum_deploySteleFund.js --network arbitrum
```

### Token Addresses
- **Mainnet STELE**: `0x71c24377e7f24b6d822C9dad967eBC77C04667b5`
- **Arbitrum STELE**: `0xF26A6c38E011E428B2DaC5E874BF26fb12665136`
- **Mainnet WETH**: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- **Arbitrum WETH**: `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1`

## Governance System

### Governance Parameters
- **Quorum**: 4% of total token supply
- **Voting Period**: 7 days (50400 blocks)
- **Voting Delay**: 1 block
- **Execution Delay**: 2 days (TimeLock)

### Governance Process
1. **Proposal Creation**: STELE token holders create proposals
2. **Voting**: 7-day voting period
3. **Queuing**: Passed proposals are queued in TimeLock
4. **Execution**: Anyone can execute after 2-day delay

### Governable Functions
The following functions in SteleFundSetting contract are controlled through governance:
- `setMinPoolAmount(uint256)`: Set minimum pool amount
- `setManagerFee(uint256)`: Set manager fee
- `setWhiteListToken(address)`: Add whitelist token
- `resetWhiteListToken(address)`: Remove whitelist token

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
├── SteleFund.sol              # Main fund contract
├── SteleFundInfo.sol          # Fund information management
├── SteleFundSetting.sol       # Fund settings management
├── SteleFundGovernor.sol      # Governance contract
├── TimeLock.sol               # Execution delay contract
├── base/
│   └── Token.sol              # ERC20 token
├── interfaces/
│   ├── ISteleFund.sol
│   ├── ISteleFundInfo.sol
│   └── ISteleFundSetting.sol
└── libraries/
    ├── FullMath.sol
    └── Path.sol

scripts/
├── mainnet/
│   ├── 1_deployTimeLock.js
│   ├── 2_deployGovernor.js
│   └── 3_deploySteleFund.js
└── arbitrum/
    ├── 1_arbitrum_deployTimeLock.js
    ├── 2_arbitrum_deployGovernor.js
    └── 3_arbitrum_deploySteleFund.js
```

## Security Features

### Access Control
- **SteleFundSetting**: TimeLock is owner (governance controlled)
- **SteleFundInfo**: SteleFund contract is owner
- **TimeLock**: Governance contract has proposer/executor roles

### SafeGuards
- 2-day execution delay prevents malicious proposals
- Whitelist tokens can only be added if they have sufficient liquidity
- STELE and WETH are non-removable base tokens

## Integration Notes

### UniswapV3 Integration
- Factory: `0x1F98431c8aD98523631AE4a59f267346ea31F984`
- SwapRouter: `0xE592427A0AEce92De3Edee1F18E0157C05861564`
- Fee tiers: 0.05%, 0.3%, 1%

### Token Standards
- ERC20 compatible
- ERC20Votes (for governance)
- OpenZeppelin standard compliant

## Common Tasks

### Adding a new whitelist token via governance
1. Create proposal calling `setWhiteListToken(tokenAddress)`
2. Vote on proposal for 7 days
3. Queue proposal in TimeLock
4. Execute after 2-day delay

### Changing manager fee via governance
1. Create proposal calling `setManagerFee(newFeeAmount)`
2. Follow standard governance process

### Emergency procedures
- Admin can revoke roles before transferring full control to governance
- TimeLock admin role should be revoked after setup is complete