#!r6rs
;;; M2 slice 1: what the strict decoder costs against Chez's utf8->string
;;; (plan section 7: it decides whether TEXT is checked byte by byte or in
;;; wider reads). Times, each as the median of 5 runs in ms:
;;;
;;;   - 1 MiB of ASCII (1,048,576 bytes), one call;
;;;   - about 1 MiB of mixed 2-, 3- and 4-byte text (1,048,572 bytes of
;;;     U+00E9, U+20AC and U+1D11E repeated), one call;
;;;   - 100,000 values of 16 bytes (ASCII), one call each.
;;;
;;; strict-utf8->string is utf8-ill-formed-offset, a byte-by-byte check, then
;;; utf8->string, so the ratio is the check's cost on top of the decode.
;;; real-time counts whole ms, so each run repeats the call 20 times (10 for the
;;; 100,000 values) and the table reports ms per call, a run's total divided.
;;;
;;; Run in the container, not under Valgrind:
;;;
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs \
;;;      --program .plans/research/m2-slice-1/utf8-cost.sps'
(import (rnrs)
        (only (chezscheme) real-time printf collect)
        (chez-sqlite3 private utf8))

;; median : (Listof Real) -> Real
(define (median xs)
  (list-ref (list-sort < xs) (div (length xs) 2)))

;; time-ms : (-> Any) -> Natural
;; Real time of one THUNK call in ms, after a collection.
(define (time-ms thunk)
  (collect)
  (let* ((start (real-time))
         (r (thunk))
         (end (real-time)))
    (- end start)))

;; repeated : Natural (-> Any) -> (-> Any)
(define (repeated n thunk)
  (lambda () (let loop ((i 0)) (when (< i n) (thunk) (loop (+ i 1))))))

;; median-of-5 : Natural (-> Any) -> Real
;; The median, over 5 runs of N calls, of ms per call.
(define (median-of-5 n thunk)
  (/ (median (map (lambda (i) (time-ms (repeated n thunk))) '(1 2 3 4 5))) n 1.0))

(define ascii (make-bytevector 1048576 97))

(define mixed
  (string->utf8
   (let loop ((n 116508) (acc '()))
     (if (= n 0)
         (apply string-append acc)
         (loop (- n 1) (cons "\xe9;\x20ac;\x1d11e;" acc))))))

(define values-16
  (let loop ((i 0) (acc '()))
    (if (= i 100000)
        (list->vector acc)
        (loop (+ i 1)
              (cons (string->utf8 (string-append "value-"
                                                 (let ((s (number->string (+ 1000000000 i))))
                                                   (substring s 0 10))))
                    acc)))))

(define (decode-all decode)
  (lambda ()
    (let loop ((i 0))
      (when (< i 100000)
        (decode (vector-ref values-16 i))
        (loop (+ i 1))))))

(printf "ASCII ~a bytes, mixed ~a bytes, values ~a bytes each\n"
        (bytevector-length ascii) (bytevector-length mixed)
        (bytevector-length (vector-ref values-16 0)))

(for-each
 (lambda (row)
   (let* ((n (cadddr row))
          (plain (median-of-5 n (cadr row)))
          (strict (median-of-5 n (caddr row))))
     (printf "~a: utf8->string ~a ms, strict-utf8->string ~a ms, ratio ~a\n"
             (car row) plain strict
             (if (= plain 0) "n/a" (/ (round (* 100 (/ strict plain))) 100.0)))))
 (list (list "1 MiB ASCII" (lambda () (utf8->string ascii)) (lambda () (strict-utf8->string ascii)) 20)
       (list "1 MiB mixed 2-, 3- and 4-byte" (lambda () (utf8->string mixed))
             (lambda () (strict-utf8->string mixed)) 20)
       (list "100,000 values of 16 bytes" (decode-all utf8->string)
             (decode-all strict-utf8->string) 10)))
