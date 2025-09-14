;; Property Tokenizer Contract
;; Core contract that tokenizes real estate properties into fractions, manages ownership records, 
;; and handles property registration and verification processes.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u600))
(define-constant ERR-PROPERTY-NOT-FOUND (err u601))
(define-constant ERR-PROPERTY-EXISTS (err u602))
(define-constant ERR-INVALID-AMOUNT (err u603))
(define-constant ERR-INSUFFICIENT-TOKENS (err u604))
(define-constant ERR-PROPERTY-NOT-VERIFIED (err u605))
(define-constant ERR-TRANSFER-FAILED (err u606))
(define-constant ERR-INVALID-PROPERTY (err u607))

;; Property Status Constants
(define-constant STATUS-PENDING "pending")
(define-constant STATUS-VERIFIED "verified")
(define-constant STATUS-ACTIVE "active")
(define-constant STATUS-SOLD "sold")

;; Fee Constants
(define-constant TOKENIZATION-FEE u1000) ;; 1% (basis points)
(define-constant TRANSFER-FEE u50) ;; 0.5%
(define-constant MIN-TOKEN-AMOUNT u100)
(define-constant MAX-TOKENS-PER-PROPERTY u10000)

;; Data Variables
(define-data-var next-property-id uint u1)
(define-data-var platform-treasury principal tx-sender)
(define-data-var contract-paused bool false)
(define-data-var total-properties uint u0)
(define-data-var total-value-locked uint u0)

;; Data Maps
(define-map properties uint {
    owner: principal,
    address: (string-utf8 200),
    value: uint,
    total-tokens: uint,
    available-tokens: uint,
    property-type: (string-ascii 20),
    status: (string-ascii 10),
    created-at: uint,
    verified-at: (optional uint),
    metadata: (string-utf8 500)
})

(define-map property-ownership {
    property-id: uint,
    owner: principal
} {
    tokens-owned: uint,
    purchase-price: uint,
    acquired-at: uint
})

(define-map property-verifiers principal bool)
(define-map property-managers principal bool)

(define-map ownership-history uint {
    property-id: uint,
    from: (optional principal),
    to: principal,
    tokens: uint,
    price-per-token: uint,
    timestamp: uint
})

(define-map user-portfolio principal {
    properties-owned: (list 50 uint),
    total-tokens: uint,
    total-invested: uint,
    first-investment: (optional uint)
})

;; Private Functions

(define-private (is-authorized-verifier (user principal))
    (or (is-eq user CONTRACT-OWNER) (default-to false (map-get? property-verifiers user)))
)

(define-private (is-authorized-manager (user principal))
    (or (is-eq user CONTRACT-OWNER) (default-to false (map-get? property-managers user)))
)

(define-private (calculate-tokenization-fee (property-value uint))
    (/ (* property-value TOKENIZATION-FEE) u10000)
)

(define-private (calculate-transfer-fee (transfer-amount uint))
    (/ (* transfer-amount TRANSFER-FEE) u10000)
)

(define-private (update-user-portfolio (user principal) (property-id uint) (tokens uint) (investment-amount uint))
    (let (
        (current-portfolio (default-to 
            {properties-owned: (list), total-tokens: u0, total-invested: u0, first-investment: none}
            (map-get? user-portfolio user)
        ))
        (current-properties (get properties-owned current-portfolio))
        (updated-properties (unwrap! (as-max-len? (append current-properties property-id) u50) current-properties))
    )
        (map-set user-portfolio user {
            properties-owned: updated-properties,
            total-tokens: (+ (get total-tokens current-portfolio) tokens),
            total-invested: (+ (get total-invested current-portfolio) investment-amount),
            first-investment: (if (is-none (get first-investment current-portfolio))
                                (some block-height)
                                (get first-investment current-portfolio))
        })
    )
)

(define-private (record-ownership-transfer (property-id uint) (from (optional principal)) (to principal) (tokens uint) (price-per-token uint))
    (let (
        (history-id (+ (* property-id u10000) block-height))
    )
        (map-set ownership-history history-id {
            property-id: property-id,
            from: from,
            to: to,
            tokens: tokens,
            price-per-token: price-per-token,
            timestamp: block-height
        })
    )
)

;; Read-Only Functions

(define-read-only (get-property (property-id uint))
    (map-get? properties property-id)
)

(define-read-only (get-property-ownership (property-id uint) (owner principal))
    (map-get? property-ownership {property-id: property-id, owner: owner})
)

(define-read-only (get-user-portfolio (user principal))
    (map-get? user-portfolio user)
)

(define-read-only (get-total-properties)
    (var-get total-properties)
)

(define-read-only (get-total-value-locked)
    (var-get total-value-locked)
)

(define-read-only (get-token-price (property-id uint))
    (match (map-get? properties property-id)
        property-data 
            (ok (/ (get value property-data) (get total-tokens property-data)))
        ERR-PROPERTY-NOT-FOUND
    )
)

(define-read-only (get-ownership-percentage (property-id uint) (owner principal))
    (match (map-get? property-ownership {property-id: property-id, owner: owner})
        ownership-data
            (match (map-get? properties property-id)
                property-data
                    (ok (/ (* (get tokens-owned ownership-data) u10000) (get total-tokens property-data)))
                ERR-PROPERTY-NOT-FOUND
            )
        (ok u0)
    )
)

(define-read-only (is-contract-paused)
    (var-get contract-paused)
)

;; Public Functions

(define-public (register-property 
    (address (string-utf8 200))
    (value uint)
    (total-tokens uint)
    (property-type (string-ascii 20))
    (metadata (string-utf8 500))
)
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (> value u0) ERR-INVALID-AMOUNT)
        (asserts! (and (>= total-tokens MIN-TOKEN-AMOUNT) (<= total-tokens MAX-TOKENS-PER-PROPERTY)) ERR-INVALID-AMOUNT)
        
        (let (
            (property-id (var-get next-property-id))
            (tokenization-fee (calculate-tokenization-fee value))
        )
            ;; Charge tokenization fee
            (try! (stx-transfer? tokenization-fee tx-sender (var-get platform-treasury)))
            
            ;; Register property
            (map-set properties property-id {
                owner: tx-sender,
                address: address,
                value: value,
                total-tokens: total-tokens,
                available-tokens: total-tokens,
                property-type: property-type,
                status: STATUS-PENDING,
                created-at: block-height,
                verified-at: none,
                metadata: metadata
            })
            
            ;; Update contract state
            (var-set next-property-id (+ property-id u1))
            (var-set total-properties (+ (var-get total-properties) u1))
            
            (ok property-id)
        )
    )
)

(define-public (verify-property (property-id uint))
    (begin
        (asserts! (is-authorized-verifier tx-sender) ERR-UNAUTHORIZED)
        
        (let (
            (property (unwrap! (map-get? properties property-id) ERR-PROPERTY-NOT-FOUND))
        )
            (asserts! (is-eq (get status property) STATUS-PENDING) ERR-INVALID-PROPERTY)
            
            ;; Update property status
            (map-set properties property-id (merge property {
                status: STATUS-VERIFIED,
                verified-at: (some block-height)
            }))
            
            ;; Add to total value locked
            (var-set total-value-locked (+ (var-get total-value-locked) (get value property)))
            
            (ok true)
        )
    )
)

(define-public (tokenize-property (property-id uint))
    (begin
        (let (
            (property (unwrap! (map-get? properties property-id) ERR-PROPERTY-NOT-FOUND))
        )
            (asserts! (is-eq tx-sender (get owner property)) ERR-UNAUTHORIZED)
            (asserts! (is-eq (get status property) STATUS-VERIFIED) ERR-PROPERTY-NOT-VERIFIED)
            
            ;; Update property status to active
            (map-set properties property-id (merge property {
                status: STATUS-ACTIVE
            }))
            
            ;; Initialize owner's token ownership
            (map-set property-ownership 
                {property-id: property-id, owner: tx-sender}
                {
                    tokens-owned: (get total-tokens property),
                    purchase-price: u0,
                    acquired-at: block-height
                }
            )
            
            ;; Update user portfolio
            (update-user-portfolio tx-sender property-id (get total-tokens property) u0)
            
            ;; Record initial ownership
            (record-ownership-transfer property-id none tx-sender (get total-tokens property) u0)
            
            (ok true)
        )
    )
)

(define-public (purchase-tokens (property-id uint) (token-amount uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
        
        (let (
            (property (unwrap! (map-get? properties property-id) ERR-PROPERTY-NOT-FOUND))
            (token-price (/ (get value property) (get total-tokens property)))
            (total-cost (* token-amount token-price))
            (transfer-fee (calculate-transfer-fee total-cost))
            (seller (get owner property))
        )
            (asserts! (is-eq (get status property) STATUS-ACTIVE) ERR-PROPERTY-NOT-VERIFIED)
            (asserts! (<= token-amount (get available-tokens property)) ERR-INSUFFICIENT-TOKENS)
            
            ;; Transfer payment to seller
            (try! (stx-transfer? total-cost tx-sender seller))
            
            ;; Transfer fee to platform
            (try! (stx-transfer? transfer-fee tx-sender (var-get platform-treasury)))
            
            ;; Update property available tokens
            (map-set properties property-id (merge property {
                available-tokens: (- (get available-tokens property) token-amount)
            }))
            
            ;; Update buyer ownership
            (let (
                (current-ownership (default-to 
                    {tokens-owned: u0, purchase-price: u0, acquired-at: block-height}
                    (map-get? property-ownership {property-id: property-id, owner: tx-sender})
                ))
            )
                (map-set property-ownership 
                    {property-id: property-id, owner: tx-sender}
                    {
                        tokens-owned: (+ (get tokens-owned current-ownership) token-amount),
                        purchase-price: (+ (get purchase-price current-ownership) total-cost),
                        acquired-at: (get acquired-at current-ownership)
                    }
                )
            )
            
            ;; Update user portfolio
            (update-user-portfolio tx-sender property-id token-amount total-cost)
            
            ;; Record ownership transfer
            (record-ownership-transfer property-id (some seller) tx-sender token-amount token-price)
            
            (ok token-amount)
        )
    )
)

(define-public (transfer-tokens (property-id uint) (recipient principal) (token-amount uint) (price-per-token uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
        
        (let (
            (sender-ownership (unwrap! 
                (map-get? property-ownership {property-id: property-id, owner: tx-sender})
                ERR-INSUFFICIENT-TOKENS
            ))
            (total-amount (* token-amount price-per-token))
            (transfer-fee (calculate-transfer-fee total-amount))
        )
            (asserts! (>= (get tokens-owned sender-ownership) token-amount) ERR-INSUFFICIENT-TOKENS)
            
            ;; Transfer payment from recipient to sender
            (try! (stx-transfer? total-amount recipient tx-sender))
            
            ;; Transfer fee to platform
            (try! (stx-transfer? transfer-fee recipient (var-get platform-treasury)))
            
            ;; Update sender ownership
            (map-set property-ownership 
                {property-id: property-id, owner: tx-sender}
                (merge sender-ownership {
                    tokens-owned: (- (get tokens-owned sender-ownership) token-amount)
                })
            )
            
            ;; Update recipient ownership
            (let (
                (recipient-ownership (default-to 
                    {tokens-owned: u0, purchase-price: u0, acquired-at: block-height}
                    (map-get? property-ownership {property-id: property-id, owner: recipient})
                ))
            )
                (map-set property-ownership 
                    {property-id: property-id, owner: recipient}
                    {
                        tokens-owned: (+ (get tokens-owned recipient-ownership) token-amount),
                        purchase-price: (+ (get purchase-price recipient-ownership) total-amount),
                        acquired-at: (get acquired-at recipient-ownership)
                    }
                )
            )
            
            ;; Update recipient portfolio
            (update-user-portfolio recipient property-id token-amount total-amount)
            
            ;; Record transfer
            (record-ownership-transfer property-id (some tx-sender) recipient token-amount price-per-token)
            
            (ok true)
        )
    )
)

;; Admin Functions

(define-public (authorize-verifier (verifier principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set property-verifiers verifier true)
        (ok true)
    )
)

(define-public (revoke-verifier (verifier principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set property-verifiers verifier false)
        (ok true)
    )
)

(define-public (authorize-manager (manager principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set property-managers manager true)
        (ok true)
    )
)

(define-public (set-treasury (new-treasury principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set platform-treasury new-treasury)
        (ok new-treasury)
    )
)

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)
    )
)

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused false)
        (ok true)
    )
)
