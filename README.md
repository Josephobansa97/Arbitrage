# Multi-Chain Price Oracle Smart Contract

A decentralized price oracle system built on Stacks blockchain that aggregates and monitors cryptocurrency prices across multiple chains and DEXes with real-time deviation alerts.

## Overview

The smart contract provides a secure and decentralized way to:
- Aggregate price data from multiple authorized oracles
- Calculate confidence scores based on oracle participation
- Monitor price deviations across different chains and DEXes
- Maintain historical price data with quality metrics

## Technical Architecture

### Core Components

```clarity
;; Oracle Registry
(define-map authorized-oracles
  { oracle: principal }
  {
    active: bool,
    reputation-score: uint,
    last-update: uint,
    total-updates: uint
  })

;; Price Aggregation
(define-map aggregated-prices
  { chain_key: uint, dex_key: uint }
  {
    price: uint,
    last-update: uint,
    confidence-score: uint,
    participating-oracles: uint,
    price-history: (list 10 uint)
  })
```

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `price-staleness-threshold` | 300 blocks | Maximum age for valid price data |
| `min-oracle-count` | 3 | Minimum oracles required for consensus |
| `max-price-deviation` | 500 (5%) | Maximum allowed price deviation |

## Key Functions

### Price Submission
```clarity
(define-public (submit-price 
    (chain-key uint) 
    (dex-key uint) 
    (price uint) 
    (confidence uint)
    (volume-24h uint))
```

### Price Queries
```clarity
(define-read-only (get-price-with-confidence (chain-key uint) (dex-key uint)))
(define-read-only (get-price-history (chain-key uint) (dex-key uint)))
```

## Usage Examples

### Adding an Oracle
```clarity
(contract-call? .price-oracle add-oracle 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Submitting Price Data
```clarity
(contract-call? .price-oracle submit-price u1 u1 u50000000 u95 u1000000)
```

### Querying Price Data
```clarity
;; Get price with confidence metrics
(contract-call? .price-oracle get-price-with-confidence u1 u1)

;; Get historical prices
(contract-call? .price-oracle get-price-history u1 u1)
```

## Error Codes

| Code | Description |
|------|-------------|
| `ERR_UNAUTHORIZED (u100)` | Caller not authorized |
| `ERR_STALE_PRICE (u400)` | Price data too old |
| `ERR_INVALID_PRICE (u401)` | Invalid price submission |
| `ERR_ORACLE_OFFLINE (u402)` | Oracle not available |

## Security Features

- 🔒 Only authorized oracles can submit prices
- 🛡️ Minimum consensus requirements prevent manipulation
- ⚡ Automatic price deviation monitoring
- 📊 Oracle reputation tracking
- ⏰ Price staleness validation

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/multi-chain-price-oracle.git
cd multi-chain-price-oracle
```

2. Install dependencies:
```bash
clarinet install
```

3. Run tests:
```bash
clarinet test
```
t

