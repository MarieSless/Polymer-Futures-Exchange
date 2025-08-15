;; Polymer Futures Exchange
;; This contract facilitates the creation and trading of polymer futures contracts.
;; Users can open long or short positions on various polymer types.
;; The contract manages collateral and settles contracts at expiry.

;; --- SIP-010 Fungible Token Trait ---
(define-trait ft-trait
  ((transfer (uint principal principal (optional (buff 34))) (response bool uint))
   (get-name () (response (string-ascii 32) uint))
   (get-symbol () (response (string-ascii 32) uint))
   (get-decimals () (response uint uint))
   (get-balance (principal) (response uint uint))
   (get-total-supply () (response uint uint))))

;; --- Constants and Errors ---
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CONTRACT_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u102))
(define-constant ERR_CONTRACT_EXPIRED (err u103))
(define-constant ERR_INVALID_PRICE (err u104))
(define-constant ERR_POSITION_NOT_FOUND (err u105))
(define-constant ERR_CANNOT_LIQUIDATE (err u106))
(define-constant ERR_INVALID_POSITION_TYPE (err u107))
(define-constant ERR_CONTRACT_INACTIVE (err u108))
(define-constant ERR_TOKEN_TRANSFER_FAILED (err u109))
(define-constant ERR_POSITION_ALREADY_EXISTS (err u110))
(define-constant LEVERAGE_FACTOR u2)
(define-constant MAINTENANCE_MARGIN u125) ;; 12.5%
(define-constant MAX_POSITION_SIZE u1000000) ;; Maximum position size
(define-constant MIN_COLLATERAL u100) ;; Minimum collateral amount

;; --- Data Maps and Variables ---
(define-data-var last-contract-id uint u0)
(define-data-var oracle-principal (optional principal) none)
(define-data-var collateral-token (optional principal) none)

;; Polymer price data, to be updated by an oracle
(define-map polymer-prices (string-ascii 16) uint) ;; "PET", "HDPE", etc.

;; Futures contract details
(define-map futures-contracts uint {
  id: uint,
  polymer-type: (string-ascii 16),
  expiry-block: uint,
  is-active: bool
})

;; User positions
(define-map user-positions { user: principal, contract-id: uint } {
  position-type: (string-ascii 5), ;; "long" or "short"
  entry-price: uint,
  collateral-amount: uint,
  position-size: uint
})

;; --- Admin Functions ---

;; Set oracle principal (only by contract owner)
(define-public (set-oracle-principal (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set oracle-principal (some new-oracle))
    (ok true)
  )
)

;; Set collateral token (only by contract owner)
(define-public (set-collateral-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set collateral-token (some token-contract))
    (ok true)
  )
)

;; --- Private Functions ---

(define-private (calculate-margin (position-size uint) (leverage uint))
  (/ (* position-size u100) leverage)
)

(define-private (get-liquidation-price (position { position-type: (string-ascii 5), entry-price: uint, collateral-amount: uint, position-size: uint }))
  (if (is-eq (get position-type position) "long")
    (if (> (get entry-price position) (/ (* (get collateral-amount position) (get entry-price position)) (get position-size position)))
      (- (get entry-price position) (/ (* (get collateral-amount position) (get entry-price position)) (get position-size position)))
      u0
    )
    (+ (get entry-price position) (/ (* (get collateral-amount position) (get entry-price position)) (get position-size position)))
  )
)

(define-private (is-valid-position-type (position-type (string-ascii 5)))
  (or (is-eq position-type "long") (is-eq position-type "short"))
)

(define-private (calculate-pnl (position-type (string-ascii 5)) (entry-price uint) (current-price uint) (position-size uint))
  (let ((price-diff (if (is-eq position-type "long")
                      (if (>= current-price entry-price)
                        (- current-price entry-price)
                        (- entry-price current-price))
                      (if (>= entry-price current-price)
                        (- entry-price current-price)
                        (- current-price entry-price)))))
    (if (is-eq position-type "long")
      (if (>= current-price entry-price)
        (/ (* price-diff position-size) entry-price)
        (- u0 (/ (* price-diff position-size) entry-price)))
      (if (>= entry-price current-price)
        (/ (* price-diff position-size) entry-price)
        (- u0 (/ (* price-diff position-size) entry-price))))
  )
)

;; --- Public Functions ---

;; Update polymer price (only by oracle)
(define-public (update-polymer-price (polymer-type (string-ascii 16)) (new-price uint))
  (let ((oracle (unwrap! (var-get oracle-principal) ERR_UNAUTHORIZED)))
    (asserts! (is-eq tx-sender oracle) ERR_UNAUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_PRICE)
    (map-set polymer-prices polymer-type new-price)
    (ok true)
  )
)

;; Create a new futures contract (only by contract owner)
(define-public (create-futures-contract (polymer-type (string-ascii 16)) (expiry-in-blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> expiry-in-blocks u0) ERR_INVALID_PRICE)
    (let ((contract-id (+ u1 (var-get last-contract-id))))
      (map-set futures-contracts contract-id {
        id: contract-id,
        polymer-type: polymer-type,
        expiry-block: (+ block-height expiry-in-blocks),
        is-active: true
      })
      (var-set last-contract-id contract-id)
      (ok contract-id)
    )
  )
)

;; Open a long or short position
(define-public (open-position (contract-id uint) (position-type (string-ascii 5)) (position-size uint) (collateral-token-contract <ft-trait>))
  (let
    (
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
      (required-collateral (calculate-margin position-size LEVERAGE_FACTOR))
      (user-balance (unwrap! (contract-call? collateral-token-contract get-balance tx-sender) ERR_TOKEN_TRANSFER_FAILED))
    )
    (asserts! (get is-active contract) ERR_CONTRACT_INACTIVE)
    (asserts! (< block-height (get expiry-block contract)) ERR_CONTRACT_EXPIRED)
    (asserts! (is-valid-position-type position-type) ERR_INVALID_POSITION_TYPE)
    (asserts! (<= position-size MAX_POSITION_SIZE) ERR_INVALID_PRICE)
    (asserts! (>= required-collateral MIN_COLLATERAL) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (>= user-balance required-collateral) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (is-none (map-get? user-positions { user: tx-sender, contract-id: contract-id })) ERR_POSITION_ALREADY_EXISTS)

    (try! (contract-call? collateral-token-contract transfer required-collateral tx-sender (as-contract tx-sender) none))

    (map-set user-positions { user: tx-sender, contract-id: contract-id } {
      position-type: position-type,
      entry-price: current-price,
      collateral-amount: required-collateral,
      position-size: position-size
    })
    (ok true)
  )
)

;; Close an existing position
(define-public (close-position (contract-id uint) (collateral-token-contract <ft-trait>))
  (let
    (
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (position (unwrap! (map-get? user-positions { user: tx-sender, contract-id: contract-id }) ERR_POSITION_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
    )
    (let
      (
        (pnl-amount (calculate-pnl (get position-type position) (get entry-price position) current-price (get position-size position)))
        (return-amount (+ (get collateral-amount position) pnl-amount))
      )
      (asserts! (>= return-amount u0) ERR_INSUFFICIENT_COLLATERAL)
      (try! (as-contract (contract-call? collateral-token-contract transfer return-amount (as-contract tx-sender) tx-sender none)))
      (map-delete user-positions { user: tx-sender, contract-id: contract-id })
      (ok pnl-amount)
    )
  )
)

;; Liquidate an underwater position
(define-public (liquidate-position (user principal) (contract-id uint) (collateral-token-contract <ft-trait>))
  (let
    (
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (position (unwrap! (map-get? user-positions { user: user, contract-id: contract-id }) ERR_POSITION_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
      (liquidation-price (get-liquidation-price position))
    )
    (asserts!
      (if (is-eq (get position-type position) "long")
        (<= current-price liquidation-price)
        (>= current-price liquidation-price)
      )
      ERR_CANNOT_LIQUIDATE
    )
    ;; Transfer remaining collateral to the liquidator as a reward
    (let ((remaining-collateral (get collateral-amount position)))
      (try! (as-contract (contract-call? collateral-token-contract transfer remaining-collateral (as-contract tx-sender) tx-sender none)))
      (map-delete user-positions { user: user, contract-id: contract-id })
      (ok true)
    )
  )
)

;; Deactivate a futures contract (only by contract owner)
(define-public (deactivate-contract (contract-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (map-get? futures-contracts contract-id)
      contract-data (begin
        (map-set futures-contracts contract-id (merge contract-data { is-active: false }))
        (ok true)
      )
      ERR_CONTRACT_NOT_FOUND
    )
  )
)

;; --- Read-Only Functions ---
(define-read-only (get-contract-details (contract-id uint))
  (map-get? futures-contracts contract-id)
)

(define-read-only (get-user-position (user principal) (contract-id uint))
  (map-get? user-positions { user: user, contract-id: contract-id })
)

(define-read-only (get-polymer-price (polymer-type (string-ascii 16)))
  (map-get? polymer-prices polymer-type)
)

(define-read-only (get-oracle-principal)
  (var-get oracle-principal)
)

(define-read-only (get-collateral-token)
  (var-get collateral-token)
)

(define-read-only (get-last-contract-id)
  (var-get last-contract-id)
)

(define-read-only (calculate-liquidation-price (user principal) (contract-id uint))
  (match (map-get? user-positions { user: user, contract-id: contract-id })
    position (ok (get-liquidation-price position))
    ERR_POSITION_NOT_FOUND
  )
)

(define-read-only (get-position-pnl (user principal) (contract-id uint))
  (let
    (
      (position (unwrap! (map-get? user-positions { user: user, contract-id: contract-id }) ERR_POSITION_NOT_FOUND))
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
    )
    (ok (calculate-pnl (get position-type position) (get entry-price position) current-price (get position-size position)))
  )
)