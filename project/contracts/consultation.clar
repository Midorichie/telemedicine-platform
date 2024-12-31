;; contracts/consultation.clar
;; Enhanced telemedicine consultation management contract

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_STATUS (err u2))
(define-constant ERR_INVALID_FEE (err u3))
(define-constant ERR_UNVERIFIED_DOCTOR (err u4))
(define-constant ERR_INVALID_SPECIALIZATION (err u5))
(define-constant ERR_CONSULTATION_NOT_FOUND (err u6))
(define-constant ERR_INVALID_STATE_TRANSITION (err u7))
(define-constant ERR_INSUFFICIENT_BALANCE (err u8))

;; Constants
(define-data-var min-consultation-fee uint u100000)
(define-constant MAX_CONSULTATION_FEE u1000000000)
(define-constant VALID_SPECIALIZATIONS (list 
    "General Practice "  ;; Padded to match 16 characters
    "Pediatrics     "
    "Cardiology     "
    "Dermatology    "
    "Psychiatry     "
))

;; Status constants with fixed lengths
(define-constant STATUS_SCHEDULED    "SCHEDULED       ")  ;; Padded to 15 chars
(define-constant STATUS_IN_PROGRESS  "IN_PROGRESS     ")
(define-constant STATUS_COMPLETED    "COMPLETED       ")
(define-constant STATUS_CANCELLED    "CANCELLED       ")
(define-constant VALID_STATUSES (list
    STATUS_SCHEDULED
    STATUS_IN_PROGRESS
    STATUS_COMPLETED
    STATUS_CANCELLED
))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Maps
(define-map last-id 
    { counter: (string-ascii 20) }
    { value: uint }
)

(define-map consultations
    { consultation-id: uint }
    {
        patient: principal,
        doctor: principal,
        status: (string-ascii 15),
        fee: uint,
        timestamp: uint,
        medical-notes-hash: (buff 32),
        scheduled-time: uint,
        duration-minutes: uint,
        cancellation-reason: (optional (string-ascii 50)),
        rating: (optional uint)
    }
)

(define-map doctor-profiles
    { doctor: principal }
    {
        specialization: (string-ascii 16),
        verification-status: bool,
        consultation-count: uint,
        available-slots: (list 10 uint),
        rating: uint,
        total-ratings: uint
    }
)

(define-map patient-records
    { patient: principal }
    {
        medical-history-hash: (buff 32),
        consultation-count: uint,
        last-consultation: uint,
        cancelled-count: uint,
        preferred-doctor: (optional principal)
    }
)

;; Enhanced validation functions
(define-private (validate-principal (user principal))
    (not (is-eq user 'SP000000000000000000002Q6VF78)))

(define-private (validate-hash (hash (buff 32)))
    (is-eq (len hash) u32))

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

(define-private (is-valid-status (status (string-ascii 15)))
    (is-some (index-of VALID_STATUSES status))
)

(define-private (is-available-slot (doctor principal) (slot uint))
    (match (map-get? doctor-profiles { doctor: doctor })
        profile (is-some (index-of (get available-slots profile) slot))
        false
    )
)

;; Modified slot filtering function
(define-private (filter-out-scheduled-slot (slots (list 10 uint)) (target-slot uint))
    (fold (lambda (slot acc)
            (if (is-eq slot target-slot)
                acc
                (cons slot acc)))
          (list-reverse slots) ;; Reverse the slots for consistent order
          (list)))

;; Administrative functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (validate-principal new-owner) ERR_UNAUTHORIZED)
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

;; Enhanced consultation scheduling with time slots
(define-public (schedule-consultation-with-time
    (doctor principal)
    (fee uint)
    (scheduled-time uint)
    (duration uint))
    (let
        ((caller tx-sender))
        (asserts! (validate-principal doctor) ERR_UNVERIFIED_DOCTOR)
        (asserts! (is-valid-fee fee) ERR_INVALID_FEE)
        (asserts! (is-verified-doctor doctor) ERR_UNVERIFIED_DOCTOR)
        (asserts! (is-available-slot doctor scheduled-time) ERR_INVALID_STATE_TRANSITION)
        
        (let ((consultation-id (get-next-consultation-id)))
            (try! (stx-transfer? fee caller doctor))
            (match (map-get? doctor-profiles { doctor: doctor })
                profile (map-set doctor-profiles
                    { doctor: doctor }
                    (merge profile {
                        consultation-count: (+ (get consultation-count profile) u1),
                        available-slots: (filter-out-scheduled-slot 
                            (get available-slots profile)
                            scheduled-time)
                    }))
                ERR_UNVERIFIED_DOCTOR)
            
            (ok (map-set consultations
                { consultation-id: consultation-id }
                {
                    patient: caller,
                    doctor: doctor,
                    status: STATUS_SCHEDULED,
                    fee: fee,
                    timestamp: block-height,
                    medical-notes-hash: 0x00,
                    scheduled-time: scheduled-time,
                    duration-minutes: duration,
                    cancellation-reason: none,
                    rating: none
                }
            ))
        )
    )
)

;; Enhanced consultation management functions
(define-public (start-consultation (consultation-id uint))
    (let ((consultation (unwrap! (get-consultation consultation-id) ERR_CONSULTATION_NOT_FOUND)))
        (asserts! (is-eq (get doctor consultation) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status consultation) STATUS_SCHEDULED) ERR_INVALID_STATE_TRANSITION)
        (ok (map-set consultations
            { consultation-id: consultation-id }
            (merge consultation { status: STATUS_IN_PROGRESS })
        ))
    )
)

(define-public (complete-consultation 
    (consultation-id uint)
    (medical-notes-hash (buff 32)))
    (let ((consultation (unwrap! (get-consultation consultation-id) ERR_CONSULTATION_NOT_FOUND)))
        (asserts! (is-eq (get doctor consultation) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (validate-hash medical-notes-hash) ERR_INVALID_STATUS)
        (asserts! (is-eq (get status consultation) STATUS_IN_PROGRESS) ERR_INVALID_STATE_TRANSITION)
        (ok (map-set consultations
            { consultation-id: consultation-id }
            (merge consultation {
                status: STATUS_COMPLETED,
                medical-notes-hash: medical-notes-hash
            })
        ))
    )
)

;; Rating system
(define-public (rate-consultation 
    (consultation-id uint)
    (rating uint))
    (let (
        (consultation (unwrap! (get-consultation consultation-id) ERR_CONSULTATION_NOT_FOUND))
        (doctor (get doctor consultation)))
        (asserts! (is-eq (get patient consultation) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status consultation) STATUS_COMPLETED) ERR_INVALID_STATE_TRANSITION)
        (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_FEE)
        
        (match (map-get? doctor-profiles { doctor: doctor })
            profile (map-set doctor-profiles
                { doctor: doctor }
                (merge profile {
                    rating: (/ (+ (* (get rating profile) 
                                   (get total-ratings profile)) 
                                rating)
                             (+ (get total-ratings profile) u1)),
                    total-ratings: (+ (get total-ratings profile) u1)
                }))
            ERR_UNVERIFIED_DOCTOR)
        
        (ok (map-set consultations
            { consultation-id: consultation-id }
            (merge consultation { rating: (some rating) })
        ))
    )
)

;; Read-only functions
(define-read-only (get-consultation (consultation-id uint))
    (map-get? consultations { consultation-id: consultation-id })
)

(define-read-only (get-doctor-consultations (doctor principal))
    (map-get? doctor-profiles { doctor: doctor })
)

(define-read-only (get-patient-consultations (patient principal))
    (map-get? patient-records { patient: patient })
)

;; Private helper functions
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
