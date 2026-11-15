#!r6rs
;;; M2 slice 1: dumps utf8-ill-formed-offset's answer for every 1- and 2-byte
;;; input and for the 3- and 4-byte range edges (min-1, min, max, max+1 of
;;; every position of every row of Unicode's Table 3-7, the other bytes at
;;; their range's mid), one line each: the bytes in hex, a space, then the
;;; offset or "ok". utf8-check.py compares the file with Python's own decoder.
;;; The container may have no python3, so this runs there and the comparison
;;; on the host.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs \
;;;      --program .plans/research/m2-slice-1/utf8-dump.sps build/utf8-dump.txt'
(import (rnrs)
        (chez-sqlite3 private utf8))

(define rows
  '(((#xe0 . #xe0) (#xa0 . #xbf) (#x80 . #xbf))
    ((#xe1 . #xec) (#x80 . #xbf) (#x80 . #xbf))
    ((#xed . #xed) (#x80 . #x9f) (#x80 . #xbf))
    ((#xee . #xef) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf0 . #xf0) (#x90 . #xbf) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf1 . #xf3) (#x80 . #xbf) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf4 . #xf4) (#x80 . #x8f) (#x80 . #xbf) (#x80 . #xbf))
    ((#xc2 . #xdf) (#x80 . #xbf))))

(define (hex2 b) (string-append (if (< b 16) "0" "") (number->string b 16)))

(define (line port bytes)
  (let ((o (utf8-ill-formed-offset (u8-list->bytevector bytes))))
    (for-each (lambda (b) (put-string port (hex2 b))) bytes)
    (put-string port (string-append " " (if o (number->string o) "ok") "\n"))))

(define (edge-lists row)
  (let ((mids (map (lambda (r) (div (+ (car r) (cdr r)) 2)) row)))
    (let loop ((p 0) (acc '()))
      (if (= p (length row))
          (reverse acc)
          (let* ((r (list-ref row p))
                 (vs (filter (lambda (v) (and (>= v 0) (<= v 255)))
                             (list (- (car r) 1) (car r) (cdr r) (+ (cdr r) 1)))))
            (loop (+ p 1)
                  (append (reverse
                           (map (lambda (v)
                                  (let fill ((k 0) (ms mids))
                                    (if (null? ms)
                                        '()
                                        (cons (if (= k p) v (car ms)) (fill (+ k 1) (cdr ms))))))
                                vs))
                          acc)))))))

(let ((port (open-file-output-port (cadr (command-line)) (file-options no-fail)
                                   (buffer-mode block) (native-transcoder))))
  (do ((a 0 (+ a 1))) ((= a 256)) (line port (list a)))
  (do ((a 0 (+ a 1))) ((= a 256))
    (do ((b 0 (+ b 1))) ((= b 256)) (line port (list a b))))
  (for-each (lambda (row) (for-each (lambda (bytes) (line port bytes)) (edge-lists row))) rows)
  (close-port port))
