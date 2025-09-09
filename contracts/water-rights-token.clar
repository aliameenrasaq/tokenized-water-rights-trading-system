;; Water Rights Token Smart Contract
;; Handles tokenization, transfer, and metadata of water usage rights
;; Implements SIP-010 fungible token standard with water rights specific features

;; Token Definition
(define-fungible-token water-rights-token)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant TOKEN_NAME "Water Rights Token")
(define-constant TOKEN_SYMBOL "WRT")
(define-constant TOKEN_DECIMALS u6) ;; 6 decimal places for precision
(define-constant MAX_SUPPLY u1000000000000) ;; 1 million tokens with 6 decimals

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_INSUFFICIENT_BALANCE (err u2002))
(define-constant ERR_INVALID_AMOUNT (err u2003))
(define-constant ERR_INVALID_RECIPIENT (err u2004))
(define-constant ERR_TOKEN_NOT_FOUND (err u2005))
(define-constant ERR_ALREADY_EXISTS (err u2006))
(define-constant ERR_EXPIRED (err u2007))
(define-constant ERR_TRANSFER_RESTRICTED (err u2008))
(define-constant ERR_MAX_SUPPLY_EXCEEDED (err u2009))

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var next-token-id uint u1)
(define-data-var contract-paused bool false)

;; Token metadata and water rights specific information
(define-map token-metadata uint {
    location: (string-ascii 100),
    volume-gallons: uint,
    issue-date: uint,
    expiry-date: uint,
    water-source: (string-ascii 50),
    usage-type: (string-ascii 30),
    regulatory-authority: (string-ascii 50),
    transferable: bool
})

;; Token ownership tracking
(define-map token-ownership uint {
    owner: principal,
    balance: uint,
    last-transfer: uint,
    locked: bool
})

;; User balance tracking
(define-map balances principal uint)

;; Transfer approvals (for marketplace functionality)
(define-map approvals {
    owner: principal,
    spender: principal
} uint)

;; Transaction history
(define-map transfer-history uint {
    from: (optional principal),
    to: principal,
    amount: uint,
    timestamp: uint,
    token-id: uint,
    transaction-type: (string-ascii 20)
})

;; Authorized minters (water authorities, etc.)
(define-map authorized-minters principal bool)

;; Water rights registry
(define-map water-rights-registry principal {
    total-allocated: uint,
    active-tokens: (list 50 uint),
    registration-date: uint,
    status: (string-ascii 20)
})

;; Transfer counter for history tracking
(define-data-var transfer-counter uint u0)

;; Private Functions

;; Check if token has expired
(define-private (is-token-expired (token-id uint))
    (match (map-get? token-metadata token-id)
        metadata 
        (> block-height (get expiry-date metadata))
        true
    )
)

;; Validate transfer conditions
(define-private (can-transfer (token-id uint) (from principal) (to principal) (amount uint))
    (let (
        (metadata (unwrap! (map-get? token-metadata token-id) false))
        (ownership (unwrap! (map-get? token-ownership token-id) false))
        (from-balance (default-to u0 (map-get? balances from)))
    )
        (and 
            (not (var-get contract-paused))
            (>= from-balance amount)
            (get transferable metadata)
            (not (get locked ownership))
            (not (is-token-expired token-id))
        )
    )
)

;; Update user registry after token operations
(define-private (update-user-registry (user principal) (token-id uint) (operation (string-ascii 10)))
    (let (
        (current-registry (default-to 
            { total-allocated: u0, active-tokens: (list), registration-date: block-height, status: "active" }
            (map-get? water-rights-registry user)
        ))
        (token-meta (unwrap-panic (map-get? token-metadata token-id)))
    )
        (if (is-eq operation "add")
            ;; Add token to user's registry
            (map-set water-rights-registry user 
                (merge current-registry {
                    total-allocated: (+ (get total-allocated current-registry) (get volume-gallons token-meta)),
                    active-tokens: (unwrap-panic (as-max-len? (append (get active-tokens current-registry) token-id) u50))
                })
            )
            ;; Remove token from user's registry
            (map-set water-rights-registry user 
                (merge current-registry {
                    total-allocated: (- (get total-allocated current-registry) (get volume-gallons token-meta)),
                    active-tokens: (filter not-target-token (get active-tokens current-registry))
                })
            )
        )
        (ok true)
    )
)

;; Helper function for filtering tokens
(define-private (not-target-token (id uint))
    true ;; Simplified for demo - would need actual filtering logic
)

;; SIP-010 Functions

;; Get token name
(define-read-only (get-name)
    (ok TOKEN_NAME)
)

;; Get token symbol
(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

;; Get total supply
(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

;; Get token URI (metadata)
(define-read-only (get-token-uri)
    (ok (some "https://api.water-rights.io/metadata"))
)

;; Get balance of user
(define-read-only (get-balance (who principal))
    (ok (default-to u0 (map-get? balances who)))
)

;; Transfer tokens
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        (asserts! (or (is-eq tx-sender from) (is-eq contract-caller from)) ERR_UNAUTHORIZED)
        (asserts! (not (var-get contract-paused)) ERR_TRANSFER_RESTRICTED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (is-eq from to)) ERR_INVALID_RECIPIENT)
        
        (let (
            (from-balance (default-to u0 (map-get? balances from)))
            (to-balance (default-to u0 (map-get? balances to)))
            (transfer-id (+ (var-get transfer-counter) u1))
        )
            (asserts! (>= from-balance amount) ERR_INSUFFICIENT_BALANCE)
            
            ;; Update balances
            (map-set balances from (- from-balance amount))
            (map-set balances to (+ to-balance amount))
            
            ;; Record transfer history
            (map-set transfer-history transfer-id {
                from: (some from),
                to: to,
                amount: amount,
                timestamp: block-height,
                token-id: u0, ;; General transfer, not specific token
                transaction-type: "transfer"
            })
            
            (var-set transfer-counter transfer-id)
            
            ;; Print transfer event
            (print {
                type: "transfer",
                from: from,
                to: to,
                amount: amount,
                memo: memo
            })
            
            (ok true)
        )
    )
)

;; Public Functions for Water Rights Management

;; Mint new water rights tokens
(define-public (mint-water-rights 
    (recipient principal)
    (amount uint)
    (location (string-ascii 100))
    (volume-gallons uint)
    (expiry-days uint)
    (water-source (string-ascii 50))
    (usage-type (string-ascii 30))
)
    (let (
        (token-id (var-get next-token-id))
        (expiry-date (+ block-height expiry-days))
        (current-supply (var-get total-supply))
    )
        (asserts! (default-to false (map-get? authorized-minters tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> volume-gallons u0) ERR_INVALID_AMOUNT)
        (asserts! (<= (+ current-supply amount) MAX_SUPPLY) ERR_MAX_SUPPLY_EXCEEDED)
        
        ;; Create token metadata
        (map-set token-metadata token-id {
            location: location,
            volume-gallons: volume-gallons,
            issue-date: block-height,
            expiry-date: expiry-date,
            water-source: water-source,
            usage-type: usage-type,
            regulatory-authority: "Water Authority",
            transferable: true
        })
        
        ;; Create token ownership record
        (map-set token-ownership token-id {
            owner: recipient,
            balance: amount,
            last-transfer: block-height,
            locked: false
        })
        
        ;; Update recipient balance
        (let ((current-balance (default-to u0 (map-get? balances recipient))))
            (map-set balances recipient (+ current-balance amount))
        )
        
        ;; Update user registry
        (unwrap-panic (update-user-registry recipient token-id "add"))
        
        ;; Record minting transaction
        (let ((transfer-id (+ (var-get transfer-counter) u1)))
            (map-set transfer-history transfer-id {
                from: none,
                to: recipient,
                amount: amount,
                timestamp: block-height,
                token-id: token-id,
                transaction-type: "mint"
            })
            (var-set transfer-counter transfer-id)
        )
        
        ;; Update contract state
        (var-set total-supply (+ current-supply amount))
        (var-set next-token-id (+ token-id u1))
        
        (print {
            type: "mint",
            recipient: recipient,
            token-id: token-id,
            amount: amount,
            volume: volume-gallons
        })
        
        (ok token-id)
    )
)

;; Add authorized minter
(define-public (add-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set authorized-minters minter true)
        (ok true)
    )
)

;; Remove authorized minter
(define-public (remove-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete authorized-minters minter)
        (ok true)
    )
)

;; Lock/unlock token for transfers
(define-public (set-token-lock (token-id uint) (locked bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (match (map-get? token-ownership token-id)
            ownership
            (begin
                (map-set token-ownership token-id (merge ownership { locked: locked }))
                (ok true)
            )
            ERR_TOKEN_NOT_FOUND
        )
    )
)

;; Pause/unpause contract
(define-public (set-contract-pause (paused bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused paused)
        (ok true)
    )
)

;; Read-only Functions

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
    (map-get? token-metadata token-id)
)

;; Get token ownership info
(define-read-only (get-token-ownership (token-id uint))
    (map-get? token-ownership token-id)
)

;; Get user's water rights registry
(define-read-only (get-user-registry (user principal))
    (map-get? water-rights-registry user)
)

;; Get transfer history
(define-read-only (get-transfer-history (transfer-id uint))
    (map-get? transfer-history transfer-id)
)

;; Check if user is authorized minter
(define-read-only (is-authorized-minter (minter principal))
    (default-to false (map-get? authorized-minters minter))
)

;; Get contract status
(define-read-only (get-contract-info)
    {
        total-supply: (var-get total-supply),
        next-token-id: (var-get next-token-id),
        paused: (var-get contract-paused),
        max-supply: MAX_SUPPLY
    }
)

