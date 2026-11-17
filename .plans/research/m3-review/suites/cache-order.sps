#!r6rs
;;; Probe: two rows of tests/test-statement-cache.sps as they stood at
;;; e590fdc, each ending in one call whose arguments are check-outs, run
;;; compiled and through interpret, which Chez is free to order otherwise.
;;; Run it against the real table and against a planted one: its verdict on
;;; a row is the row's verdict there. Run from a tree's root:
;;;   $CHEZ --libdirs src:tests:build/scheme-libs --program PROBE
(import (rnrs) (rnrs eval) (only (chezscheme) interpret)
        (chez-sqlite3 private statement-cache))

(define env (environment '(rnrs) '(chez-sqlite3 private statement-cache)))

;; The near-spellings row's expression, its check-outs the arguments of one
;; list.
(define near
  '(let* ((c (make-statement-cache 8)) (long (make-string 5000 #\a)))
     (statement-cache-return! c "" "e") (statement-cache-return! c "a\x0;b" "nul")
     (statement-cache-return! c long "long") (statement-cache-return! c "caf\xe9;" "uni")
     (list (statement-cache-check-out! c "") (statement-cache-check-out! c (string-copy "a\x0;b"))
           (statement-cache-check-out! c (string-copy long))
           (statement-cache-check-out! c (string-copy "caf\xe9;"))
           (statement-cache-check-out! c "a") (statement-cache-check-out! c "cafe")
           (statement-cache-check-out! c (string-append (make-string 4999 #\a) "b")))))
(define near-expected '((hit "e") (hit "nul") (hit "long") (hit "uni") (miss) (miss) (miss)))

;; The capacity-1024 row's expression, its two check-outs the last
;; arguments of one list, the count read before it, as the row's let* read
;; it. Keys returned in order by a loop, as fill! does.
(define full
  '(let ((c (make-statement-cache 1024)))
     (let loop ((i 0))
       (when (< i 1025)
         (let ((k (string-append "select " (number->string i))))
           (statement-cache-return! c k k)
           (loop (+ i 1)))))
     (let ((m (statement-cache-count c)))
       (list m (statement-cache-check-out! c "select 0")
             (statement-cache-check-out! c "select 1")))))
(define full-expected '(1024 (miss) (hit "select 1")))

(define (verdict label expected got)
  (display label) (display ": ") (write got)
  (display (if (equal? got expected) "  -- the row passes" "  -- the row fails"))
  (newline))

(verdict "near spellings, compiled" near-expected (eval near env))
(verdict "near spellings, interpret" near-expected (interpret near env))
(verdict "capacity 1024, compiled" full-expected (eval full env))
(verdict "capacity 1024, interpret" full-expected (interpret full env))
