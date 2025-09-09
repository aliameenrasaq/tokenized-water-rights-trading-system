;; Usage Tracker Smart Contract
;; Monitors and validates water consumption against allocated rights
;; Provides real-time usage logging and compliance verification

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_USAGE (err u1002))
(define-constant ERR_USAGE_LIMIT_EXCEEDED (err u1003))
(define-constant ERR_INVALID_TIMESTAMP (err u1004))
(define-constant ERR_USER_NOT_FOUND (err u1005))
(define-constant ERR_INVALID_AMOUNT (err u1006))
(define-constant ERR_ALREADY_REPORTED (err u1007))

;; Data Variables
(define-data-var total-users uint u0)
(define-data-var total-usage uint u0)
(define-data-var violation-count uint u0)

;; Data Maps
;; User registration and allocation data
(define-map users principal {
    allocated-volume: uint,
    used-volume: uint,
    registration-timestamp: uint,
    status: (string-ascii 20),
    location: (string-ascii 50)
})

;; Daily usage tracking
(define-map daily-usage {
    user: principal,
    date: uint
} {
    volume: uint,
    timestamp: uint,
    validated: bool
})

;; Usage history for analytics
(define-map usage-history uint {
    user: principal,
    volume: uint,
    timestamp: uint,
    transaction-type: (string-ascii 20),
    notes: (string-ascii 100)
})

;; Violation tracking
(define-map violations principal {
    count: uint,
    total-excess: uint,
    last-violation: uint,
    penalty-status: (string-ascii 20)
})

;; Authorized validators (can report usage)
(define-map authorized-validators principal bool)

;; Usage reports counter
(define-data-var usage-report-id uint u0)

;; Private Functions

;; Calculate days since epoch for date grouping
(define-private (get-day-key (timestamp uint))
    (/ timestamp u86400) ;; 86400 seconds in a day
)

;; Validate timestamp is not in future
(define-private (is-valid-timestamp (timestamp uint))
    (<= timestamp block-height)
)

;; Check if user exists and is active
(define-private (is-user-active (user principal))
    (match (map-get? users user)
        user-data (is-eq (get status user-data) "active")
        false
    )
)

;; Calculate remaining allocation for user
(define-private (get-remaining-allocation (user principal))
    (match (map-get? users user)
        user-data 
        (- (get allocated-volume user-data) (get used-volume user-data))
        u0
    )
)

;; Public Functions

;; Register a new user with water allocation
(define-public (register-user 
    (user principal) 
    (allocated-volume uint) 
    (location (string-ascii 50))
)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> allocated-volume u0) ERR_INVALID_AMOUNT)
        
        (map-set users user {
            allocated-volume: allocated-volume,
            used-volume: u0,
            registration-timestamp: block-height,
            status: "active",
            location: location
        })
        
        (var-set total-users (+ (var-get total-users) u1))
        (ok true)
    )
)

;; Record water usage by authorized validators
(define-public (record-usage 
    (user principal) 
    (volume uint) 
    (timestamp uint)
)
    (let (
        (current-day (get-day-key timestamp))
        (report-id (+ (var-get usage-report-id) u1))
        (remaining-allocation (get-remaining-allocation user))
    )
        ;; Validation checks
        (asserts! (default-to false (map-get? authorized-validators tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (is-user-active user) ERR_USER_NOT_FOUND)
        (asserts! (> volume u0) ERR_INVALID_AMOUNT)
        (asserts! (is-valid-timestamp timestamp) ERR_INVALID_TIMESTAMP)
        
        ;; Check if usage exceeds allocation
        (if (> volume remaining-allocation)
            ;; Handle violation
            (begin
                (unwrap-panic (handle-violation user (- volume remaining-allocation)))
                ERR_USAGE_LIMIT_EXCEEDED
            )
            ;; Record valid usage
            (begin
                ;; Update user's used volume
                (match (map-get? users user)
                    user-data 
                    (map-set users user 
                        (merge user-data { used-volume: (+ (get used-volume user-data) volume) })
                    )
                    false
                )
                
                ;; Record daily usage
                (map-set daily-usage { user: user, date: current-day } {
                    volume: volume,
                    timestamp: timestamp,
                    validated: true
                })
                
                ;; Add to usage history
                (map-set usage-history report-id {
                    user: user,
                    volume: volume,
                    timestamp: timestamp,
                    transaction-type: "usage",
                    notes: "Regular usage recorded"
                })
                
                ;; Update counters
                (var-set usage-report-id report-id)
                (var-set total-usage (+ (var-get total-usage) volume))
                
                (ok true)
            )
        )
    )
)

;; Handle usage violations
(define-private (handle-violation (user principal) (excess-volume uint))
    (let (
        (current-violations (default-to { count: u0, total-excess: u0, last-violation: u0, penalty-status: "none" }
                           (map-get? violations user)))
    )
        ;; Update violation record
        (map-set violations user {
            count: (+ (get count current-violations) u1),
            total-excess: (+ (get total-excess current-violations) excess-volume),
            last-violation: block-height,
            penalty-status: "pending"
        })
        
        ;; Update global violation count
        (var-set violation-count (+ (var-get violation-count) u1))
        
        (ok true)
    )
)

;; Add authorized validator
(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set authorized-validators validator true)
        (ok true)
    )
)

;; Remove authorized validator
(define-public (remove-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete authorized-validators validator)
        (ok true)
    )
)

;; Update user status
(define-public (update-user-status (user principal) (new-status (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? users user)) ERR_USER_NOT_FOUND)
        
        (match (map-get? users user)
            user-data 
            (begin
                (map-set users user (merge user-data { status: new-status }))
                (ok true)
            )
            ERR_USER_NOT_FOUND
        )
    )
)

;; Get user information
(define-read-only (get-user-info (user principal))
    (map-get? users user)
)

;; Get daily usage for specific user and date
(define-read-only (get-daily-usage (user principal) (date uint))
    (map-get? daily-usage { user: user, date: date })
)

;; Get violation history for user
(define-read-only (get-user-violations (user principal))
    (map-get? violations user)
)

;; Get usage history by ID
(define-read-only (get-usage-history (history-id uint))
    (map-get? usage-history history-id)
)

;; Check if validator is authorized
(define-read-only (is-validator-authorized (validator principal))
    (default-to false (map-get? authorized-validators validator))
)

;; Get system statistics
(define-read-only (get-system-stats)
    {
        total-users: (var-get total-users),
        total-usage: (var-get total-usage),
        violation-count: (var-get violation-count),
        total-reports: (var-get usage-report-id)
    }
)

;; Calculate user compliance rate
(define-read-only (get-user-compliance-rate (user principal))
    (match (map-get? users user)
        user-data 
        (let (
            (allocated (get allocated-volume user-data))
            (used (get used-volume user-data))
        )
            (if (> allocated u0)
                (/ (* used u100) allocated) ;; Return percentage
                u0
            )
        )
        u0
    )
)

