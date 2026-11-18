;;; fifo-double-open.sps: test-native's load FIFO row, against an opener
;;; that opens its FIFO twice, as macOS's dyld does (the M4 session's Mac
;;; run 2, PR #38: dlopen tried the path, "not a file", then tried it again,
;;; each open waiting for a writer). Linux's dlopen opens it once, so no run
;;; of the row on Linux can show that shape. A stand-in thread calls open(2)
;;; read-only TIMES times through a __collect_safe binding, closing each.
;;; With no gap between them, Linux's second open mostly found the first
;;; release's writer still open, so one release freed both, but not always:
;;; the Mac's writer had gone before dyld's second open. So each open after
;;; the first waits GAP ms, as dyld's work between its two opens did, and
;;; the release's shell has exited by then.
;;;
;;; Each release opens the FIFO for writing and closes it, as the row's
;;; collector does. One release frees a single opener and leaves a double
;;; opener waiting in its second open; releasing again, until the opener
;;; answers, frees both. Run from a worktree's root:
;;;
;;;   scripts/guix-env sh -c '$CHEZ --program .plans/research/m4-slice-2/fifo-double-open.sps'
;;;
;;; It prints one line per case: the method, the opens, the gap, what the
;;; method saw, how many opens returned, and the cleanup's release.
(import (chezscheme))

;; libc, by its name on Linux and on macOS: the first that loads.
(let loop ((names '("libc.so.6" "/usr/lib/libSystem.B.dylib")))
  (unless (null? names)
    (unless (guard (e (#t #f)) (load-shared-object (car names)) #t)
      (loop (cdr names)))))

(define c-open (foreign-procedure __collect_safe "open" (uptr int) int))
(define c-close (foreign-procedure __collect_safe "close" (int) int))

;; foreign-c-string : String -> Natural
;; S's UTF-8 bytes and a NUL, copied to foreign memory: the address, never
;; freed (a probe makes two). A __collect_safe binding takes no string.
(define (foreign-c-string s)
  (let* ((bytes (string->utf8 s))
         (n (bytevector-length bytes))
         (p (foreign-alloc (+ n 1))))
    (let loop ((i 0))
      (when (< i n)
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bytes i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p n 0)
    p))

;; wait-until : (-> Any) Natural -> (U 'satisfied 'timed-out)
;; DONE? polled every 10 ms, STEPS times at most.
(define (wait-until done? steps)
  (let loop ((n steps))
    (cond ((done?) 'satisfied)
          ((= n 0) 'timed-out)
          (else (sleep (make-time 'time-duration 10000000 0)) (loop (- n 1))))))

;; release : String -> Integer
;; The FIFO opened for writing and closed, by a shell: its exit status.
(define (release fifo)
  (system (string-append "sh -c 'exec 3<>\"$0\"' " fifo)))

;; release-until : String (-> Any) Natural -> (List Symbol Natural)
;; The row's method: a release, then up to a second for ANSWERED?, again,
;; ROUNDS releases at most.
(define (release-until fifo answered? rounds)
  (let loop ((n 1))
    (release fifo)
    (cond ((eq? (wait-until answered? 100) 'satisfied) (list 'released n))
          ((< n rounds) (loop (+ n 1)))
          (else (list 'unanswered n)))))

;; trial : String Natural Natural Symbol -> (List Symbol Natural Natural Any)
;; An opener that opens FIFO TIMES times, GAP ms between, freed by METHOD:
;; once, the old collector's, or until it answers.
(define (trial fifo times gap method)
  (let ((m (make-mutex)) (opens '()) (done #f) (path (foreign-c-string fifo)))
    (fork-thread
     (lambda ()
       (let loop ((k times))
         (when (> k 0)
           (when (< k times) (sleep (make-time 'time-duration (* gap 1000000) 0)))
           (let ((fd (c-open path 0)))
             (with-mutex m (set! opens (cons fd opens)))
             (when (>= fd 0) (c-close fd))
             (loop (- k 1)))))
       (with-mutex m (set! done #t))))
    (sleep (make-time 'time-duration 0 1))
    (let* ((seen (if (eq? method 'once)
                     (begin (release fifo)
                            (list (wait-until (lambda () (with-mutex m done)) 200)))
                     (release-until fifo (lambda () (with-mutex m done)) 5)))
           ;; A double opener left waiting by one release is freed here, so
           ;; the next trial starts with no thread on the FIFO.
           (cleanup (if (with-mutex m done)
                        'none
                        (release-until fifo (lambda () (with-mutex m done)) 5)))
           (count (with-mutex m (length opens))))
      (list method times gap seen 'opens-returned count 'cleanup cleanup))))

(let* ((dir (format "~a/fifo-double-open-~a" (or (getenv "TMPDIR") "/tmp") (random 1000000000)))
       (fifo (string-append dir "/blocking.fifo")))
  (system (string-append "mkdir " dir " && mkfifo " fifo))
  (for-each
   (lambda (case)
     (write (apply trial fifo case))
     (newline))
   '((1 0 once) (2 0 once) (2 200 once) (1 0 until) (2 0 until) (2 200 until)))
  (system (string-append "rm " fifo " && rmdir " dir)))
