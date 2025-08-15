# Polymer Futures Exchange

A decentralized futures trading platform built on Stacks blockchain for polymer commodities. This smart contract enables users to open long and short positions on various polymer types with leverage, manage collateral, and settle contracts at expiry.

## Overview

The Polymer Futures Exchange contract facilitates the creation and trading of futures contracts for different polymer types (PET, HDPE, etc.). It supports leveraged trading with proper collateral management, liquidation mechanisms, and oracle-based price feeds.

## Features

- **Leveraged Trading**: Open long/short positions with 2x leverage
- **Multiple Polymer Types**: Support for various polymer commodities
- **Collateral Management**: Automatic collateral handling and margin calculations
- **Liquidation System**: Underwater positions can be liquidated by third parties
- **Oracle Integration**: Real-time price feeds from authorized oracle
- **Position Management**: Easy opening, closing, and monitoring of positions

## Contract Architecture

### Core Components

1. **Futures Contracts**: Time-bound contracts for specific polymer types
2. **User Positions**: Individual trading positions with collateral tracking
3. **Price Oracle**: External price feed mechanism
4. **Liquidation Engine**: Automated liquidation for underwater positions

### Key Parameters

- **Leverage Factor**: 2x (50% margin requirement)
- **Maintenance Margin**: 12.5%
- **Max Position Size**: 1,000,000 units
- **Min Collateral**: 100 units
- **Max Contract Expiry**: ~1 year (52,560 blocks)

## Installation & Setup

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v0.31.1 or higher
- Stacks blockchain development environment
- SIP-010 compatible token for collateral

### Quick Start

1. Clone the repository
```bash
git clone <repository-url>
cd polymer-futures-exchange
```

2. Check contract syntax
```bash
clarinet check
```

3. Run tests
```bash
clarinet test
```

4. Deploy to testnet
```bash
clarinet deploy --testnet
```

## Usage Guide

### 1. Initial Setup (Contract Owner Only)

```clarity
;; Set the price oracle
(contract-call? .polymer-futures set-oracle-principal 'SP1ABC...)

;; Set the collateral token contract
(contract-call? .polymer-futures set-collateral-token 'SP1XYZ...usdc-token)
```

### 2. Create Futures Contracts (Contract Owner)

```clarity
;; Create a PET futures contract expiring in 1000 blocks
(contract-call? .polymer-futures create-futures-contract "PET" u1000)
```

### 3. Update Prices (Oracle Only)

```clarity
;; Update PET price to $1000 per unit
(contract-call? .polymer-futures update-polymer-price "PET" u1000)
```

### 4. Trading Operations

#### Open a Long Position
```clarity
(contract-call? .polymer-futures open-position 
  u1                    ;; contract-id
  "long"               ;; position-type
  u1000                ;; position-size
  .usdc-token)         ;; collateral-token-contract
```

#### Open a Short Position
```clarity
(contract-call? .polymer-futures open-position 
  u1                    ;; contract-id
  "short"              ;; position-type
  u500                 ;; position-size
  .usdc-token)         ;; collateral-token-contract
```

#### Close a Position
```clarity
(contract-call? .polymer-futures close-position 
  u1                    ;; contract-id
  .usdc-token)         ;; collateral-token-contract
```

#### Liquidate an Underwater Position
```clarity
(contract-call? .polymer-futures liquidate-position 
  'SP1USER...          ;; user-to-liquidate
  u1                   ;; contract-id
  .usdc-token)         ;; collateral-token-contract
```

### 5. Query Functions

```clarity
;; Get contract details
(contract-call? .polymer-futures get-contract-details u1)

;; Get user position
(contract-call? .polymer-futures get-user-position 'SP1USER... u1)

;; Get current polymer price
(contract-call? .polymer-futures get-polymer-price "PET")

;; Calculate position PnL
(contract-call? .polymer-futures get-position-pnl 'SP1USER... u1)

;; Get liquidation price
(contract-call? .polymer-futures calculate-liquidation-price 'SP1USER... u1)
```

## Technical Specifications

### Data Structures

#### Futures Contract
```clarity
{
  id: uint,
  polymer-type: (string-ascii 16),
  expiry-block: uint,
  is-active: bool
}
```

#### User Position
```clarity
{
  position-type: (string-ascii 5),  ;; "long" or "short"
  entry-price: uint,
  collateral-amount: uint,
  position-size: uint
}
```

### Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | ERR_UNAUTHORIZED | Caller not authorized |
| u101 | ERR_CONTRACT_NOT_FOUND | Contract ID invalid |
| u102 | ERR_INSUFFICIENT_COLLATERAL | Not enough collateral |
| u103 | ERR_CONTRACT_EXPIRED | Contract past expiry |
| u104 | ERR_INVALID_PRICE | Price validation failed |
| u105 | ERR_POSITION_NOT_FOUND | Position doesn't exist |
| u106 | ERR_CANNOT_LIQUIDATE | Position not underwater |
| u107 | ERR_INVALID_POSITION_TYPE | Invalid position type |
| u108 | ERR_CONTRACT_INACTIVE | Contract deactivated |
| u109 | ERR_TOKEN_TRANSFER_FAILED | Token transfer error |
| u110 | ERR_POSITION_ALREADY_EXISTS | Position already exists |

## Security Features

### Input Validation
- Comprehensive bounds checking for all parameters
- Zero address validation for principals
- String length validation for polymer types
- Price range validation (1 to 1 billion)

### Access Control
- Owner-only functions for contract management
- Oracle-only price updates
- Position ownership verification

### Economic Security
- Maintenance margin requirements
- Liquidation mechanisms
- Collateral management
- Position size limits

## Mathematical Formulas

### Margin Calculation
```
Required Margin = (Position Size × 100) / Leverage Factor
```

### PnL Calculation
```
Long PnL = (Current Price - Entry Price) × Position Size / Entry Price
Short PnL = (Entry Price - Current Price) × Position Size / Entry Price
```

### Liquidation Price
```
Long Liquidation = Entry Price - (Collateral × Entry Price) / Position Size
Short Liquidation = Entry Price + (Collateral × Entry Price) / Position Size
```

## Testing

The contract includes comprehensive test coverage for:
- Position opening and closing
- Liquidation scenarios
- Price updates
- Access control
- Error conditions
- Edge cases

Run tests with:
```bash
clarinet test
```

## Deployment

### Testnet Deployment
```bash
clarinet deploy --testnet
```

### Mainnet Deployment
```bash
clarinet deploy --mainnet
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This smart contract is provided as-is for educational and development purposes. Users should conduct thorough testing and security audits before deploying to mainnet. Trading derivatives involves significant financial risk.

## Support

For questions, issues, or contributions:
- Create an issue on GitHub
- Join our Discord community
- Check the documentation

---

**⚠️ Important**: Always test thoroughly on testnet before mainnet deployment. Futures trading involves significant financial risk.