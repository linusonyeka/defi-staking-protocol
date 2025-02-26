;; DeFi Staking Protocol
;; Implements liquidity pooling and yield farming with optimized minimum calculation

;; Define fungible token trait
(define-trait ft-trait
    (
        (transfer (uint principal principal) (response bool uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-decimals () (response uint uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
    )
)

;; Define token contracts
(define-constant base-token-principal .token-a)
(define-constant quote-token-principal .token-b)

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-FUNDS (err u2))
(define-constant ERR-EXISTING-POSITION (err u3))
(define-constant ERR-NO-POSITION (err u4))
(define-constant ERR-BELOW-THRESHOLD (err u5))
(define-constant ERR-TIME-LOCK (err u6))
(define-constant ERR-TOKEN-MISMATCH (err u7))
(define-constant ERR-MATH-FAILURE (err u8))
(define-constant ERR-INVALID-ADMIN (err u9))
(define-constant ERR-ADMIN-VALIDATION (err u10))

;; Constants
(define-constant MIN_DEPOSIT_AMOUNT u100000) ;; Minimum deposit requirement
(define-constant STAKING_PERIOD u144) ;; ~24 hours in blocks
(define-constant BASE_YIELD_RATE u100) ;; 1.00x base yield rate
(define-constant SWAP_FEE_RATE u30) ;; 0.3% fee
(define-constant NULL_ADDRESS 'SP000000000000000000002Q6VF78)

;; Protocol state variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var total-liquidity-shares uint u0)
(define-data-var last-state-update uint u0)
(define-data-var protocol-active bool true)
(define-data-var yield-rate uint BASE_YIELD_RATE)

;; Staker data registry
(define-map staker-positions
    principal
    {
        base-token-amount: uint,
        quote-token-amount: uint,
        liquidity-shares: uint,
        deposit-block: uint,
        last-harvest: uint,
        unlock-block: uint
    }
)

;; Liquidity pool registry
(define-map liquidity-pools
    uint
    {
        base-token-reserve: uint,
        quote-token-reserve: uint,
        total-liquidity: uint,
        accumulated-fees: uint
    }
)

;; Find the smaller of two uint values
(define-private (min-uint (a uint) (b uint))
    (if (<= a b)
        a
        b))

;; Read-only functions
(define-read-only (get-staker-position (staker principal))
    (map-get? staker-positions staker)
)

(define-read-only (get-pool-data (pool-id uint))
    (map-get? liquidity-pools pool-id)
)

(define-read-only (calculate-share-issuance (base-amount uint) (quote-amount uint))
    (let (
        (pool (unwrap! (get-pool-data u1) (err ERR-MATH-FAILURE)))
        (total-shares (get total-liquidity pool))
    )
    (ok (if (is-eq total-shares u0)
        (sqrti (* base-amount quote-amount))
        (min-uint
            (/ (* base-amount total-shares) (get base-token-reserve pool))
            (/ (* quote-amount total-shares) (get quote-token-reserve pool))
        )))
    )
)

;; Public functions
(define-public (deposit-liquidity (base-token <ft-trait>) (quote-token <ft-trait>) (base-amount uint) (quote-amount uint))
    (begin
        (asserts! (and 
            (is-eq (contract-of base-token) base-token-principal)
            (is-eq (contract-of quote-token) quote-token-principal))
            ERR-TOKEN-MISMATCH)
            
        (let (
            (staker-data (default-to 
                {
                    base-token-amount: u0,
                    quote-token-amount: u0,
                    liquidity-shares: u0,
                    deposit-block: u0,
                    last-harvest: block-height,
                    unlock-block: u0
                }
                (map-get? staker-positions tx-sender)))
            (shares-calculation (calculate-share-issuance base-amount quote-amount))
        )
        (asserts! (>= base-amount MIN_DEPOSIT_AMOUNT) ERR-BELOW-THRESHOLD)
        (asserts! (>= quote-amount MIN_DEPOSIT_AMOUNT) ERR-BELOW-THRESHOLD)
        (asserts! (is-eq (get liquidity-shares staker-data) u0) ERR-EXISTING-POSITION)
        
        (let 
            ((shares (unwrap! shares-calculation ERR-MATH-FAILURE)))
            
            ;; Transfer tokens to contract
            (try! (contract-call? base-token transfer base-amount tx-sender (as-contract tx-sender)))
            (try! (contract-call? quote-token transfer quote-amount tx-sender (as-contract tx-sender)))
            
            ;; Record staker position
            (map-set staker-positions tx-sender
                {
                    base-token-amount: base-amount,
                    quote-token-amount: quote-amount,
                    liquidity-shares: shares,
                    deposit-block: block-height,
                    last-harvest: block-height,
                    unlock-block: (+ block-height STAKING_PERIOD)
                }
            )
            
            ;; Update pool state
            (try! (update-pool-state base-amount quote-amount shares))
            (ok shares)))
    )
)

(define-public (withdraw-liquidity (base-token <ft-trait>) (quote-token <ft-trait>))
    (begin
        (asserts! (and 
            (is-eq (contract-of base-token) base-token-principal)
            (is-eq (contract-of quote-token) quote-token-principal))
            ERR-TOKEN-MISMATCH)
            
        (let (
            (staker-data (unwrap! (get-staker-position tx-sender) ERR-NO-POSITION))
            (current-height block-height)
        )
        (asserts! (>= current-height (get unlock-block staker-data)) ERR-TIME-LOCK)
        
        (let (
            (base-amount (get base-token-amount staker-data))
            (quote-amount (get quote-token-amount staker-data))
            (shares (get liquidity-shares staker-data))
        )
            ;; Calculate yield
            (let (
                (yield-amount (calculate-yield tx-sender))
                (total-base (+ base-amount yield-amount))
                (total-quote (+ quote-amount yield-amount))
            )
                ;; Return tokens to staker
                (try! (as-contract (contract-call? base-token transfer total-base (as-contract tx-sender) tx-sender)))
                (try! (as-contract (contract-call? quote-token transfer total-quote (as-contract tx-sender) tx-sender)))
                
                ;; Update protocol state
                (map-delete staker-positions tx-sender)
                (try! (update-pool-state total-base total-quote shares))
                (ok true)
            ))))
)

;; Private helper functions
(define-private (update-pool-state (base-delta uint) (quote-delta uint) (share-delta uint))
    (let (
        (pool (unwrap! (get-pool-data u1) ERR-MATH-FAILURE))
        (new-base-reserve (- (get base-token-reserve pool) base-delta))
        (new-quote-reserve (- (get quote-token-reserve pool) quote-delta))
        (new-total-shares (- (get total-liquidity pool) share-delta))
    )
    (asserts! (and (>= new-base-reserve u0) (>= new-quote-reserve u0) (>= new-total-shares u0)) ERR-INSUFFICIENT-FUNDS)
    (map-set liquidity-pools u1
        {
            base-token-reserve: new-base-reserve,
            quote-token-reserve: new-quote-reserve,
            total-liquidity: new-total-shares,
            accumulated-fees: (get accumulated-fees pool)
        }
    )
    (ok true))
)

(define-private (calculate-yield (staker principal))
    (let (
        (staker-data (unwrap! (get-staker-position staker) u0))
        (blocks-staked (- block-height (get last-harvest staker-data)))
        (share-amount (get liquidity-shares staker-data))
    )
    (/ (* (* share-amount blocks-staked) (var-get yield-rate)) u10000))
)

;; Administrative functions
(define-private (verify-and-update-admin (new-admin principal))
    (begin
        (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR-INVALID-ADMIN)
        (let ((staker-data (get-staker-position new-admin)))
            (asserts! (is-some staker-data) ERR-INVALID-ADMIN)
            (let ((verified-data (unwrap! staker-data ERR-ADMIN-VALIDATION)))
                (asserts! (> (get liquidity-shares verified-data) u0) ERR-ADMIN-VALIDATION)
                (asserts! (>= block-height (get unlock-block verified-data)) ERR-ADMIN-VALIDATION)
                (ok (var-set protocol-admin new-admin)))))
)

(define-public (transfer-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED)
        (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR-INVALID-ADMIN)
        (try! (verify-and-update-admin new-admin))
        (ok true))
)

(define-public (update-yield-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED)
        (asserts! (> new-rate u0) ERR-TOKEN-MISMATCH)
        (ok (var-set yield-rate new-rate)))
)

(define-public (set-protocol-status)
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED)
        (var-set protocol-active (not (var-get protocol-active)))
        (ok true))
)