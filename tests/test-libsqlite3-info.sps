#!r6rs
;;; The suite for (chez-sqlite3 private libsqlite3-info): the report a loaded
;;; libsqlite3 gives of itself (ADR-0002, decision 4).
;;;
;;;   - each accessor answers its own field (every field differs);
;;;   - each accessor refuses anything but a report, with an assertion
;;;     violation from the accessor naming the value by its kind, never the
;;;     value: a string holding a secret is never printed (ADR-0013,
;;;     decision 7);
;;;   - the record is opaque, so record-rtd refuses a report and no one can
;;;     rebuild one from its type;
;;;   - the constructor is private, built by native alone, and checks
;;;     nothing, so it answers what it was given.
;;;
;;; "Sealed" cannot be held from here: an opaque record's type is out of
;;; reach, so nothing can name it as a parent (the mutation log says so).
;;;
;;; SRFI-64 makes #f of a raise in the actual expression, so no expected
;;; value here is #f: every refusal is compared against a no-raise sentinel.
(import (rnrs)
        (rnrs records inspection)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private libsqlite3-info))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) (quote (fail xpass)))
        (display "  expected: ")
        (write (test-result-ref r (quote expected-value)))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r (quote actual-value)))
        (newline)))))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO MESSAGE IRRITANTS), (other TEXT)
;; for any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-message e)
                   (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; Every field differs from every other.
(define info
  (make-libsqlite3-info "/r/path/libsqlite3.so.0" 'guix-home "3.99.0-r" 3099000
                        "2099-01-01 00:00:00 reportsourceid"))

(define secret "Pr0xyS3cr3t")

(define accessors
  (list (cons 'libsqlite3-info-path libsqlite3-info-path)
        (cons 'libsqlite3-info-source libsqlite3-info-source)
        (cons 'libsqlite3-info-version libsqlite3-info-version)
        (cons 'libsqlite3-info-version-number libsqlite3-info-version-number)
        (cons 'libsqlite3-info-source-id libsqlite3-info-source-id)))

(test-begin "libsqlite3-info")

(test-equal "a report is a libsqlite3-info?"
  #t
  (libsqlite3-info? info))

(test-equal "each accessor answers its own field"
  '("/r/path/libsqlite3.so.0" guix-home "3.99.0-r" 3099000 "2099-01-01 00:00:00 reportsourceid")
  (list (libsqlite3-info-path info) (libsqlite3-info-source info) (libsqlite3-info-version info)
        (libsqlite3-info-version-number info) (libsqlite3-info-source-id info)))

(test-equal "libsqlite3-info? is false for everything else, and raises nothing"
  '(#f #f #f #f #f #f #f)
  (map libsqlite3-info? (list secret 5 #f '() '(1 2) (vector 1 2) 'libsqlite3-info)))

;; Not a report: a string holding a secret, a number, #f, a list, a vector,
;; and a list of the report's own fields. Each accessor's refusal names the
;; value by its kind, or as itself when it holds no text.
(test-equal "every accessor refuses a string by its kind, naming the accessor, not the string"
  (map (lambda (a)
         (list 'assertion-violation (car a) "not a libsqlite3-info" '((kind string))))
       accessors)
  (map (lambda (a) (raised (lambda () ((cdr a) secret)))) accessors))

(test-equal "every accessor refuses a number, #f, a list, a vector, and the report's fields as a list"
  (map (lambda (a)
         (list (list 'assertion-violation (car a) "not a libsqlite3-info" '(5))
               (list 'assertion-violation (car a) "not a libsqlite3-info" '(#f))
               (list 'assertion-violation (car a) "not a libsqlite3-info" '((kind list)))
               (list 'assertion-violation (car a) "not a libsqlite3-info" '((kind vector)))
               (list 'assertion-violation (car a) "not a libsqlite3-info" '((kind list)))))
       accessors)
  (map (lambda (a)
         (map (lambda (v) (raised (lambda () ((cdr a) v))))
              (list 5 #f (list secret) (vector secret)
                    (list "/r/path/libsqlite3.so.0" 'guix-home "3.99.0-r" 3099000 "x"))))
       accessors))

(test-equal "no accessor prints the secret it refused, by write, display or display-condition"
  (map (lambda (a) 'absent) accessors)
  (map (lambda (a)
         (let ((text (guard (e (#t (describe e)))
                       ((cdr a) secret)
                       'no-raise)))
           (cond ((eq? text 'no-raise) 'no-raise)
                 ((contains? text secret) 'printed)
                 (else 'absent))))
       accessors))

;; Chez's own check of a record accessor named what it refused. This row
;; guards the opposite: that the refusal is ours, from the accessor.
(test-equal "an accessor of another record type's value refuses it too"
  (map (lambda (a) (list 'assertion-violation (car a) "not a libsqlite3-info" '((kind other))))
       accessors)
  (map (lambda (a) (raised (lambda () ((cdr a) (make-eq-hashtable))))) accessors))

;; A record that record-rtd opens can be rebuilt from its type: one holding
;; any path, version and source id, answering libsqlite3-info? true. Opaque,
;; it raises instead.
(test-equal "the report is opaque: record-rtd refuses it, and record? says it is no record"
  '((assertion-violation record-rtd) #f)
  (list (guard (e ((and (assertion-violation? e) (who-condition? e))
                   (list 'assertion-violation (condition-who e)))
                  (#t (list 'other-raise (describe e))))
          (list 'no-raise (record-type-name (record-rtd info))))
        (record? info)))

(test-equal "the constructor is unchecked: it answers whatever it was given, field for field"
  '(1 two "three" (4) #f)
  (let ((odd (make-libsqlite3-info 1 'two "three" '(4) #f)))
    (list (libsqlite3-info-path odd) (libsqlite3-info-source odd) (libsqlite3-info-version odd)
          (libsqlite3-info-version-number odd) (libsqlite3-info-source-id odd))))

(test-end "libsqlite3-info")

(exit (suite-exit-status runner))
