;; Polymer Futures Exchange
;; This contract facilitates the creation and trading of polymer futures contracts.
;; Users can open long or short positions on various polymer types.
;; The contract manages collateral and settles contracts at expiry.

;; --- SIP-010 Fungible Token Trait ---
(define-trait ft-trait
  ((transfer (uint principal principal) (response bool uint))
   (get-name () (response (string-ascii 32) uint))
   (get-symbol () (response (string-ascii 32) uint))
   (get-decimals () (response uint uint))
   (get-balance-of (principal) (response uint uint))
   (get-total-supply () (response uint uint))))

;; --- Constants and Errors ---
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ORACLE_PRINCIPAL 'SP2J6B0Y0B0J0K0N0P0Q0R0S0T0V0W0X0Y0Z0A0B0C0) ;; Placeholder for a real oracle
(define-constant COLLATERAL_TOKEN <stablecoin-trait>) ;; e.g., 'ST1...usdc-token
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CONTRACT_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u102))
(define-constant ERR_CONTRACT_EXPIRED (err u103))
(define-constant ERR_INVALID_PRICE (err u104))
(define-constant ERR_POSITION_NOT_FOUND (err u105))
(define-constant ERR_CANNOT_LIQUIDATE (err u106))
(define-constant LEVERAGE_FACTOR u2)
(define-constant MAINTENANCE_MARGIN u125) ;; 12.5%

;; --- Data Maps and Variables ---
(define-data-var last-contract-id uint u0)

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

;; --- Private Functions ---

(define-private (calculate-margin (position-size uint) (leverage uint))
  (/ (* position-size u100) leverage)
)

(define-private (get-liquidation-price (position { position-type: (string-ascii 5), entry-price: uint, collateral-amount: uint, position-size: uint }))
  (if (is-eq (get position-type position) "long")
    (- (get entry-price position) (/ (* (get collateral-amount position) (get entry-price position)) (get position-size position)))
    (+ (get entry-price position) (/ (* (get collateral-amount position) (get entry-price position)) (get position-size position)))
  )
)

;; --- Public Functions ---

;; Update polymer price (only by oracle)
(define-public (update-polymer-price (polymer-type (string-ascii 16)) (new-price uint))
  (asserts! (is-eq tx-sender ORACLE_PRINCIPAL) ERR_UNAUTHORIZED)
  (asserts! (> new-price u0) ERR_INVALID_PRICE)
  (map-set polymer-prices polymer-type new-price)
  (ok true)
)

;; Create a new futures contract (only by contract owner)
(define-public (create-futures-contract (polymer-type (string-ascii 16)) (expiry-in-blocks uint))
  (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
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

;; Open a long or short position
(define-public (open-position (contract-id uint) (position-type (string-ascii 5)) (position-size uint))
  (let
    (
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
      (required-collateral (calculate-margin position-size LEVERAGE_FACTOR))
    )
    (asserts! (get is-active contract) ERR_CONTRACT_NOT_FOUND)
    (asserts! (>= block-height (get expiry-block contract)) ERR_CONTRACT_EXPIRED)
    (asserts! (>= (unwrap! (contract-call? COLLATERAL_TOKEN get-balance-of tx-sender) (err u0)) required-collateral) ERR_INSUFFICIENT_COLLATERAL)

    (try! (contract-call? COLLATERAL_TOKEN transfer required-collateral tx-sender (as-contract tx-sender)))

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
(define-public (close-position (contract-id uint))
  (let
    (
      (contract (unwrap! (map-get? futures-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (position (unwrap! (map-get? user-positions { user: tx-sender, contract-id: contract-id }) ERR_POSITION_NOT_FOUND))
      (current-price (unwrap! (map-get? polymer-prices (get polymer-type contract)) ERR_INVALID_PRICE))
    )
    (let
      (
        (pnl (if (is-eq (get position-type position) "long")
               (- current-price (get entry-price position))
               (- (get entry-price position) current-price)
             )
        )
        (pnl-amount (/ (* pnl (get position-size position)) (get entry-price position)))
        (return-amount (+ (get collateral-amount position) pnl-amount))
      )
      (asserts! (>= return-amount u0) (err u0)) ;; Should not happen with solvent positions
      (try! (as-contract (contract-call? COLLATERAL_TOKEN transfer return-amount tx-sender tx-sender)))
      (map-delete user-positions { user: tx-sender, contract-id: contract-id })
      (ok pnl-amount)
    )
  )
)

;; Liquidate an underwater position
(define-public (liquidate-position (user principal) (contract-id uint))
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
    ;; Transfer remaining collateral (if any) to the liquidator as a reward
    (try! (as-contract (contract-call? COLLATERAL_TOKEN transfer (get collateral-amount position) tx-sender tx-sender)))
    (map-delete user-positions { user: user, contract-id: contract-id })
    (ok true)
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