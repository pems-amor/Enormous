# ENORMOUS Options Trading Platform

A decentralized options trading and volatility marketplace built on Stacks blockchain, enabling sophisticated options trading with automated market making.

## Core Features

### Options Trading
- European-style options
- Call and Put options support
- On-chain attribution of writers for revenue distribution
- 10-100 days expiry window
- 24-hour post-expiry exercise window
- Minimum premium: 0.1 STX

### Risk Management
- 5x maximum leverage
- Collateralized option writing
- Real-time collateral debiting on assignment events
- Input validation for strike price and contract size
- Greeks calculation and tracking
  - Delta (-1.0000 to +1.0000)
  - Gamma (high precision)
  - Theta (daily decay)
  - Vega (volatility sensitivity)

### Market Making
- Automated liquidity provision
- LP token system
- Delta-neutral targeting
- Dynamic rebalancing

### Writer Lifecycle
- Premiums from primary sales accrue on-chain to the option writer
- `withdraw-writer-premium` lets writers claim net proceeds without touching collateral
- `reclaim-writer-collateral` unlocks unused collateral after the exercise window elapses
- Exercise settlements automatically debit collateral, record payouts, and flag assignments

### Fee Structure
- Trading fee: 0.25%
- Exercise fee: 0.1%
- Market maker rewards: 50% of fees

### Technical Specifications
- Volatility precision: 4 decimals
- Price precision: 8 decimals
- Black-Scholes pricing model
- Automated Greeks calculations

## Smart Contract Components

### Data Structures
- Option contracts tracking
- User position management
- Market maker pools
- Volatility surface data
- Greeks calculations

### Core Functions
1. `create-option-contract` — collateralizes the writer, stores greeks, and records writer identity.
2. `buy-option` — prices contracts, routes net premium to the writer, and updates volume stats.
3. `exercise-option` — verifies moneyness, settles payouts, and debits writer collateral in real time.
4. `withdraw-writer-premium` — lets writers claim accumulated premiums net of trading fees.
5. `reclaim-writer-collateral` — releases unused collateral once the exercise window closes.
6. `create-mm-pool` / `add-mm-liquidity` — bootstraps and grows automated option-writing pools.

### Risk Controls
- Emergency pause mechanism
- Collateral validation
- Writer-only access control on premium and collateral withdrawals
- Positive quantity guards on core entry points
- Exercise window enforcement
- Minimum premium requirements

## Administrative Features
- Risk-free rate management
- Volatility surface updates
- Fee withdrawal system
- Emergency controls

## Market Making Features
- Automated option writing
- Liquidity pool management
- LP token minting/burning
- Premium distribution

## Monitoring
- Protocol statistics
- Trade volume counters (`total-options-volume`, `total-premiums-traded`)
- Option Greeks tracking
- Volatility surface data
- Market maker pool metrics

---

Note: This contract implements core options trading functionality with automated market making. Production deployment requires proper oracle integration for price feeds, comprehensive testing, and monitoring to ensure writer collateral remains sufficient before permitting withdrawals.
