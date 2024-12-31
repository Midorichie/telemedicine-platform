;; contracts/patient-records.clar
;; Manages patient medical records and history

(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_RECORD (err u2))
(define-constant ERR_RECORD_NOT_FOUND (err u3))
(define-constant ERR_INVALID_ACCESS_REQUEST (err u4))
(define-constant ERR_INVALID_BLOOD_TYPE (err u5))

;; Valid blood types constant
(define-constant VALID_BLOOD_TYPES (list 
    "A+ "  ;; Padded to match length
    "A- "
    "B+ "
    "B- "
    "O+ "
    "O- "
    "AB+"
    "AB-"
))

;; Data Maps
(define-map patient-medical-records
    { patient: principal }
    {
        records-hash: (buff 32),
        last-updated: uint,
        emergency-contact: (optional principal),
        allergies: (string-ascii 500),
        blood-type: (string-ascii 3),
        created-at: uint,
        access-log: (list 50 principal)
    }
)

(define-map access-permissions
    { patient: principal, granted-to: principal }
    {
        granted-at: uint,
        expires-at: uint,
        access-type: (string-ascii 20)  ;; "READ" or "WRITE"
    }
)

;; Enhanced validation functions
(define-private (validate-principal (user principal))
    (not (is-eq user 'SP000000000000000000002Q6VF78)))

(define-private (validate-hash (hash (buff 32)))
    (is-eq (len hash) u32))

(define-private (validate-allergies (allergies (string-ascii 500)))
    (and 
        (>= (len allergies) u1)
        (<= (len allergies) u500)))

(define-private (validate-duration (duration uint))
    (<= duration u52560000)) ;; Max duration ~1 year in blocks

(define-private (is-valid-blood-type (blood-type (string-ascii 3)))
    (is-some (index-of VALID_BLOOD_TYPES blood-type))
)

(define-private (is-valid-access-type (access-type (string-ascii 20)))
    (or 
        (is-eq access-type "READ          ")  ;; Padded to match length
        (is-eq access-type "WRITE         ")  ;; Padded to match length
    )
)

;; Public Functions
(define-public (create-medical-record 
    (records-hash (buff 32))
    (allergies (string-ascii 500))
    (blood-type (string-ascii 3)))
    (let ((caller tx-sender))
        (asserts! (validate-principal caller) ERR_INVALID_RECORD)
        (asserts! (validate-hash records-hash) ERR_INVALID_RECORD)
        (asserts! (validate-allergies allergies) ERR_INVALID_RECORD)
        (asserts! (is-valid-blood-type blood-type) ERR_INVALID_RECORD)
        (ok (map-set patient-medical-records
            { patient: caller }
            {
                records-hash: records-hash,
                last-updated: block-height,
                emergency-contact: none,
                allergies: allergies,
                blood-type: blood-type,
                created-at: block-height,
                access-log: (list)
            }
        ))
    )
)

(define-public (update-medical-record
    (patient principal)
    (new-records-hash (buff 32)))
    (let ((caller tx-sender))
        (asserts! (validate-principal patient) ERR_INVALID_RECORD)
        (asserts! (validate-hash new-records-hash) ERR_INVALID_RECORD)
        (asserts! (or 
            (is-eq caller patient)
            (has-write-access caller patient)) 
            ERR_UNAUTHORIZED)
        
        (match (map-get? patient-medical-records { patient: patient })
            record (ok (map-set patient-medical-records
                { patient: patient }
                (merge record {
                    records-hash: new-records-hash,
                    last-updated: block-height,
                    access-log: (unwrap! 
                        (as-max-len? 
                            (append (get access-log record) caller) 
                            u50)
                        ERR_INVALID_RECORD)
                })
            ))
            ERR_RECORD_NOT_FOUND)
    )
)

(define-public (grant-access
    (granted-to principal)
    (access-type (string-ascii 20))
    (duration uint))
    (let ((caller tx-sender))
        (asserts! (validate-principal granted-to) ERR_INVALID_ACCESS_REQUEST)
        (asserts! (validate-duration duration) ERR_INVALID_ACCESS_REQUEST)
        (asserts! (is-valid-access-type access-type) ERR_INVALID_ACCESS_REQUEST)
        (ok (map-set access-permissions
            { patient: caller, granted-to: granted-to }
            {
                granted-at: block-height,
                expires-at: (+ block-height duration),
                access-type: access-type
            }
        ))
    )
)

;; Read Only Functions
(define-read-only (get-medical-record (patient principal))
    (let ((caller tx-sender))
        (match (map-get? patient-medical-records { patient: patient })
            record (if (or 
                        (is-eq caller patient)
                        (has-read-access caller patient))
                    (ok record)
                    (err ERR_UNAUTHORIZED))
            (err ERR_RECORD_NOT_FOUND))
    )
)

;; Private Helper Functions
(define-private (has-read-access (accessor principal) (patient principal))
    (match (map-get? access-permissions 
        { patient: patient, granted-to: accessor })
        permission (and
            (< block-height (get expires-at permission))
            (or
                (is-eq (get access-type permission) "READ          ")
                (is-eq (get access-type permission) "WRITE         ")))
        false)
)

(define-private (has-write-access (accessor principal) (patient principal))
    (match (map-get? access-permissions 
        { patient: patient, granted-to: accessor })
        permission (and
            (< block-height (get expires-at permission))
            (is-eq (get access-type permission) "WRITE         "))
        false)
)
