;; Governance Voting Contract
;; Enables fractional property owners to vote on major property decisions including renovations, 
;; management changes, and sale proposals with voting power proportional to ownership stake.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u800))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u801))
(define-constant ERR-VOTING-CLOSED (err u802))
(define-constant ERR-ALREADY-VOTED (err u803))
(define-constant ERR-INSUFFICIENT-TOKENS (err u804))

;; Proposal Types
(define-constant PROPOSAL-RENOVATION "renovation")
(define-constant PROPOSAL-MANAGEMENT "management")
(define-constant PROPOSAL-SALE "sale")

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var contract-paused bool false)
(define-data-var min-voting-period uint u1008) ;; ~7 days

;; Data Maps
(define-map proposals uint {
    property-id: uint,
    proposer: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    proposal-type: (string-ascii 20),
    voting-start: uint,
    voting-end: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 10), ;; "active", "passed", "failed", "executed"
    execution-data: (optional (string-utf8 200))
})

(define-map votes {
    proposal-id: uint,
    voter: principal
} {
    vote-type: (string-ascii 10), ;; "for" or "against"
    voting-power: uint,
    timestamp: uint
})

(define-map vote-delegation principal principal)

;; Public Functions
(define-public (create-proposal 
    (property-id uint)
    (title (string-ascii 100))
    (description (string-utf8 500))
    (proposal-type (string-ascii 20))
    (voting-duration uint)
)
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        (asserts! (>= voting-duration (var-get min-voting-period)) ERR-UNAUTHORIZED)
        
        ;; This would verify the caller owns tokens in the property
        
        (let (
            (proposal-id (var-get next-proposal-id))
        )
            (map-set proposals proposal-id {
                property-id: property-id,
                proposer: tx-sender,
                title: title,
                description: description,
                proposal-type: proposal-type,
                voting-start: block-height,
                voting-end: (+ block-height voting-duration),
                votes-for: u0,
                votes-against: u0,
                status: "active",
                execution-data: none
            })
            
            (var-set next-proposal-id (+ proposal-id u1))
            (ok proposal-id)
        )
    )
)

(define-public (cast-vote (proposal-id uint) (vote-for bool))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
        
        (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            ;; This would get actual voting power from property tokenizer
            (voting-power u1) ;; Placeholder
        )
            (asserts! (<= block-height (get voting-end proposal)) ERR-VOTING-CLOSED)
            (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
            
            ;; Record vote
            (map-set votes {proposal-id: proposal-id, voter: tx-sender} {
                vote-type: (if vote-for "for" "against"),
                voting-power: voting-power,
                timestamp: block-height
            })
            
            ;; Update proposal vote counts
            (map-set proposals proposal-id (merge proposal {
                votes-for: (if vote-for 
                             (+ (get votes-for proposal) voting-power) 
                             (get votes-for proposal)),
                votes-against: (if vote-for 
                                 (get votes-against proposal) 
                                 (+ (get votes-against proposal) voting-power))
            }))
            
            (ok true)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (begin
        (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        )
            (asserts! (> block-height (get voting-end proposal)) ERR-VOTING-CLOSED)
            (asserts! (is-eq (get status proposal) "active") ERR-UNAUTHORIZED)
            
            ;; Check if proposal passed (simple majority)
            (let (
                (passed (> (get votes-for proposal) (get votes-against proposal)))
            )
                (map-set proposals proposal-id (merge proposal {
                    status: (if passed "passed" "failed")
                }))
                
                (ok passed)
            )
        )
    )
)

;; Read-Only Functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-voting-power (user principal) (property-id uint))
    ;; This would integrate with property-tokenizer to get actual voting power
    u1 ;; Placeholder
)

;; Admin Functions
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)
    )
)
