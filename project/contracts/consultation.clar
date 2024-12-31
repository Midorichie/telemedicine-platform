;; contracts/consultation.clar
;; Handles consultation sessions between patients and doctors

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_STATUS (err u2))
(define-constant ERR_INVALID_FEE (err u3))
(define-constant ERR_UNVERIFIED_DOCTOR (err u4))
(define-constant ERR_INVALID_SPECIALIZATION (err u5))

;; Constants
(define-data-var min-consultation-fee uint u100000) ;; in microSTX
(define-constant MAX_CONSULTATION_FEE u1000000000) ;; 1000 STX max fee
(define-constant VALID_SPECIALIZATIONS (list 
    "General Practice"
    "Pediatrics    "  ;; Padded to 16 characters
    "Cardiology   "   ;; Padded to 16 characters
    "Dermatology  "   ;; Padded to 16 characters
    "Psychiatry   "   ;; Padded to 16 characters
))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Map to track the last ID used for various counters
(define-map last-id 
    { counter: (string-ascii 20) }
    { value: uint }
)

(define-map consultations
    { consultation-id: uint }
    {
        patient: principal,
        doctor: principal,
        status: (string-ascii 20),
        fee: uint,
        timestamp: uint,
        medical-notes-hash: (buff 32)
    }
)

(define-map doctor-profiles
    { doctor: principal }
    {
        specialization: (string-ascii 16),  ;; Changed from 50 to 16
        verification-status: bool,
        consultation-count: uint
    }
)

(define-map patient-records
    { patient: principal }
    {
        medical-history-hash: (buff 32),
        consultation-count: uint,
        last-consultation: uint
    }
)

;; Administrative functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (ok (var-set contract-owner new-owner))
    )
)

;; Initialize the consultation counter if it doesn't exist
(define-private (initialize-counter)
    (match (map-get? last-id { counter: "consultation" })
        success true
        (map-set last-id 
            { counter: "consultation" }
            { value: u0 }
        )
    )
)

;; Validation functions
(define-private (is-valid-specialization (spec (string-ascii 16)))  ;; Changed from 50 to 16
    (is-some (index-of VALID_SPECIALIZATIONS spec))
)

(define-private (is-valid-fee (fee uint))
    (and 
        (>= fee (var-get min-consultation-fee))
        (<= fee MAX_CONSULTATION_FEE)
    )
)

(define-private (is-verified-doctor (doctor principal))
    (match (map-get? doctor-profiles { doctor: doctor })
        profile (get verification-status profile)
        false
    )
)

(define-public (register-doctor 
    (specialization (string-ascii 16)))  ;; Changed from 50 to 16
    (let
        ((caller tx-sender))
        (asserts! (is-valid-specialization specialization) ERR_INVALID_SPECIALIZATION)
        (ok (map-set doctor-profiles
            { doctor: caller }
            {
                specialization: specialization,
                verification-status: false,
                consultation-count: u0
            }
        ))
    )
)

(define-public (schedule-consultation 
    (doctor principal)
    (fee uint))
    (let
        ((caller tx-sender))
        ;; Validate inputs
        (asserts! (is-valid-fee fee) ERR_INVALID_FEE)
        (asserts! (is-verified-doctor doctor) ERR_UNVERIFIED_DOCTOR)
        
        ;; Process consultation
        (let ((consultation-id (get-next-consultation-id)))
            (try! (stx-transfer? fee caller doctor))
            (ok (map-set consultations
                { consultation-id: consultation-id }
                {
                    patient: caller,
                    doctor: doctor,
                    status: "SCHEDULED",
                    fee: fee,
                    timestamp: block-height,
                    medical-notes-hash: 0x00
                }
            ))
        )
    )
)

;; Admin function to verify doctors
(define-public (verify-doctor (doctor principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (match (map-get? doctor-profiles { doctor: doctor })
            profile (ok (map-set doctor-profiles
                { doctor: doctor }
                (merge profile { verification-status: true })
            ))
            ERR_UNAUTHORIZED
        )
    )
)

(define-read-only (get-consultation 
    (consultation-id uint))
    (map-get? consultations { consultation-id: consultation-id })
)

;; Private functions
(define-private (get-next-consultation-id)
    (let
        ((current-id (default-to { value: u0 } 
            (map-get? last-id { counter: "consultation" }))))
        (begin
            (map-set last-id 
                { counter: "consultation" }
                { value: (+ (get value current-id) u1) }
            )
            (+ (get value current-id) u1)
        )
    )
)

;; Initialize counter on contract deployment
(initialize-counter)
