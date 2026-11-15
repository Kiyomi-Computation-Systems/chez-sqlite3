;;; chez-interrupt.sps: A3, this binding's architecture through Chez.
;;;
;;;   $CHEZ --program chez-interrupt.sps LIBRARY SOURCE-ID SCRATCH-DIR TIMING-FILE [RUNS]
;;;
;;; A Chez thread that owns a connection (ADR-0010) blocks in a
;;; __collect_safe sqlite3_step inside critical-section, as M2's verbs run it
;;; (ADR-0011, ADR-0014 decision 10). Another Chez thread collects, then calls
;;; sqlite3_interrupt, the one call ADR-0010 lets another thread make.
;;;
;;; Bare foreign-procedure bindings, made after the library's load. No
;;; Scheme object is passed to C: strings are copied into foreign blocks.
;;; Effects are sequenced with let* and begin, never by argument order.
;;; Each forked thread makes whatever it raises its answer; every wait is
;;; bounded, and a timed-out wait prints TIMEOUT and exits 3. The owner
;;; closes its connection only after the main thread has made its interrupt,
;;; so no interrupt reaches a closed connection.
;;;
;;; Facts go to stdout, byte for byte the same across runs; timings go to
;;; TIMING-FILE.
(import (chezscheme))

(define args (command-line-arguments))
(define library-path (list-ref args 0))
(define expected-source-id (list-ref args 1))
(define scratch (list-ref args 2))
(define timing (open-output-file (list-ref args 3) 'replace))
(define runs (if (> (length args) 4) (string->number (list-ref args 4)) 21))

(define loaded (load-shared-object library-path))

(define sqlite3-libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define sqlite3-sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define sqlite3-open-v2
  (foreign-procedure __collect_safe "sqlite3_open_v2" (uptr uptr int uptr) int))
(define sqlite3-close (foreign-procedure __collect_safe "sqlite3_close" (uptr) int))
(define sqlite3-prepare-v3
  (foreign-procedure __collect_safe "sqlite3_prepare_v3"
    (uptr uptr int unsigned-int uptr uptr) int))
(define sqlite3-step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define sqlite3-finalize (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define sqlite3-interrupt (foreign-procedure "sqlite3_interrupt" (uptr) void))
(define sqlite3-is-interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int))
(define sqlite3-busy-timeout (foreign-procedure "sqlite3_busy_timeout" (uptr int) int))
(define sqlite3-errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define sqlite3-extended-errcode (foreign-procedure "sqlite3_extended_errcode" (uptr) int))

;; ---- C strings, read and written by our own code ----

(define (read-c-string address)
  (let loop ([n 0])
    (if (= 0 (foreign-ref 'unsigned-8 address n))
        (let ([bv (make-bytevector n)])
          (let copy ([i 0])
            (when (< i n)
              (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 address i))
              (copy (+ i 1))))
          (utf8->string bv))
        (loop (+ n 1)))))

;; Calls (proc block byte-length) with a NUL-terminated copy of s, freed after.
(define (call-with-c-string s proc)
  (let* ([bv (string->utf8 s)]
         [n (bytevector-length bv)]
         [block (foreign-alloc (+ n 1))])
    (let fill ([i 0])
      (when (< i n)
        (foreign-set! 'unsigned-8 block i (bytevector-u8-ref bv i))
        (fill (+ i 1))))
    (foreign-set! 'unsigned-8 block n 0)
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block n))
      (lambda () (foreign-free block)))))

(define (call-with-out-pointer proc)
  (let ([cell (foreign-alloc 8)])
    (foreign-set! 'uptr cell 0 0)
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc cell))
      (lambda () (foreign-free cell)))))

;; READWRITE | CREATE | FULLMUTEX | EXRESCODE, as chez-sqlite3 opens one.
(define open-flags (logior #x2 #x4 #x10000 #x02000000))

(define (open-db file)
  (call-with-c-string (string-append scratch "/" file)
    (lambda (path n)
      (call-with-out-pointer
        (lambda (cell)
          (let* ([rc (sqlite3-open-v2 path cell open-flags 0)]
                 [db (foreign-ref 'uptr cell 0)])
            (unless (= rc 0) (error 'open-db "open failed" rc))
            db))))))

(define (prepare db sql)
  (call-with-c-string sql
    (lambda (text n)
      (call-with-out-pointer
        (lambda (cell)
          (let* ([rc (sqlite3-prepare-v3 db text n 0 cell 0)]
                 [st (foreign-ref 'uptr cell 0)])
            (unless (and (= rc 0) (not (= st 0)))
              (error 'prepare "prepare failed" rc sql))
            st))))))

;; Steps SQL to its end; answers the last step's code.
(define (exec db sql)
  (let* ([st (prepare db sql)]
         [rc (let loop () (let ([r (sqlite3-step st)]) (if (= r 100) (loop) r)))]
         [f (sqlite3-finalize st)])
    rc))

(define (must db sql)
  (let ([rc (exec db sql)])
    (unless (= rc 101) (error 'must "statement failed" rc sql))))

(define (now-ms)
  (let ([t (current-time 'time-monotonic)])
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define (sleep-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

(define (code-name rc)
  (case rc
    [(0) "OK"] [(5) "BUSY"] [(9) "INTERRUPT"] [(100) "ROW"] [(101) "DONE"]
    [else "?"]))

(define (condition->text e)
  (call-with-string-output-port (lambda (p) (display-condition e p))))

;; ---- what the two threads share ----

;; state: 'starting, then 'stepping just before the step, 'returned after it,
;; or 'raised. released: set by the main thread once it has interrupted (or
;; given up); the owner closes its connection only after that.
(define-record-type shared
  (fields mutex cond
          (mutable db) (mutable state) (mutable answer) (mutable t-call)
          (mutable t-return) (mutable released) (mutable timer-fired))
  (protocol (lambda (new) (lambda () (new (make-mutex) (make-condition)
                                          #f 'starting #f #f #f #f #f)))))

(define (update! sh proc)
  (with-mutex (shared-mutex sh)
    (proc)
    (condition-broadcast (shared-cond sh))))

(define (read-state sh)
  (with-mutex (shared-mutex sh) (shared-state sh)))

;; Waits until (ready?) holds, at most ms; answers #t, or #f on the bound.
(define (wait-until sh ready? ms)
  (let ([deadline (+ (now-ms) ms)])
    (with-mutex (shared-mutex sh)
      (let loop ()
        (cond
          [(ready?) #t]
          [(>= (now-ms) deadline) #f]
          [else
           (condition-wait (shared-cond sh) (shared-mutex sh)
                           (make-time 'time-duration 50000000 0))
           (loop)])))))

(define (timed-out what)
  (printf "TIMEOUT: ~a~n" what)
  (flush-output-port (current-output-port))
  (exit 3))

;; The owner thread: opens FILE, runs SETUP on its connection, prepares SQL,
;; then steps it inside critical-section. With timer?, it arms a Chez timer
;; interrupt just before the step, outside any critical section, instead.
(define (owner sh file setup sql timer?)
  (lambda ()
    (let ([answer
           (guard (e [#t (list 'raised (condition->text e))])
             (let* ([db (open-db file)]
                    [_ (setup db)]
                    [st (prepare db sql)])
               (update! sh (lambda () (shared-db-set! sh db)
                                      (shared-state-set! sh 'stepping)))
               (let* ([t0 (now-ms)]
                      [rc (if timer?
                              (begin
                                (timer-interrupt-handler
                                  (lambda ()
                                    (update! sh (lambda ()
                                                  (shared-timer-fired-set! sh (now-ms))))))
                                (set-timer 100000)
                                (sqlite3-step st))
                              (critical-section (sqlite3-step st)))]
                      [t1 (now-ms)]
                      [ext (sqlite3-extended-errcode db)]
                      [msg (read-c-string (sqlite3-errmsg db))])
                 (update! sh (lambda ()
                               (shared-t-call-set! sh t0)
                               (shared-t-return-set! sh t1)
                               (shared-state-set! sh 'returned)))
                 ;; Burn ticks so an armed timer fires, if it is going to.
                 (when timer?
                   (let burn ([i 0])
                     (when (and (< i 10000000)
                                (not (with-mutex (shared-mutex sh)
                                       (shared-timer-fired sh))))
                       (burn (+ i 1))))
                   (set-timer 0))
                 (let* ([released (wait-until sh (lambda () (shared-released sh)) 20000)]
                        [f (sqlite3-finalize st)]
                        [c (sqlite3-close db)])
                   (list 'answered rc ext msg released f c)))))])
      (update! sh (lambda ()
                    (shared-answer-set! sh answer)
                    (unless (eq? (shared-state sh) 'returned)
                      (shared-state-set! sh 'raised)))))))

(define (no-setup db) #f)

(define long-sql
  "WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM c WHERE i < 2000000000) SELECT count(*) FROM c")

;; One run. KIND is 'long (the long step), 'busy (BEGIN IMMEDIATE under
;; another connection's lock, busy timeout 1000 ms), or 'timer (the long
;; step with a Chez timer armed on the owner). COLLECTOR is collect or
;; collect-rendezvous, called by the main thread while the step blocks.
;; Answers (facts timings), facts a string.
(define (one-run kind collector run)
  (let* ([file (format "a3-~a-~a-~a.db" kind
                       (cond [(eq? collector collect) "collect"] [collector "rendezvous"] [else "none"])
                       run)]
         [other (and (eq? kind 'busy)
                     (let ([o (open-db file)])
                       (must o "CREATE TABLE t(x)")
                       (must o "INSERT INTO t VALUES(1)")
                       (must o "BEGIN IMMEDIATE")
                       o))]
         [sh (make-shared)]
         [setup (if (eq? kind 'busy)
                    (lambda (db) (sqlite3-busy-timeout db 1000))
                    no-setup)]
         [sql (if (eq? kind 'busy) "BEGIN IMMEDIATE" long-sql)]
         [th (fork-thread (owner sh file setup sql (eq? kind 'timer)))]
         [started (wait-until sh (lambda () (memq (shared-state sh) '(stepping raised))) 10000)])
    (unless started (timed-out "the owner never began its step"))
    (when (eq? (read-state sh) 'raised)
      (printf "the owner raised: ~s~n" (shared-answer sh))
      (exit 1))
    (sleep-ms 200)
    (let* ([db (with-mutex (shared-mutex sh) (shared-db sh))]
           [n0 (collections)]
           [c0 (now-ms)]
           [_ (if collector (collector) #f)]
           [c1 (now-ms)]
           [n1 (collections)]
           [blocked-after-collect (eq? (read-state sh) 'stepping)]
           [junk (make-bytevector 1000000 7)]
           [ti (now-ms)]
           [_ (sqlite3-interrupt db)]
           [after-interrupt (sqlite3-is-interrupted db)]
           [blocked-at-interrupt (eq? (read-state sh) 'stepping)]
           [_ (update! sh (lambda () (shared-released-set! sh #t)))]
           [finished (wait-until sh (lambda () (shared-answer sh)) 10000)])
      (unless finished (timed-out "the owner's step did not return within 10 s of the interrupt"))
      (when other
        (must other "COMMIT")
        (sqlite3-close other))
      (let* ([answer (with-mutex (shared-mutex sh) (shared-answer sh))]
             [t-call (shared-t-call sh)]
             [t-return (shared-t-return sh)]
             [fired (shared-timer-fired sh)]
             [facts
              (with-output-to-string
                (lambda ()
                  (when collector
                    (printf "  main thread's ~a while the step blocked: returned with the step still blocked: ~a; collections rose by ~a~n"
                            (if (eq? collector collect) "(collect)" "(collect-rendezvous)")
                            (if blocked-after-collect "yes" "NO")
                            (- n1 n0)))
                  (printf "  main thread's sqlite3_interrupt: the step still blocked then: ~a; is_interrupted just after: ~a~n"
                          (if blocked-at-interrupt "yes" "NO") after-interrupt)
                  (if (eq? (car answer) 'answered)
                      (let* ([rc (list-ref answer 1)] [ext (list-ref answer 2)]
                             [msg (list-ref answer 3)] [released (list-ref answer 4)]
                             [f (list-ref answer 5)] [c (list-ref answer 6)])
                        (printf "  the owner's step answered ~a ~a, extended ~a, ~s~n" rc (code-name rc) ext msg)
                        (when (eq? kind 'busy)
                          (printf "  it ended ~a~n"
                                  (cond [(< (- t-return t-call) 500) "early: before half the busy timeout"]
                                        [(>= (- t-return t-call) 900) "at the busy timeout: at least 90% of it"]
                                        [else "between half and 90% of the busy timeout"])))
                        (when (eq? kind 'timer)
                          (printf "  the owner's timer interrupt ~a~n"
                                  (cond [(not fired) "never fired"]
                                        [(< fired t-call) "fired before the step began"]
                                        [(< fired t-return) "fired while the step blocked"]
                                        [else "fired only after the step returned"])))
                        (printf "  the owner then: released ~a, finalize ~a, close ~a~n" released f c))
                      (printf "  the owner raised: ~a~n" (cadr answer)))))])
        (list facts
              (list (- c1 c0) (- t-return ti) (- t-return t-call)
                    (if fired (- fired t-return) 0)))))))

;; C3's control: the same timer, armed the same way, during a 200 ms loop of
;; Scheme code instead of a foreign call. If it fired only after the loop, C3's
;; answer would say nothing about the foreign call.
(define (timer-control)
  (let* ([fired #f]
         [_ (timer-interrupt-handler (lambda () (set! fired (now-ms))))]
         [t0 (now-ms)]
         [_ (set-timer 100000)]
         [t1 (let loop () (let ([t (now-ms)]) (if (< t (+ t0 200)) (loop) t)))]
         [_ (set-timer 0)])
    (list (cond [(not fired) "never fired"]
                [(< fired t1) "fired during the loop"]
                [else "fired only after the loop"])
          (if fired (- fired t0) 0))))

(define (sorted-stats label xs)
  (let* ([v (list-sort < xs)] [n (length v)])
    (fprintf timing "~a: n ~a, min ~,3f, median ~,3f, max ~,3f ms~n"
             label n (list-ref v 0) (list-ref v (div n 2)) (list-ref v (- n 1)))
    (fprintf timing "  sorted:")
    (for-each (lambda (x) (fprintf timing " ~,3f" x)) v)
    (fprintf timing "~n")))

(define (case-run name kind collector)
  (let loop ([run 0] [first #f] [same 0] [collects '()] [latencies '()] [steps '()]
             [timers '()])
    (if (= run runs)
        (begin
          (printf "~a~n~a" name first)
          (printf "  runs whose facts equal run 1's: ~a of ~a~n" same runs)
          (when collector (sorted-stats (string-append name ": the collection's ms") collects))
          (sorted-stats (string-append name ": ms from the interrupt call to the step's return") latencies)
          (sorted-stats (string-append name ": ms the step took") steps)
          (when (eq? kind 'timer)
            (sorted-stats (string-append name ": ms from the step's return to the timer handler")
                          timers)))
        (let* ([r (one-run kind collector run)]
               [facts (car r)]
               [times (cadr r)]
               [first (or first facts)])
          (loop (+ run 1) first (if (string=? first facts) (+ same 1) same)
                (cons (list-ref times 0) collects)
                (cons (list-ref times 1) latencies)
                (cons (list-ref times 2) steps)
                (cons (list-ref times 3) timers))))))

(define (control-run)
  (let loop ([run 0] [first #f] [same 0] [times '()])
    (if (= run runs)
        (begin
          (printf "C3 control: the same timer armed on the main thread during a 200 ms loop of Scheme code~n  it ~a~n"
                  first)
          (printf "  runs whose facts equal run 1's: ~a of ~a~n" same runs)
          (sorted-stats "C3 control: ms from arming the timer to its handler" times))
        (let* ([r (timer-control)]
               [first (or first (car r))])
          (loop (+ run 1) first (if (string=? first (car r)) (+ same 1) same)
                (cons (cadr r) times))))))

(let* ([version (read-c-string (sqlite3-libversion))]
       [source-id (read-c-string (sqlite3-sourceid))])
  (unless (string=? source-id expected-source-id)
    (printf "refused: runtime source id ~a, expected ~a~n" source-id expected-source-id)
    (exit 2))
  (printf "libversion ~a~nsourceid ~a~n" version source-id)
  (fprintf timing "libversion ~a~nsourceid ~a~n" version source-id)
  (fprintf timing "RUNS ~a per distribution; the machine was shared with other probes~n" runs)
  (printf "Chez ~a, threaded ~a~n" (scheme-version) (threaded?))
  (case-run "C1a: a long step in the owner's critical-section; main calls (collect), then interrupts"
            'long collect)
  (case-run "C1b: the same; main calls (collect-rendezvous), then interrupts"
            'long collect-rendezvous)
  (case-run "C2a: the owner's BEGIN IMMEDIATE blocked in a 1000 ms busy timeout; main calls (collect), then interrupts"
            'busy collect)
  (case-run "C2b: the same; main calls (collect-rendezvous), then interrupts"
            'busy collect-rendezvous)
  (case-run "C3: a long step with a Chez timer interrupt armed on the owner, outside any critical section; main interrupts"
            'timer #f)
  (control-run)
  (close-port timing)
  (printf "end~n"))
