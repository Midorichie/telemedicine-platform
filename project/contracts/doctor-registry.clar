;; contracts/doctor-registry.clar
;; Manages doctor verification and credentials

(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_CREDENTIALS (err u2))
(define-constant ERR_DOCTOR_NOT_FOUND (err u3))
(define-constant ERR_ALREADY_REGISTERED (err u4))
(define-constant ERR_INVALID_YEARS_EXPERIENCE (err u5))

;; Constants for validation
(define-constant VALID_SPECIALIZATIONS (list 
    "General Practice"
    "Pediatrics     "  ;; Padded to match length
    "Cardiology    "   ;; Padded to match length
    "Dermatology   "   ;; Padded to match length
    "Psychiatry    "   ;; Padded to match length
))

(define-constant MAX_YEARS_EXPERIENCE u50)
(define-constant MIN_YEARS_EXPERIENCE u1)

;; Data Maps
(define-map doctor-credentials
    { doctor: principal }
    {
        license-number: (string-ascii 20),
        specialization: (string-ascii 16),
        verification-status: bool,
        credentials-hash: (buff 32),
        insurance-info: (string-ascii 100),
        years-experience: uint,
        hospital-affiliations: (list 5 (string-ascii 50)),
        available-hours: (list 7 (string-ascii 50)),
        created-at: uint,
        last-verified: uint
    }
)

(define-map credentials-verification
    { license-number: (string-ascii 20) }
    {
        status: bool,
        verified-by: principal,
        verification-date: uint
    }
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Enhanced validation functions
(define-private (validate-principal (user principal))
    (not (is-eq user 'SP000000000000000000002Q6VF78)))

(define-private (validate-hash (hash (buff 32)))
    (is-eq (len hash) u32))

(define-private (validate-insurance-info (info (string-ascii 100)))
    (and 
        (> (len info) u0)
        (<= (len info) u100)))

(define-private (is-valid-license-number (license-number (string-ascii 20)))
    (let ((len (len license-number)))
        (and (> len u0) (<= len u20))
    )
)

(define-private (is-valid-specialization (spec (string-ascii 16)))
    (is-some (index-of VALID_SPECIALIZATIONS spec))
)

(define-private (is-valid-years-experience (years uint))
    (and 
        (>= years MIN_YEARS_EXPERIENCE)
        (<= years MAX_YEARS_EXPERIENCE)
    )
)

(define-private (is-valid-hospital-affiliations (affiliations (list 5 (string-ascii 50))))
    (and 
        (> (len affiliations) u0)
        (<= (len affiliations) u5)
    )
)

(define-private (is-valid-available-hours (hours (list 7 (string-ascii 50))))
    (and 
        (> (len hours) u0)
        (<= (len hours) u7)
    )
)

;; Administrative functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (validate-principal new-owner) ERR_INVALID_CREDENTIALS)
        (ok (var-set contract-owner new-owner))
    )
)

;; Public Functions
(define-public (register-doctor-credentials
    (license-number (string-ascii 20))
    (specialization (string-ascii 16))
    (credentials-hash (buff 32))
    (insurance-info (string-ascii 100))
    (years-experience uint)
    (hospital-affiliations (list 5 (string-ascii 50)))
    (available-hours (list 7 (string-ascii 50))))
    (let ((caller tx-sender))
        (asserts! (validate-principal caller) ERR_INVALID_CREDENTIALS)
        (asserts! (validate-hash credentials-hash) ERR_INVALID_CREDENTIALS)
        (asserts! (validate-insurance-info insurance-info) ERR_INVALID_CREDENTIALS)
        (asserts! (is-valid-license-number license-number) ERR_INVALID_CREDENTIALS)
        (asserts! (is-valid-specialization specialization) ERR_INVALID_CREDENTIALS)
        (asserts! (is-valid-years-experience years-experience) ERR_INVALID_YEARS_EXPERIENCE)
        (asserts! (is-valid-hospital-affiliations hospital-affiliations) ERR_INVALID_CREDENTIALS)
        (asserts! (is-valid-available-hours available-hours) ERR_INVALID_CREDENTIALS)
        (asserts! (not (is-some (map-get? doctor-credentials { doctor: caller }))) 
            ERR_ALREADY_REGISTERED)
        
        (ok (map-set doctor-credentials
            { doctor: caller }
            {
                license-number: license-number,
                specialization: specialization,
                verification-status: false,
                credentials-hash: credentials-hash,
                insurance-info: insurance-info,
                years-experience: years-experience,
                hospital-affiliations: hospital-affiliations,
                available-hours: available-hours,
                created-at: block-height,
                last-verified: u0
            }
        ))
    )
)

(define-public (verify-doctor-credentials 
    (doctor principal)
    (license-number (string-ascii 20)))
    (let ((caller tx-sender))
        (asserts! (is-eq caller (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (validate-principal doctor) ERR_INVALID_CREDENTIALS)
        (asserts! (is-valid-license-number license-number) ERR_INVALID_CREDENTIALS)
        
        (match (map-get? doctor-credentials { doctor: doctor })
            credentials 
                (begin
                    (map-set credentials-verification
                        { license-number: license-number }
                        {
                            status: true,
                            verified-by: caller,
                            verification-date: block-height
                        })
                    (ok (map-set doctor-credentials
                        { doctor: doctor }
                        (merge credentials {
                            verification-status: true,
                            last-verified: block-height
                        })
                    )))
            ERR_DOCTOR_NOT_FOUND)
    )
)

(define-public (update-available-hours
    (new-hours (list 7 (string-ascii 50))))
    (let ((caller tx-sender))
        (asserts! (is-valid-available-hours new-hours) ERR_INVALID_CREDENTIALS)
        (match (map-get? doctor-credentials { doctor: caller })
            credentials 
                (ok (map-set doctor-credentials
                    { doctor: caller }
                    (merge credentials {
                        available-hours: new-hours
                    })
                ))
            ERR_DOCTOR_NOT_FOUND)
    )
)

(define-public (update-insurance-info
    (new-insurance-info (string-ascii 100)))
    (let ((caller tx-sender))
        (asserts! (validate-insurance-info new-insurance-info) ERR_INVALID_CREDENTIALS)
        (match (map-get? doctor-credentials { doctor: caller })
            credentials 
                (ok (map-set doctor-credentials
                    { doctor: caller }
                    (merge credentials {
                        insurance-info: new-insurance-info
                    })
                ))
            ERR_DOCTOR_NOT_FOUND)
    )
)

;; Read Only Functions
(define-read-only (get-doctor-credentials (doctor principal))
    (map-get? doctor-credentials { doctor: doctor })
)

(define-read-only (verify-license
    (license-number (string-ascii 20)))
    (map-get? credentials-verification { license-number: license-number })
)

(define-read-only (is-doctor-verified (doctor principal))
    (match (map-get? doctor-credentials { doctor: doctor })
        credentials (get verification-status credentials)
        false)
)

(define-read-only (get-doctor-availability (doctor principal))
    (match (map-get? doctor-credentials { doctor: doctor })
        credentials (ok (get available-hours credentials))
        (err ERR_DOCTOR_NOT_FOUND))
)
