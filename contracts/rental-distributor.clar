;; Rental Distributor Contract
;; Automatically distributes rental income to fractional owners based on their ownership percentage 
;; and manages property-related expenses and maintenance costs.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u700))
(define-constant ERR-PROPERTY-NOT-FOUND (err u701))
(define-constant ERR-INSUFFICIENT-FUNDS (err u702))
(define-constant ERR-NO-RENTAL-INCOME (err u703))
(define-constant ERR-INVALID-AMOUNT (err u704))

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var platform-fee uint u500) ;; 5%

;; Data Maps
(define-map rental-income uint {
    total-collected: uint,
    distributed: uint,
    expenses: uint,
    last-distribution: uint
})

(define-map owner-earnings {
    property-id: uint,
    owner: principal
} {
    total-earned: uint,
    claimed: uint,
    last-claim: uint
})

;; Public Functions
(define-public (distribute-rental (property-id uint) (amount uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; This would integrate with property-tokenizer to get ownership data
        ;; and distribute proportionally to all token holders
        
        (let (
            (current-income (default-to 
                {total-collected: u0, distributed: u0, expenses: u0, last-distribution: u0}
                (map-get? rental-income property-id)
            ))
        )
            (map-set rental-income property-id {
                total-collected: (+ (get total-collected current-income) amount),
                distributed: (get distributed current-income),
                expenses: (get expenses current-income),
                last-distribution: block-height
            })
            
            (ok amount)
        )
    )
)

(define-public (claim-rental-income (property-id uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        
        ;; This would calculate and transfer earned rental income to the caller
        ;; based on their fractional ownership percentage
        
        (ok u0) ;; Placeholder
    )
)

(define-public (collect-expenses (property-id uint) (expense-amount uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (> expense-amount u0) ERR-INVALID-AMOUNT)
        
        (let (
            (current-income (default-to 
                {total-collected: u0, distributed: u0, expenses: u0, last-distribution: u0}
                (map-get? rental-income property-id)
            ))
        )
            (map-set rental-income property-id (merge current-income {
                expenses: (+ (get expenses current-income) expense-amount)
            }))
            
            (ok expense-amount)
        )
    )
)

;; Read-Only Functions
(define-read-only (get-rental-info (property-id uint))
    (map-get? rental-income property-id)
)

(define-read-only (get-owner-earnings (property-id uint) (owner principal))
    (map-get? owner-earnings {property-id: property-id, owner: owner})
)

;; Admin Functions
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)
    )
)
