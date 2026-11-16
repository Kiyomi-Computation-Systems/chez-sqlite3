;; M3 slice 3, part A's probe 1: the lookaside slots ten held statements take,
;; prepared with no flags and with SQLITE_PREPARE_PERSISTENT; and the tail
;; offset sqlite3_prepare_v3 gives for each of nine short SQL texts. Uses M2's
;; internals and native's bindings, so it runs from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/lookaside-tails.sps
(import (rnrs) (rnrs eval)
        (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set!
              printf)
        (chez-sqlite3 private native)
        (chez-sqlite3 private connection)
        (chez-sqlite3 private statement))

(define db-status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int))

(define (lookaside-used db)
  (call-with-open-handle 'probe db
    (lambda (h)
      (let ((cur (foreign-alloc 8)) (hi (foreign-alloc 8)))
        (foreign-set! 'int cur 0 0) (foreign-set! 'int hi 0 0)
        (let* ((rc (db-status h 0 cur hi 0))
               (c (foreign-ref 'int cur 0)))
          (foreign-free cur) (foreign-free hi)
          (list rc c))))))

(define (raw-prepare db sql flags)
  (call-with-open-handle 'probe db
    (lambda (h)
      (call-with-c-string 'probe sql
        (lambda (c)
          (let-values (((tail st)
                        (call-with-out-pointer 'probe
                          (lambda (tslot)
                            (let-values (((rc s) (call-with-out-pointer 'probe
                                                   (lambda (sslot)
                                                     (sqlite3-prepare-v3 h c (+ 1 (bytevector-length (string->utf8 sql))) flags sslot tslot)))))
                              (list rc s))))))
            (list (car tail) (cadr tail) (- st c))))))))

(printf "version ~a\n" (eval (quote (sqlite-version)) (environment (quote (chez-sqlite3)))))
(for-each
 (lambda (flags)
   (let ((db (open-database ":memory:")))
     (printf "flags ~a: lookaside before ~a\n" flags (lookaside-used db))
     (let loop ((i 0) (held '()))
       (if (< i 10)
           (let ((r (raw-prepare db "select 1, 2 where ?1" flags)))
             (loop (+ i 1) (cons (cadr r) held)))
           (begin
             (printf "flags ~a: lookaside holding 10: ~a\n" flags (lookaside-used db))
             (for-each (lambda (s) (sqlite3-finalize s)) held)
             (printf "flags ~a: after finalize: ~a\n" flags (lookaside-used db)))))
     (close-database! db)))
 '(0 1))

;; tails
(let ((db (open-database ":memory:")))
  (for-each (lambda (sql)
              (let ((r (raw-prepare db sql 0)))
                (printf "~s: rc ~a stmt ~a tail ~a len ~a\n" sql (car r) (if (eqv? (cadr r) 0) 'null 'stmt) (caddr r)
                        (bytevector-length (string->utf8 sql)))
                (unless (eqv? (cadr r) 0) (sqlite3-finalize (cadr r)))))
            '("" ";" "select 1" "select 1;" "select 1; select 2" " -- c" ";; select 2" "select 1 -- c\n; x" "select \x3bb;; select 2"))
  (close-database! db))
