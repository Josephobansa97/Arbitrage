;; Multi-Chain Price Oracle
;; Aggregates Bitcoin prices from multiple DEXes across different chains

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_STALE_PRICE (err u400))
(define-constant ERR_INVALID_PRICE (err u401))
(define-constant ERR_ORACLE_OFFLINE (err u402))

;; Oracle configuration
(define-data-var price-staleness-threshold uint u300) ;; 5 minutes in blocks
(define-data-var min-oracle-count uint u3) ;; Minimum oracles for consensus
(define-data-var max-price-deviation uint u500) ;; 5% max deviation from median

;; Oracle registry
(define-map authorized-oracles
  { oracle: principal }
  {
    active: bool,
    reputation-score: uint,
    last-update: uint,
    total-updates: uint
  }
)

;; Price feeds from different chains and DEXes
(define-map price-submissions
  { oracle: principal, chain_key: uint, dex_key: uint, round_id: uint }
  {
    price: uint,
    timestamp: uint,
    confidence: uint,
    volume-24h: uint
  }
)

;; Aggregated price data
(define-map aggregated-prices
  { chain_key: uint, dex_key: uint }
  {
    price: uint,
    last-update: uint,
    confidence-score: uint,
    participating-oracles: uint,
    price-history: (list 10 uint)
  }
)

;; Price deviation alerts
(define-map price-alerts
  { alert-id: uint }
  {
    chain_key: uint,
    dex_key: uint,
    deviation-percentage: uint,
    triggered-at: uint,
    resolved: bool
  }
)

(define-data-var current-round-id uint u1)
(define-data-var next-alert-id uint u1)

;; Submit price data (called by authorized oracles)
(define-public (submit-price 
  (chain-key uint) 
  (dex-key uint) 
  (price uint) 
  (confidence uint)
  (volume-24h uint))
  (let (
    (round-id (var-get current-round-id))
    (oracle-data (unwrap! (map-get? authorized-oracles { oracle: tx-sender }) ERR_UNAUTHORIZED))
  )
    (asserts! (get active oracle-data) ERR_UNAUTHORIZED)
    (asserts! (> price u0) ERR_INVALID_PRICE)
    (asserts! (<= confidence u100) ERR_INVALID_PRICE)
    
    ;; Record price submission
    (map-set price-submissions
      { oracle: tx-sender, chain_key: chain-key, dex_key: dex-key, round_id: round-id }
      {
        price: price,
        timestamp: stacks-block-height,
        confidence: confidence,
        volume-24h: volume-24h
      }
    )
    
    ;; Update oracle stats
    (map-set authorized-oracles
      { oracle: tx-sender }
      (merge oracle-data {
        last-update: stacks-block-height,
        total-updates: (+ (get total-updates oracle-data) u1)
      })
    )
    
    ;; Trigger price aggregation
    (try! (aggregate-prices chain-key dex-key round-id))
    
    (ok true)
  )
)

;; Aggregate prices from multiple oracles
(define-private (aggregate-prices (chain-key uint) (dex-key uint) (round-id uint))
  (let (
    (submissions (get-price-submissions-for-round chain-key dex-key round-id))
    (submission-count (len submissions))
  )
    (if (>= submission-count (var-get min-oracle-count))
      (let (
        (median-price (calculate-median-price submissions))
        (confidence-score (calculate-confidence-score submissions))
        (current-price (get-current-price chain-key dex-key))
      )
        ;; Check for significant price deviation
        (if (and (is-some current-price) 
                 (> (calculate-price-deviation median-price (unwrap-panic current-price)) 
                    (var-get max-price-deviation)))
          (begin
            (unwrap! (trigger-price-alert chain-key dex-key median-price (unwrap-panic current-price)) ERR_INVALID_PRICE)
            true
          )
          true
        )
        
        ;; Update aggregated price
        (map-set aggregated-prices
          { chain_key: chain-key, dex_key: dex-key }
          {
            price: median-price,
            last-update: stacks-block-height,
            confidence-score: confidence-score,
            participating-oracles: submission-count,
            price-history: (update-price-history chain-key dex-key median-price)
          }
        )
        (ok true)
      )
      (ok false) ;; Not enough submissions yet
    )
  )
)

;; Calculate median price from submissions
(define-private (calculate-median-price (submissions (list 20 uint)))
  ;; Simplified median calculation - in real implementation would sort the list
  (let (
    (sum (fold + submissions u0))
    (count (len submissions))
  )
    (/ sum count) ;; Using average as approximation for demo
  )
)

;; Calculate confidence score based on oracle consensus
(define-private (calculate-confidence-score (submissions (list 20 uint)))
  (let (
    (count (len submissions))
    (min-count (var-get min-oracle-count))
  )
    (if (>= count (* min-count u2))
      u95 ;; High confidence with many oracles
      (if (>= count min-count)
        u75 ;; Medium confidence with minimum oracles
        u50 ;; Low confidence
      )
    )
  )
)

;; Calculate price deviation percentage
(define-private (calculate-price-deviation (new-price uint) (old-price uint))
  (let (
    (diff (if (> new-price old-price) 
            (- new-price old-price) 
            (- old-price new-price)))
  )
    (/ (* diff u10000) old-price) ;; Return in basis points
  )
)

;; Trigger price deviation alert
(define-private (trigger-price-alert (chain-key uint) (dex-key uint) (new-price uint) (old-price uint))
  (let (
    (alert-id (var-get next-alert-id))
    (deviation (calculate-price-deviation new-price old-price))
  )
    (map-set price-alerts
      { alert-id: alert-id }
      {
        chain_key: chain-key,
        dex_key: dex-key,
        deviation-percentage: deviation,
        triggered-at: stacks-block-height,
        resolved: false
      }
    )
    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)
  )
)

;; Update price history
(define-private (update-price-history (chain-key uint) (dex-key uint) (new-price uint))
  (match (map-get? aggregated-prices { chain_key: chain-key, dex_key: dex-key })
    price-data 
    (let (
      (current-history (get price-history price-data))
      (updated-history (unwrap-panic (as-max-len? (append current-history new-price) u10)))
    )
      ;; Keep only last 10 prices
      (if (> (len updated-history) u10)
        (unwrap-panic (slice? updated-history u1 u10))
        updated-history
      )
    )
    (list new-price) ;; First price entry
  )
)

;; Helper functions
(define-private (get-price-submissions-for-round (chain-key uint) (dex-key uint) (round-id uint))
  ;; Simplified - in real implementation would query all oracle submissions
  (list u50000000 u50100000 u49900000) ;; Mock data
)

(define-private (get-current-price (chain-key uint) (dex-key uint))
  (match (map-get? aggregated-prices { chain_key: chain-key, dex_key: dex-key })
    price-data (some (get price price-data))
    none
  )
)

;; Oracle management functions
(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-oracles
      { oracle: oracle }
      {
        active: true,
        reputation-score: u100,
        last-update: u0,
        total-updates: u0
      }
    )
    (ok true)
  )
)

(define-public (deactivate-oracle (oracle principal))
  (let (
    (oracle-data (unwrap! (map-get? authorized-oracles { oracle: oracle }) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-oracles
      { oracle: oracle }
      (merge oracle-data { active: false })
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-price (chain-key uint) (dex-key uint))
  (match (map-get? aggregated-prices { chain_key: chain-key, dex_key: dex-key })
    price-data 
    (if (< (- stacks-block-height (get last-update price-data)) (var-get price-staleness-threshold))
      (ok (get price price-data))
      ERR_STALE_PRICE
    )
    ERR_ORACLE_OFFLINE
  )
)

(define-read-only (get-price-with-confidence (chain-key uint) (dex-key uint))
  (match (map-get? aggregated-prices { chain_key: chain-key, dex_key: dex-key })
    price-data 
    (ok {
      price: (get price price-data),
      confidence: (get confidence-score price-data),
      last-update: (get last-update price-data),
      participating-oracles: (get participating-oracles price-data)
    })
    ERR_ORACLE_OFFLINE
  )
)

(define-read-only (get-oracle-info (oracle principal))
  (map-get? authorized-oracles { oracle: oracle })
)

(define-read-only (get-price-history (chain-key uint) (dex-key uint))
  (match (map-get? aggregated-prices { chain_key: chain-key, dex_key: dex-key })
    price-data (get price-history price-data)
    (list)
  )
)

(define-read-only (get-active-alerts)
  ;; Simplified - would return list of unresolved alerts
  (list)
)
