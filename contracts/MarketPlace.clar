;; Decentralized Options Trading & Volatility Marketplace
;; A protocol for trading options and volatility on Stacks assets

;; Constants
(define-constant contract-owner tx-sender)
(define-constant min-premium u100000) ;; 0.1 STX minimum premium (100k micro-STX)
(define-constant max-leverage u500) ;; 5x max leverage for margin trading
(define-constant exercise-window u144) ;; ~24 hours window for exercise after expiry
(define-constant min-time-to-expiry u1440) ;; Minimum 10 days to expiry (1440 blocks)
(define-constant max-time-to-expiry u14400) ;; Maximum 100 days to expiry 
(define-constant volatility-precision u10000) ;; 4 decimal places for volatility (100.00%)
(define-constant price-precision u100000000) ;; 8 decimal places for pricing

;; Greeks precision for risk calculations
(define-constant delta-precision u10000) ;; Delta: -1.0000 to +1.0000
(define-constant gamma-precision u100000000) ;; Gamma: higher precision needed
(define-constant theta-precision u1000000) ;; Theta: daily decay rate
(define-constant vega-precision u1000000) ;; Vega: volatility sensitivity

;; Trading and protocol fees
(define-constant trading-fee-rate u25) ;; 0.25% trading fee (25/10000)
(define-constant exercise-fee-rate u10) ;; 0.1% exercise fee (10/10000)
(define-constant mm-reward-rate u5000) ;; 50% of fees to market makers (5000/10000)

;; Error codes
(define-constant err-not-authorized (err u100))
(define-constant err-option-not-found (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-option-expired (err u103))
(define-constant err-option-not-expired (err u104))
(define-constant err-invalid-strike (err u105))
(define-constant err-insufficient-collateral (err u106))
(define-constant err-invalid-expiry (err u107))
(define-constant err-not-exercisable (err u108))
(define-constant err-market-closed (err u109))
(define-constant err-volatility-too-high (err u110))
(define-constant err-position-not-found (err u111))

;; Option types
(define-constant option-type-call u1)
(define-constant option-type-put u2)

;; Option contract definitions
(define-map option-contracts
  { option-id: uint }
  {
    underlying-asset: (string-ascii 12), ;; "STX", "stSTX", "wBTC", etc.
    option-type: uint, ;; 1 = call, 2 = put
    strike-price: uint,
    expiry-block: uint,
    total-contracts: uint,
    premium-collected: uint,
    is-active: bool,
    created-at: uint,
    iv-at-creation: uint, ;; Implied volatility when created
    writer-collateral: uint
  }
)

;; User option positions (long positions - bought options)
(define-map user-long-positions
  { user: principal, option-id: uint }
  {
    contracts-owned: uint,
    premium-paid: uint,
    purchase-block: uint,
    is-exercised: bool,
    average-iv: uint
  }
)

;; User short positions (written options - market maker positions)
(define-map user-short-positions
  { user: principal, option-id: uint }
  {
    contracts-written: uint,
    collateral-locked: uint,
    premium-earned: uint,
    write-block: uint,
    is-assigned: bool
  }
)

;; Market maker pools for automated option writing
(define-map mm-pools
  { pool-id: uint }
  {
    underlying-asset: (string-ascii 12),
    total-liquidity: uint,
    available-liquidity: uint,
    total-lp-tokens: uint,
    accumulated-premiums: uint,
    active-collateral: uint,
    target-delta: int, ;; Target portfolio delta
    risk-free-rate: uint,
    is-active: bool
  }
)

(define-map mm-lp-positions
  { lp: principal, pool-id: uint }
  {
    lp-tokens: uint,
    deposited-amount: uint,
    earned-premiums: uint,
    entry-block: uint,
    last-rebalance: uint
  }
)

;; Volatility surface data
(define-map volatility-surface
  { asset: (string-ascii 12), time-to-expiry: uint, moneyness: uint }
  {
    implied-volatility: uint,
    last-update: uint,
    trade-count: uint,
    confidence-score: uint
  }
)

;; Options chain data for each underlying asset
(define-map options-chain
  { asset: (string-ascii 12), expiry-block: uint }
  {
    available-strikes: (list 20 uint),
    total-call-volume: uint,
    total-put-volume: uint,
    max-pain: uint, ;; Price where most options expire worthless
    put-call-ratio: uint
  }
)

;; Real-time Greeks calculations (simplified)
(define-map option-greeks
  { option-id: uint }
  {
    delta: int,
    gamma: uint,
    theta: int, ;; Negative for time decay
    vega: uint,
    rho: int,
    last-calculation: uint,
    underlying-price: uint
  }
)

;; Exercise and assignment queue
(define-map exercise-queue
  { exercise-id: uint }
  {
    option-id: uint,
    exerciser: principal,
    contracts-exercised: uint,
    exercise-block: uint,
    settlement-amount: uint,
    is-processed: bool
  }
)

;; Volatility trading positions (for direct volatility exposure)
(define-map volatility-positions
  { user: principal, asset: (string-ascii 12) }
  {
    position-size: int, ;; Positive = long vol, negative = short vol
    entry-iv: uint,
    collateral: uint,
    unrealized-pnl: int,
    last-mark-to-market: uint
  }
)

;; Global state variables
(define-data-var next-option-id uint u1)
(define-data-var next-pool-id uint u1)
(define-data-var next-exercise-id uint u1)
(define-data-var total-options-volume uint u0)
(define-data-var total-premiums-traded uint u0)
(define-data-var total-protocol-fees uint u0)
(define-data-var emergency-pause bool false)

;; Risk-free rate (simplified - would come from oracle)
(define-data-var current-risk-free-rate uint u300) ;; 3% annual

;; Helper functions for Black-Scholes calculations (simplified)
(define-private (calculate-option-premium 
                (spot-price uint)
                (strike-price uint) 
                (time-to-expiry uint)
                (volatility uint)
                (risk-free-rate uint)
                (is-call bool))
  ;; Simplified Black-Scholes approximation
  ;; In production, would use more sophisticated math libraries
  (let ((intrinsic-value (if is-call
                           (if (> spot-price strike-price) (- spot-price strike-price) u0)
                           (if (> strike-price spot-price) (- strike-price spot-price) u0)))
        (time-value (/ (* volatility (sqrt time-to-expiry)) u100)))
    (+ intrinsic-value time-value))
)

(define-private (calculate-delta (spot-price uint) (strike-price uint) (time-to-expiry uint) (volatility uint) (is-call bool))
  ;; Simplified delta calculation
  (if is-call
    (if (> spot-price strike-price) (to-int (+ u50 (* u40 (/ (- spot-price strike-price) spot-price)))) 50)
    (if (> strike-price spot-price) (- 50 (to-int (* u40 (/ (- strike-price spot-price) spot-price)))) -50))
)

(define-private (sqrt (n uint))
  ;; Simple square root approximation - in production would use proper math
  (/ (+ n (/ n n)) u2)
)

(define-private (calculate-collateral-requirement (option-type uint) (contracts uint) (strike-price uint) (spot-price uint))
  (if (is-eq option-type option-type-call)
    ;; Call option: need to deliver underlying at strike
    (* contracts spot-price)
    ;; Put option: need to buy underlying at strike  
    (* contracts strike-price))
)

;; Core Options Trading Functions

;; 1. Create new option contract
(define-public (create-option-contract
                (underlying-asset (string-ascii 12))
                (option-type uint)
                (strike-price uint)
                (blocks-to-expiry uint)
                (contracts-to-write uint))
  (let ((option-id (var-get next-option-id))
        (expiry-block (+ stacks-block-height blocks-to-expiry))
        (current-price u50000000)) ;; Would get from oracle in production
    
    (asserts! (not (var-get emergency-pause)) err-not-authorized)
    (asserts! (or (is-eq option-type option-type-call) (is-eq option-type option-type-put)) err-not-authorized)
    (asserts! (>= blocks-to-expiry min-time-to-expiry) err-invalid-expiry)
    (asserts! (<= blocks-to-expiry max-time-to-expiry) err-invalid-expiry)
    
    ;; Calculate required collateral
    (let ((collateral-needed (calculate-collateral-requirement option-type contracts-to-write strike-price current-price)))
      
      ;; Transfer collateral from option writer
      (try! (stx-transfer? collateral-needed tx-sender (as-contract tx-sender)))
      
      ;; Create option contract
      (map-set option-contracts { option-id: option-id }
        {
          underlying-asset: underlying-asset,
          option-type: option-type,
          strike-price: strike-price,
          expiry-block: expiry-block,
          total-contracts: contracts-to-write,
          premium-collected: u0,
          is-active: true,
          created-at: stacks-block-height,
          iv-at-creation: u2500, ;; 25% IV assumption
          writer-collateral: collateral-needed
        })
      
      ;; Create writer's short position
      (map-set user-short-positions { user: tx-sender, option-id: option-id }
        {
          contracts-written: contracts-to-write,
          collateral-locked: collateral-needed,
          premium-earned: u0,
          write-block: stacks-block-height,
          is-assigned: false
        })
      
      ;; Calculate and store Greeks
      (let ((delta (calculate-delta current-price strike-price blocks-to-expiry u2500 (is-eq option-type option-type-call))))
        (map-set option-greeks { option-id: option-id }
          {
            delta: delta,
            gamma: u1000, ;; Simplified
            theta: -10, ;; Simplified daily decay
            vega: u500, ;; Simplified
            rho: 100, ;; Simplified
            last-calculation: stacks-block-height,
            underlying-price: current-price
          }))
      
      (var-set next-option-id (+ option-id u1))
      
      (print {
        event: "option-created",
        option-id: option-id,
        writer: tx-sender,
        underlying: underlying-asset,
        option-type: option-type,
        strike: strike-price,
        expiry: expiry-block,
        contracts: contracts-to-write
      })
      
      (ok option-id)
    )
  )
)

;; 2. Buy option contract
(define-public (buy-option (option-id uint) (contracts uint))
  (let ((option (unwrap! (map-get? option-contracts { option-id: option-id }) err-option-not-found))
        (current-price u50000000)) ;; Would get from oracle
    
    (asserts! (get is-active option) err-market-closed)
    (asserts! (< stacks-block-height (get expiry-block option)) err-option-expired)
    (asserts! (<= contracts (get total-contracts option)) err-insufficient-balance)
    
    ;; Calculate premium using Black-Scholes
    (let ((time-to-expiry (- (get expiry-block option) stacks-block-height))
          (premium-per-contract (calculate-option-premium 
                                  current-price
                                  (get strike-price option)
                                  time-to-expiry
                                  u2500 ;; 25% volatility assumption
                                  (var-get current-risk-free-rate)
                                  (is-eq (get option-type option) option-type-call)))
          (total-premium (* premium-per-contract contracts))
          (trading-fee (/ (* total-premium trading-fee-rate) u10000)))
      
      ;; Transfer premium + fee from buyer
      (try! (stx-transfer? (+ total-premium trading-fee) tx-sender (as-contract tx-sender)))
      
      ;; Create or update buyer's long position
      (let ((existing-position (map-get? user-long-positions { user: tx-sender, option-id: option-id })))
        (match existing-position
          position
            (map-set user-long-positions { user: tx-sender, option-id: option-id }
              (merge position {
                contracts-owned: (+ (get contracts-owned position) contracts),
                premium-paid: (+ (get premium-paid position) total-premium)
              }))
          (map-set user-long-positions { user: tx-sender, option-id: option-id }
            {
              contracts-owned: contracts,
              premium-paid: total-premium,
              purchase-block: stacks-block-height,
              is-exercised: false,
              average-iv: u2500
            })))
      
      ;; Update option contract
      (map-set option-contracts { option-id: option-id }
        (merge option {
          total-contracts: (- (get total-contracts option) contracts),
          premium-collected: (+ (get premium-collected option) total-premium)
        }))
      
      ;; Update protocol fees
      (var-set total-protocol-fees (+ (var-get total-protocol-fees) trading-fee))
      (var-set total-premiums-traded (+ (var-get total-premiums-traded) total-premium))
      
      (print {
        event: "option-purchased",
        buyer: tx-sender,
        option-id: option-id,
        contracts: contracts,
        premium-paid: total-premium,
        current-price: current-price
      })
      
      (ok total-premium)
    )
  )
)

;; 3. Exercise option contract
(define-public (exercise-option (option-id uint) (contracts uint))
  (let ((option (unwrap! (map-get? option-contracts { option-id: option-id }) err-option-not-found))
        (long-position (unwrap! (map-get? user-long-positions { user: tx-sender, option-id: option-id }) err-position-not-found))
        (current-price u55000000)) ;; Would get from oracle
    
    (asserts! (>= stacks-block-height (get expiry-block option)) err-option-not-expired)
    (asserts! (<= stacks-block-height (+ (get expiry-block option) exercise-window)) err-option-expired)
    (asserts! (>= (get contracts-owned long-position) contracts) err-insufficient-balance)
    
    ;; Check if option is in-the-money
    (let ((is-call (is-eq (get option-type option) option-type-call))
          (is-itm (if is-call
                    (> current-price (get strike-price option))
                    (< current-price (get strike-price option)))))
      
      (asserts! is-itm err-not-exercisable)
      
      ;; Calculate settlement amount
      (let ((settlement-per-contract (if is-call
                                       (- current-price (get strike-price option))
                                       (- (get strike-price option) current-price)))
            (total-settlement (* settlement-per-contract contracts))
            (exercise-fee (/ (* total-settlement exercise-fee-rate) u10000))
            (net-settlement (- total-settlement exercise-fee))
            (exercise-id (var-get next-exercise-id)))
        
        ;; Transfer settlement to option holder
        (try! (as-contract (stx-transfer? net-settlement tx-sender tx-sender)))
        
        ;; Update long position
        (map-set user-long-positions { user: tx-sender, option-id: option-id }
          (merge long-position {
            contracts-owned: (- (get contracts-owned long-position) contracts),
            is-exercised: true
          }))
        
        ;; Create exercise record
        (map-set exercise-queue { exercise-id: exercise-id }
          {
            option-id: option-id,
            exerciser: tx-sender,
            contracts-exercised: contracts,
            exercise-block: stacks-block-height,
            settlement-amount: net-settlement,
            is-processed: true
          })
        
        (var-set next-exercise-id (+ exercise-id u1))
        (var-set total-protocol-fees (+ (var-get total-protocol-fees) exercise-fee))
        
        (print {
          event: "option-exercised",
          exerciser: tx-sender,
          option-id: option-id,
          contracts: contracts,
          settlement: net-settlement,
          current-price: current-price
        })
        
        (ok net-settlement)
      )
    )
  )
)

;; 4. Create market maker pool for automated option writing
(define-public (create-mm-pool (underlying-asset (string-ascii 12)) (initial-liquidity uint))
  (let ((pool-id (var-get next-pool-id)))
    
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    
    ;; Transfer initial liquidity
    (try! (stx-transfer? initial-liquidity tx-sender (as-contract tx-sender)))
    
    ;; Create MM pool
    (map-set mm-pools { pool-id: pool-id }
      {
        underlying-asset: underlying-asset,
        total-liquidity: initial-liquidity,
        available-liquidity: initial-liquidity,
        total-lp-tokens: initial-liquidity, ;; 1:1 initial ratio
        accumulated-premiums: u0,
        active-collateral: u0,
        target-delta: 0, ;; Delta neutral
        risk-free-rate: (var-get current-risk-free-rate),
        is-active: true
      })
    
    (var-set next-pool-id (+ pool-id u1))
    
    (print {
      event: "mm-pool-created",
      pool-id: pool-id,
      underlying: underlying-asset,
      initial-liquidity: initial-liquidity
    })
    
    (ok pool-id)
  )
)

;; 5. Add liquidity to market maker pool
(define-public (add-mm-liquidity (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? mm-pools { pool-id: pool-id }) err-not-authorized)))
    
    (asserts! (get is-active pool) err-market-closed)
    
    ;; Calculate LP tokens to mint
    (let ((lp-tokens-to-mint (if (is-eq (get total-lp-tokens pool) u0)
                               amount
                               (/ (* amount (get total-lp-tokens pool)) (get total-liquidity pool)))))
      
      ;; Transfer liquidity from LP
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update or create LP position
      (let ((existing-lp (map-get? mm-lp-positions { lp: tx-sender, pool-id: pool-id })))
        (match existing-lp
          position
            (map-set mm-lp-positions { lp: tx-sender, pool-id: pool-id }
              (merge position {
                lp-tokens: (+ (get lp-tokens position) lp-tokens-to-mint),
                deposited-amount: (+ (get deposited-amount position) amount)
              }))
          (map-set mm-lp-positions { lp: tx-sender, pool-id: pool-id }
            {
              lp-tokens: lp-tokens-to-mint,
              deposited-amount: amount,
              earned-premiums: u0,
              entry-block: stacks-block-height,
              last-rebalance: stacks-block-height
            })))
      
      ;; Update pool state
      (map-set mm-pools { pool-id: pool-id }
        (merge pool {
          total-liquidity: (+ (get total-liquidity pool) amount),
          available-liquidity: (+ (get available-liquidity pool) amount),
          total-lp-tokens: (+ (get total-lp-tokens pool) lp-tokens-to-mint)
        }))
      
      (print {
        event: "mm-liquidity-added",
        lp: tx-sender,
        pool-id: pool-id,
        amount: amount,
        lp-tokens: lp-tokens-to-mint
      })
      
      (ok lp-tokens-to-mint)
    )
  )
)

;; Read-only functions

(define-read-only (get-option-contract (option-id uint))
  (map-get? option-contracts { option-id: option-id })
)

(define-read-only (get-user-long-position (user principal) (option-id uint))
  (map-get? user-long-positions { user: user, option-id: option-id })
)

(define-read-only (get-user-short-position (user principal) (option-id uint))
  (map-get? user-short-positions { user: user, option-id: option-id })
)

(define-read-only (get-option-greeks (option-id uint))
  (map-get? option-greeks { option-id: option-id })
)

(define-read-only (get-mm-pool (pool-id uint))
  (map-get? mm-pools { pool-id: pool-id })
)

(define-read-only (calculate-option-value (option-id uint) (current-spot-price uint))
  (match (map-get? option-contracts { option-id: option-id })
    option
      (let ((time-to-expiry (if (> (get expiry-block option) stacks-block-height)
                             (- (get expiry-block option) stacks-block-height)
                             u0)))
        (some (calculate-option-premium 
                current-spot-price
                (get strike-price option)
                time-to-expiry
                u2500 ;; Default IV
                (var-get current-risk-free-rate)
                (is-eq (get option-type option) option-type-call))))
    none)
)

(define-read-only (get-protocol-stats)
  {
    total-options-created: (- (var-get next-option-id) u1),
    total-volume: (var-get total-options-volume),
    total-premiums: (var-get total-premiums-traded),
    total-fees: (var-get total-protocol-fees),
    total-mm-pools: (- (var-get next-pool-id) u1),
    current-risk-free-rate: (var-get current-risk-free-rate)
  }
)

(define-read-only (get-volatility-surface (asset (string-ascii 12)) (time-to-expiry uint) (moneyness uint))
  (map-get? volatility-surface { asset: asset, time-to-expiry: time-to-expiry, moneyness: moneyness })
)

;; Admin functions

(define-public (update-risk-free-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (var-set current-risk-free-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-volatility-surface (asset (string-ascii 12)) (time-to-expiry uint) (moneyness uint) (iv uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (map-set volatility-surface { asset: asset, time-to-expiry: time-to-expiry, moneyness: moneyness }
      {
        implied-volatility: iv,
        last-update: stacks-block-height,
        trade-count: u1,
        confidence-score: u100
      })
    (ok iv)
  )
)

(define-public (withdraw-protocol-fees)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (let ((fees (var-get total-protocol-fees)))
      (var-set total-protocol-fees u0)
      (try! (as-contract (stx-transfer? fees tx-sender contract-owner)))
      (ok fees)
    )
  )
)

(define-public (emergency-pause-toggle)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (var-set emergency-pause (not (var-get emergency-pause)))
    (ok (var-get emergency-pause))
  )
)