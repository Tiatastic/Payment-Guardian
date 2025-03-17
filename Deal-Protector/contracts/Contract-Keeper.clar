;; Service Agreement Smart Contract

;; Constants for agreement status tracking
(define-constant contract-owner tx-sender)
(define-constant status-pending-funding u0)
(define-constant status-in-progress u1)
(define-constant status-completed u2)
(define-constant status-cancelled u3)
(define-constant status-disputed u4)

;; Error constants
(define-constant ERR-permission-denied (err u100))
(define-constant ERR-invalid-status (err u101))
(define-constant ERR-payment-too-low (err u102))
(define-constant ERR-duplicate-agreement (err u103))
(define-constant ERR-agreement-missing (err u104))
(define-constant ERR-milestone-index-out-of-bounds (err u105))
(define-constant ERR-invalid-parameters (err u106))
(define-constant ERR-invalid-provider (err u107))
(define-constant ERR-milestone-validation-failed (err u108))

;; Data structures for tracking agreements
(define-map agreement-data
    { agreement-id: uint }
    {
        provider-principal: principal,
        client-principal: principal,
        agreement-value: uint,
        current-status: uint,
        creation-block: uint,
        completion-block: uint,
        dispute-deadline-block: uint,
        milestone-list: (list 5 {
            milestone-title: (string-utf8 100),
            milestone-fee: uint,
            milestone-status: bool
        })
    }
)

(define-map payment-vault
    { agreement-id: uint }
    { secured-funds: uint }
)

(define-map dispute-records
    { agreement-id: uint }
    {
        dispute-description: (string-utf8 200),
        dispute-creator: principal,
        dispute-outcome: (optional (string-utf8 200))
    }
)

;; Read-only functions
(define-read-only (get-agreement-info (agreement-id uint))
    (map-get? agreement-data { agreement-id: agreement-id })
)

(define-read-only (get-secured-payment (agreement-id uint))
    (default-to { secured-funds: u0 }
        (map-get? payment-vault { agreement-id: agreement-id })
    )
)

(define-read-only (get-dispute-info (agreement-id uint))
    (map-get? dispute-records { agreement-id: agreement-id })
)

;; Private helper functions
(define-private (check-authorization (agreement-id uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) false)))
        (or
            (is-eq tx-sender contract-owner)
            (is-eq tx-sender (get provider-principal agreement-info))
            (is-eq tx-sender (get client-principal agreement-info))
        )
    )
)

(define-private (is-milestone-done? (milestone {
    milestone-title: (string-utf8 100),
    milestone-fee: uint,
    milestone-status: bool
}))
    (get milestone-status milestone))

(define-private (check-all-milestones-complete (milestone-list (list 5 {
        milestone-title: (string-utf8 100),
        milestone-fee: uint,
        milestone-status: bool
    })))
    (and
        (is-milestone-done? (unwrap-panic (element-at milestone-list u0)))
        (is-milestone-done? (unwrap-panic (element-at milestone-list u1)))
        (is-milestone-done? (unwrap-panic (element-at milestone-list u2)))
        (is-milestone-done? (unwrap-panic (element-at milestone-list u3)))
        (is-milestone-done? (unwrap-panic (element-at milestone-list u4)))
    )
)

(define-private (validate-provider (provider-address principal))
    (and 
        (not (is-eq provider-address tx-sender))
        (not (is-eq provider-address contract-owner))
        (not (is-eq provider-address (as-contract tx-sender)))
    )
)

(define-private (validate-milestone-structure (milestones (list 5 {
        milestone-title: (string-utf8 100),
        milestone-fee: uint,
        milestone-status: bool
    })) 
    (total-value uint))
    (let ((total-milestone-fees (+ 
            (get milestone-fee (unwrap-panic (element-at milestones u0)))
            (get milestone-fee (unwrap-panic (element-at milestones u1)))
            (get milestone-fee (unwrap-panic (element-at milestones u2)))
            (get milestone-fee (unwrap-panic (element-at milestones u3)))
            (get milestone-fee (unwrap-panic (element-at milestones u4)))
        )))
        (and 
            (is-eq total-milestone-fees total-value)  ;; Sum of milestone fees must equal total value
            (> (len (get milestone-title (unwrap-panic (element-at milestones u0)))) u0)  ;; Validate titles
            (> (len (get milestone-title (unwrap-panic (element-at milestones u1)))) u0)
            (> (len (get milestone-title (unwrap-panic (element-at milestones u2)))) u0)
            (> (len (get milestone-title (unwrap-panic (element-at milestones u3)))) u0)
            (> (len (get milestone-title (unwrap-panic (element-at milestones u4)))) u0)
        )
    )
)

(define-private (update-milestone-completion 
    (milestone {
        milestone-title: (string-utf8 100),
        milestone-fee: uint,
        milestone-status: bool
    })
    (target-index uint)
    (current-index uint))
    {
        milestone-title: (get milestone-title milestone),
        milestone-fee: (get milestone-fee milestone),
        milestone-status: (if (is-eq current-index target-index) 
                            true 
                            (get milestone-status milestone))
    }
)

;; Public functions
(define-public (establish-service-agreement (agreement-id uint) 
                                       (provider-address principal)
                                       (total-value uint)
                                       (agreement-duration uint)
                                       (milestone-list (list 5 {
                                           milestone-title: (string-utf8 100),
                                           milestone-fee: uint,
                                           milestone-status: bool
                                       })))
    (let ((current-block-height block-height))
        (asserts! (is-none (get-agreement-info agreement-id)) ERR-duplicate-agreement)
        (asserts! (> total-value u0) ERR-payment-too-low)
        (asserts! (> agreement-duration u0) ERR-invalid-parameters)
        (asserts! (validate-provider provider-address) ERR-invalid-provider)
        (asserts! (validate-milestone-structure milestone-list total-value) ERR-milestone-validation-failed)
        
        (map-set agreement-data
            { agreement-id: agreement-id }
            {
                provider-principal: provider-address,
                client-principal: tx-sender,
                agreement-value: total-value,
                current-status: status-pending-funding,
                creation-block: current-block-height,
                completion-block: (+ current-block-height agreement-duration),
                dispute-deadline-block: (+ (+ current-block-height agreement-duration) u144), ;; ~1 day after end (assuming ~10min blocks)
                milestone-list: milestone-list
            }
        )
        
        (map-set payment-vault
            { agreement-id: agreement-id }
            { secured-funds: u0 }
        )
        
        (ok true)
    )
)

(define-public (fund-agreement (agreement-id uint) (deposit-amount uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing))
          (current-balance (get secured-funds (get-secured-payment agreement-id))))
        
        (asserts! (is-eq tx-sender (get client-principal agreement-info)) ERR-permission-denied)
        (asserts! (is-eq (get current-status agreement-info) status-pending-funding) ERR-invalid-status)
        (asserts! (> deposit-amount u0) ERR-invalid-parameters)
        
        (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
        
        (let ((updated-balance (+ current-balance deposit-amount)))
            (map-set payment-vault
                { agreement-id: agreement-id }
                { secured-funds: updated-balance }
            )
            
            (if (>= updated-balance (get agreement-value agreement-info))
                (map-set agreement-data
                    { agreement-id: agreement-id }
                    (merge agreement-info { current-status: status-in-progress })
                )
                true
            )
            
            (ok true)
        )
    )
)

(define-public (complete-milestone (agreement-id uint) (milestone-index uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing)))
        (asserts! (is-eq tx-sender (get provider-principal agreement-info)) ERR-permission-denied)
        (asserts! (is-eq (get current-status agreement-info) status-in-progress) ERR-invalid-status)
        (asserts! (< milestone-index (len (get milestone-list agreement-info))) ERR-milestone-index-out-of-bounds)
        
        (let ((milestones (get milestone-list agreement-info))
              (updated-milestones 
                (list 
                    (update-milestone-completion (unwrap-panic (element-at milestones u0)) milestone-index u0)
                    (update-milestone-completion (unwrap-panic (element-at milestones u1)) milestone-index u1)
                    (update-milestone-completion (unwrap-panic (element-at milestones u2)) milestone-index u2)
                    (update-milestone-completion (unwrap-panic (element-at milestones u3)) milestone-index u3)
                    (update-milestone-completion (unwrap-panic (element-at milestones u4)) milestone-index u4)
                )))
            
            (map-set agreement-data
                { agreement-id: agreement-id }
                (merge agreement-info { milestone-list: updated-milestones })
            )
            
            (if (check-all-milestones-complete updated-milestones)
                (map-set agreement-data
                    { agreement-id: agreement-id }
                    (merge agreement-info { 
                        current-status: status-completed,
                        milestone-list: updated-milestones 
                    })
                )
                true
            )
            
            (ok true)
        )
    )
)

(define-public (release-payment (agreement-id uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing))
          (vault-info (get-secured-payment agreement-id)))
        
        (asserts! (is-eq tx-sender (get client-principal agreement-info)) ERR-permission-denied)
        (asserts! (is-eq (get current-status agreement-info) status-completed) ERR-invalid-status)
        
        (try! (as-contract (stx-transfer? 
            (get secured-funds vault-info)
            (as-contract tx-sender)
            (get provider-principal agreement-info)
        )))
        
        (map-set payment-vault
            { agreement-id: agreement-id }
            { secured-funds: u0 }
        )
        
        (ok true)
    )
)

(define-public (file-dispute (agreement-id uint) (dispute-description (string-utf8 200)))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing)))
        (asserts! (check-authorization agreement-id) ERR-permission-denied)
        (asserts! (< block-height (get dispute-deadline-block agreement-info)) ERR-invalid-status)
        (asserts! (> (len dispute-description) u0) ERR-invalid-parameters)
        
        (map-set dispute-records
            { agreement-id: agreement-id }
            {
                dispute-description: dispute-description,
                dispute-creator: tx-sender,
                dispute-outcome: none
            }
        )
        
        (map-set agreement-data
            { agreement-id: agreement-id }
            (merge agreement-info { current-status: status-disputed })
        )
        
        (ok true)
    )
)

(define-public (arbitrate-dispute (agreement-id uint) 
                                (resolution-text (string-utf8 200))
                                (client-refund-rate uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing))
          (vault-info (get-secured-payment agreement-id)))
        
        (asserts! (is-eq tx-sender contract-owner) ERR-permission-denied)
        (asserts! (is-eq (get current-status agreement-info) status-disputed) ERR-invalid-status)
        (asserts! (<= client-refund-rate u100) ERR-invalid-parameters)
        (asserts! (> (len resolution-text) u0) ERR-invalid-parameters)
        
        (let ((client-refund (/ (* (get secured-funds vault-info) client-refund-rate) u100))
              (provider-payment (- (get secured-funds vault-info) client-refund)))
            
            ;; Process client refund
            (if (> client-refund u0)
                (try! (as-contract (stx-transfer? 
                    client-refund
                    (as-contract tx-sender)
                    (get client-principal agreement-info)
                )))
                true
            )
            
            ;; Process provider payment
            (if (> provider-payment u0)
                (try! (as-contract (stx-transfer? 
                    provider-payment
                    (as-contract tx-sender)
                    (get provider-principal agreement-info)
                )))
                true
            )
            
            ;; Update dispute resolution
            (let ((dispute-info (unwrap! (get-dispute-info agreement-id) ERR-agreement-missing)))
                (map-set dispute-records
                    { agreement-id: agreement-id }
                    (merge dispute-info { dispute-outcome: (some resolution-text) })
                )
            )
            
            ;; Clear vault and update status
            (map-set payment-vault
                { agreement-id: agreement-id }
                { secured-funds: u0 }
            )
            
            (map-set agreement-data
                { agreement-id: agreement-id }
                (merge agreement-info { current-status: status-completed })
            )
            
            (ok true)
        )
    )
)

(define-public (cancel-agreement (agreement-id uint))
    (let ((agreement-info (unwrap! (get-agreement-info agreement-id) ERR-agreement-missing))
          (vault-info (get-secured-payment agreement-id)))
        
        (asserts! (check-authorization agreement-id) ERR-permission-denied)
        (asserts! (is-eq (get current-status agreement-info) status-pending-funding) ERR-invalid-status)
        ;; Return secured funds to client
        (if (> (get secured-funds vault-info) u0)
            (try! (as-contract (stx-transfer? 
                (get secured-funds vault-info)
                (as-contract tx-sender)
                (get client-principal agreement-info)
            )))
            true
        )
        
        (map-set payment-vault
            { agreement-id: agreement-id }
            { secured-funds: u0 }
        )
        
        (map-set agreement-data
            { agreement-id: agreement-id }
            (merge agreement-info { current-status: status-cancelled })
        )
        
        (ok true)
    )
)