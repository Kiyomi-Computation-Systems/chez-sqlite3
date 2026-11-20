#!r6rs
;;; The suite for load-extension! under engines and a timer's continuations
;;; (ADR-0021; ADR-0016), in (chez-sqlite3 private extension). The call's
;;; one section claims its claim's position 0, inside the section: a run the
;;; call has passed is refused there, touching nothing. Every load runs the
;;; extension's init again, so a whole call is counted by its effect, the
;;; init's run, which tests/extension.c's chez_inits() counts, never by how
;;; many runs answered.
;;;
;;;   clean          the load with no engine: it answers, the init run once,
;;;                  chez_half present
;;;   every fuel     the load as an engine, at every fuel from 1 until it
;;;                  completes without expiring, each fuel's run resumed at
;;;                  its fuel until it completes: it answers, the init run
;;;                  once, chez_half present
;;;   resumed twice  each fuel's remainder resumed to its end, then again:
;;;                  the second refused with &sqlite-closed, the init not run
;;;                  again; or, taken past the section, answering again with
;;;                  no init; or a whole new call, its own init, only below a
;;;                  refusal of a remainder taken before the section, which
;;;                  the sweep sees itself
;;;   interleaved    the remainder R at every fuel, R1 taken from R's resume
;;;                  at every later fuel, R resumed again to its end, then
;;;                  R1: each run answers or is refused, the inits one a call
;;;                  whatever the runs answered, two only for a whole new
;;;                  call, below the first refusal the sweep saw itself
;;;   re-entered     a continuation a timer's handler took at each tick of the
;;;                  call, called once the call has returned: refused, or
;;;                  past the section answering again, never the init run
;;;                  again but by a whole new call, below a refusal the sweep
;;;                  sees itself
;;;   two passes     each of the three rows above twice: with no collect
;;;                  request in a trial, and under a collect trip of 256
;;;                  bytes, where a request due inside the section costs the
;;;                  engine ticks at its exit, so remainders and a timer's
;;;                  continuations are taken past the section too, the
;;;                  call's last work; the second pass fails by name where
;;;                  none is
;;;   the caller's   the caller's path, and its entry point, changed between
;;;   strings        an expiry and its resume: refused by the check's own
;;;                  rule, or loaded, never the changed string handed to C
;;;
;;; Each trial runs on a fresh connection, opened with the opt-in outside
;;; the engine, and a fresh engine. A pin, a connection of the suite's that
;;; loaded the extension first and stays open, keeps the file loaded, so the
;;; count reads across trials, each trial's inits the count's growth over
;;; it, read on the pin. An engine spends no ticks inside a critical
;;; section, so the fuels measure the Scheme work between the call's sections.
;;; Each fuel and tick begins with a collection, collect-trip-bytes raised far
;;; above what its runs allocate, so no collect request falls in them, but in
;;; the low pass, which lowers the trip on purpose. Each bound on a whole new
;;; call is a refusal the sweep sees itself, never a refused call's fuel, a
;;; control run on the code under test, or a caller's count.
;;;
;;; Where the library lacks sqlite3_load_extension, no connection can opt
;;; in: each row is printed unavailable, and the open's refusal asserted in
;;; its place (ADR-0005).
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs mutable-strings)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine set-timer timer-interrupt-handler collect collect-trip-bytes
              disable-interrupts enable-interrupts)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (extension-build)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-extensions-unavailable?))

(define runner (test-runner-simple))
(test-runner-current runner)

(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- reached through eval -------------------------------------------------------------

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : (Listof Symbol) Symbol -> Procedure
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define load-extension! (public 'load-extension!))
(define open-database (public 'open-database))
(define close-database! (public 'close-database!))
(define database? (public 'database?))
(define query (public 'query))
(define query-row (public 'query-row))

;; available : Any
(define available
  (guard (e (#t (list 'unreached (describe e))))
    (eval 'load-extension-available? (environment '(chez-sqlite3 private native)))))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-extensions-unavailable? e)
         (list 'extensions-unavailable (who-of e)
               (if (and (chez-sqlite3-error? e) (not (sqlite-error? e))) 'library-condition 'other-kind)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define (a-database? x) (guard (e (#t #f)) (database? x)))

(define (close-answer r)
  (guard (e (#t #f)) (close-database! r)))

(define (opted) (open-database ":memory:" '((enable-load-extension . #t))))

;; half : Database -> Any
(define (half db)
  (let ((r (guard (e ((sqlite-error? e) (list 'absent (sqlite-error-code e)))
                     (#t (list 'raised (what-raised e))))
             (query db "select chez_half(5)"))))
    (if (equal? r '(#(2.5))) 'present r)))

;; summarized : (Listof Any) -> Any
;; () for no deviation; else how many, and the first three.
(define (summarized deviations)
  (if (null? deviations)
      '()
      (list (length deviations)
            (let loop ((rest deviations) (n 0) (kept '()))
              (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

(define (kind-count kinds k) (let ((p (assq k kinds))) (if p (cdr p) 0)))

;; counted-up : Symbol (Listof (Pairof Symbol Natural)) -> (Listof (Pairof Symbol Natural))
(define (counted-up k kinds)
  (cond ((null? kinds) (list (cons k 1)))
        ((eq? (car (car kinds)) k) (cons (cons k (+ (cdr (car kinds)) 1)) (cdr kinds)))
        (else (cons (car kinds) (counted-up k (cdr kinds))))))

;; --- the extension and the pin ------------------------------------------------------------

(define dir (guard (e (#t (list 'raised (describe e)))) (make-process-temp-directory)))

(define built
  (if (string? dir)
      (guard (e (#t (list 'raised (describe e)))) (built-where-loadable available dir))
      (list 'no-scratch dir)))

(define ext (extension-path built 'default))
(define ext-named (extension-path built 'named))

;; pin : Any
;; A connection of the suite's, the default variant loaded into it first,
;; open to the end: so the file stays loaded across the trials, and
;; chez_inits() read on it counts every init in the process. #f where the
;; library lacks sqlite3_load_extension; else what failed.
(define pin
  (if (eq? available #t)
      (guard (e (#t (list 'raised (what-raised e))))
        (let ((db (opted)))
          (guard (e (#t (close-answer db) (raise e)))
            (load-extension! db ext)
            db)))
      #f))

;; pin-inits : -> Any
;; How many inits of the default variant have run in the process, read on
;; the pin.
(define (pin-inits)
  (let ((r (attempt (lambda () (query-row pin "select chez_inits()")))))
    (if (and (vector? r) (= (vector-length r) 1)) (vector-ref r 0) r)))

(define (load-thunk db) (lambda () (attempt (lambda () (load-extension! db ext) 'loaded))))

(define refused-answer '(raised (closed load-extension!)))

;; --- engines ------------------------------------------------------------------------------

;; quieted! : -> Void
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
(define (slice e fuel)
  (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))

;; resumed-at : Engine Positive-Integer -> Any
(define (resumed-at e fuel)
  (let loop ((e e) (n 0))
    (let ((r (slice e fuel)))
      (cond ((eq? (car r) 'completed) (cadr r))
            ((>= n 100000) 'never-completed)
            (else (loop (cadr r) (+ n 1)))))))

;; finish : Engine -> Any
(define (finish e) (resumed-at e 1000000))

;; engine-row : String Any (-> Any) -> Void
;; The test NAME on a library that has sqlite3_load_extension; on one
;; without it, NAME printed UNAVAILABLE and the open's refusal asserted in
;; its place.
(define (engine-row name expected thunk)
  (if (eq? available #t)
      (test-equal name expected (guard (e (#t (list 'raised (what-raised e)))) (thunk)))
      (begin
        (display "UNAVAILABLE ")
        (display name)
        (display ": this libsqlite3 has no sqlite3_load_extension, so no connection can opt in, and the open's refusal is asserted in its place")
        (newline)
        (test-equal (string-append "unavailable, the opt-in's open refused in its place: " name)
          '(raised (extensions-unavailable open-database library-condition))
          (let ((r (attempt opted)))
            (if (a-database? r) (begin (close-answer r) 'opened) r))))))

(test-begin "load-extension-engines")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "where the library has sqlite3_load_extension, tests/extension.c's default variant compiles and the pin loads it, its count 1; where it has none, the build is named unavailable, nothing compiled, and there is no pin"
  (if (eq? available #f) (list '(unavailable) 'no-pin) (list 'built 1))
  (begin
    (when (eq? available #f)
      (display "UNAVAILABLE the extension's build: this libsqlite3 has no sqlite3_load_extension, so no connection can load it")
      (newline))
    (list (if (and (list? built) (for-all pair? built) (assq 'default built)) 'built built)
          (if (eq? available #t) (if (a-database? pin) (pin-inits) pin) 'no-pin))))

;; --- clean -------------------------------------------------------------------------------------

(engine-row "the clean answer, with no engine: the load answers on a fresh connection, the init run once, read on the pin, and chez_half present; closed, the connection's count is back"
  (list 'loaded 1 'present '((block . 0) (connection . 1) (statement . 1)))
  (lambda ()
    (let* ((db (opted))
           (before (pin-inits))
           (r ((load-thunk db)))
           (after (pin-inits))
           (h (half db)))
      (close-answer db)
      (list r (if (and (integer? before) (integer? after)) (- after before) (list before after)) h
            (native-counts)))))

;; --- every fuel ---------------------------------------------------------------------------------

;; at-fuel : Positive-Integer -> (List Boolean (Listof Any))
;; The load at FUEL on a fresh connection, resumed at its fuel until it
;; completes: whether it expired, and what deviated.
(define (at-fuel fuel)
  (let* ((db (opted))
         (before (pin-inits))
         (r (slice (make-engine (load-thunk db)) fuel))
         (expired (eq? (car r) 'expired))
         (answer (if expired (resumed-at (cadr r) fuel) (cadr r)))
         (after (pin-inits))
         (h (half db)))
    (close-answer db)
    (list expired
          (append (if (eq? answer 'loaded) '() (list (list 'answer answer)))
                  (if (and (integer? before) (integer? after) (= (- after before) 1)) '()
                      (list (list 'inits before after)))
                  (if (eq? h 'present) '() (list (list 'half h)))))))

;; sweep : (Positive-Integer -> (List Boolean (Listof Any))) -> (List Any (Listof Any))
(define (sweep check)
  (let loop ((fuel 1) (deviations '()))
    (quieted!)
    (let* ((r (check fuel))
           (deviations (if (null? (cadr r)) deviations (cons (cons fuel (cadr r)) deviations))))
      (cond ((not (car r)) (list fuel (reverse deviations)))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations)))
            (else (loop (+ fuel 1) deviations))))))

(engine-row "the load as an engine, at every fuel from 1 until it completes without expiring, each fuel on a fresh connection, resumed at its fuel until it completes: it answers, the init run once, read on the pin, and chez_half present; it expires at one fuel at least"
  (list '() 'expired-at-a-fuel '((block . 0) (connection . 1) (statement . 1)))
  (lambda ()
    (let ((r (sweep at-fuel)))
      (display "  load-extension!, resumed at its fuel: completed without expiring at fuel ")
      (write (car r))
      (newline)
      (list (if (integer? (car r)) (summarized (cadr r)) (list (car r) (summarized (cadr r))))
            (if (and (integer? (car r)) (> (car r) 1)) 'expired-at-a-fuel (list 'completed-at (car r)))
            (native-counts)))))

;; --- the two passes -----------------------------------------------------------------------------
;; Pass = (U 'high 'low)
;; Each trial begins with begun!: quieted!'s collection, then PASS's trip. In
;; the high pass it stays at 2^27, so no collect request falls in a trial. In
;; the low pass it is 256 bytes, below what one call allocates, until the
;; trial ends: a request then falls due all through it, and one due inside a
;; critical section is handled at the section's exit, where it costs the
;; engine ticks. So an expiry can fall just past the load's section, the
;; call's last work, which no procedure call follows: there alone are
;; remainders taken past it. Each trial is judged by what it saw itself, and
;; each bound is a refusal the sweep saw.

(define low-trip 256)

;; begun! : Pass -> Void
(define (begun! pass)
  (quieted!)
  (when (eq? pass 'low) (collect-trip-bytes low-trip)))

;; ended! : -> Void
(define (ended!) (collect-trip-bytes (expt 2 27)))

(define (slice-in pass e fuel) (slice e fuel))
(define (finish-in pass e) (finish e))

;; --- resumed twice ------------------------------------------------------------------------------

;; twice : Pass Positive-Integer -> (List Boolean Symbol (Listof Any) Boolean)
;; The load at FUEL on a fresh connection, one slice, in PASS. Completed:
;; (#f none () #f). Expired, its remainder is resumed to its end, FIRST,
;; which must answer with one init; then resumed again, SECOND: refused,
;; &sqlite-closed, no init; again, answering past the section, no init; or
;; new, a whole new call, answering with one init of its own. Last,
;; whether the init had run at the expiry.
(define (twice pass fuel)
  (begun! pass)
  (let* ((db (opted))
         (before (pin-inits))
         (r (slice-in pass (make-engine (load-thunk db)) fuel)))
    (if (eq? (car r) 'completed)
        (begin (close-answer db) (ended!) (list #f 'none '() #f))
        (let* ((more (cadr r))
               (at-expiry (pin-inits))
               (first (finish-in pass more))
               (after-first (pin-inits))
               (second (finish-in pass more))
               (after-second (pin-inits))
               (grew (and (integer? after-first) (integer? after-second) (- after-second after-first)))
               (kind (cond ((and (equal? second refused-answer) (eqv? grew 0)) 'refused)
                           ((and (eq? second 'loaded) (eqv? grew 0)) 'again)
                           ((and (eq? second 'loaded) (eqv? grew 1)) 'new)
                           (else 'other)))
               (h (half db)))
          (close-answer db)
          (ended!)
          (list #t kind
                (append (if (eq? first 'loaded) '() (list (list 'first first)))
                        (if (and (integer? before) (integer? after-first) (= (- after-first before) 1)) '()
                            (list (list 'first-inits before after-first)))
                        (if (eq? kind 'other) (list (list 'second second grew)) '())
                        (if (eq? h 'present) '() (list (list 'half h))))
                (and (integer? at-expiry) (integer? before) (> at-expiry before)))))))

;; twice-sweep : Pass -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
;; twice at every fuel from 1 until the load completes without expiring:
;; that fuel; each fuel's deviations; how many fuels each kind of second
;; resume came at, a refusal of a remainder taken before the section,
;; no init at its expiry, as refused-before; and the first fuel at which
;; one was refused, the sweep's own bound: a whole new call past it
;; deviates.
(define (twice-sweep pass)
  (let loop ((fuel 1) (deviations '()) (kinds '()) (refused-at #f))
    (let* ((r (twice pass fuel))
           (kind (cadr r))
           (found (if (and (eq? kind 'new) refused-at)
                      (cons (list 'new-past-a-refusal refused-at) (caddr r))
                      (caddr r)))
           (deviations (if (null? found) deviations (cons (cons fuel found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (not (cadddr r)) fuel)))
           (kinds (if (car r) (counted-up (if (and (eq? kind 'refused) (not (cadddr r))) 'refused-before kind) kinds) kinds)))
      (cond ((not (car r)) (list fuel (reverse deviations) kinds refused-at))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) kinds refused-at))
            (else (loop (+ fuel 1) deviations kinds refused-at))))))

;; twice-reported : String Pass Boolean -> Any
;; twice-sweep in PASS, printed, naming WHAT, and judged: no deviation; a
;; refusal before the section seen, and refusals at half the fuels at
;; least; and, when PAST?, a remainder taken past the section at some fuel,
;; answering again.
(define (twice-reported what pass past?)
  (let ((r (twice-sweep pass)))
    (display "  ")
    (display what)
    (display ": completed without expiring at fuel ")
    (write (car r))
    (display "; second resumes ")
    (write (caddr r))
    (display "; refused before the section first at fuel ")
    (write (cadddr r))
    (newline)
    (let* ((kinds (caddr r))
           (refused (+ (kind-count kinds 'refused) (kind-count kinds 'refused-before))))
      (list (if (integer? (car r)) (summarized (cadr r)) (list (car r) (summarized (cadr r))))
            (if (and (cadddr r) (integer? (car r)) (>= (* 2 refused) (car r)))
                'refused-before-the-section-and-at-half-the-fuels
                (list 'refused refused 'kinds kinds 'of (car r) 'before-first-at (cadddr r)))
            (cond ((not past?) 'not-asked)
                  ((> (kind-count kinds 'again) 0) 'taken-past-the-section-at-a-fuel)
                  (else (list 'none-taken-past-the-section kinds)))))))

(engine-row "the load's remainder resumed twice, at every fuel from 1 until it completes without expiring, each fuel on a fresh connection, no collect request in its runs: resumed to its end it answers, the init run once; resumed again, it raises &sqlite-closed, refused at its section, the init not run again, at half the fuels at least and at some before the section; or, taken past the section, it answers again, no init; a whole new call, its own init, comes only below every refusal before the section; chez_half present"
  (list '() 'refused-before-the-section-and-at-half-the-fuels 'not-asked)
  (lambda () (twice-reported "load-extension! resumed twice" 'high #f)))

(engine-row "the same, its runs under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit: the same verdicts, and at some fuel a remainder is taken past the section, its second resume answering again with no init"
  (list '() 'refused-before-the-section-and-at-half-the-fuels 'taken-past-the-section-at-a-fuel)
  (lambda () (twice-reported "load-extension! resumed twice, low trip" 'low #t)))

;; --- interleaved ----------------------------------------------------------------------------------

;; Trial = (List Symbol (Listof Any) Any Boolean Boolean Any)
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; what its runs answered;
;; how many inits it ran, read on the pin; whether R, and R1, were each
;; taken past the section, the init run at its own expiry; and chez_half
;; on its connection after.

;; interleaved-trial : Pass Natural Natural -> Trial
;; The load at FUEL on a fresh connection and engine, in PASS: R, resumed
;; at G until it expires again as R1, then R resumed again to its end,
;; then R1.
(define (interleaved-trial pass fuel g)
  (begun! pass)
  (let* ((db (opted))
         (before (pin-inits))
         (grew (lambda () (let ((now (pin-inits))) (if (and (integer? now) (integer? before)) (- now before) now))))
         (r (slice-in pass (make-engine (load-thunk db)) fuel))
         (t (if (eq? (car r) 'completed)
                (list 'completed (list (cadr r)) (grew) #f #f)
                (let* ((R (cadr r))
                       (r-past (eqv? (grew) 1))
                       (r1 (slice-in pass R g)))
                  (if (eq? (car r1) 'completed)
                      (let ((second (finish-in pass R)))
                        (list 'last (list (cadr r1) second) (grew) r-past #f))
                      (let* ((R1 (cadr r1))
                             (r1-past (eqv? (grew) 1))
                             (second (finish-in pass R))
                             (third (finish-in pass R1)))
                        (list 'interleaved (list second third) (grew) r-past r1-past))))))
         (h (half db)))
    (close-answer db)
    (ended!)
    (append t (list h))))

;; trial-deviations : Trial -> (Listof Any)
;; What a trial did wrong, judged by itself: a run that neither answered
;; nor was refused; inits other than 1 or 2, two being a whole new call,
;; which the sweep bounds; chez_half absent.
(define (trial-deviations t)
  (append (let loop ((rest (cadr t)) (found '()))
            (if (null? rest)
                (reverse found)
                (loop (cdr rest)
                      (if (or (eq? (car rest) 'loaded) (equal? (car rest) refused-answer))
                          found
                          (cons (list 'answer (car rest)) found)))))
          (if (memv (caddr t) '(1 2)) '() (list (list 'inits (caddr t))))
          (if (eq? (list-ref t 5) 'present) '() (list (list 'half (list-ref t 5))))))

;; refused-before? : Trial -> Boolean
;; Whether a run of the trial was refused, R taken before the section.
(define (refused-before? t)
  (and (not (cadddr t)) (member refused-answer (cadr t)) #t))

;; Sweep = (List Any Natural (Listof Any) Natural (Listof Natural) (U Natural #f) Natural Natural Natural)
;; The fuel at which the load completes without expiring; how many trials
;; ran; their deviations, with their fuels; the trials that ran an init;
;; the fuels of the trials that ran two, whole new calls; the first fuel at
;; which a trial was refused, R taken before the section, the sweep's own
;; bound; how many fuels saw a refusal; and the trials with both
;; remainders past the section, and with R before it and R1 past it.

;; interleave-sweep : Pass -> Sweep
;; At every fuel from 1 until the load completes without expiring, a trial
;; at every G from 1 until R's resume completes within it.
(define (interleave-sweep pass)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (news '()) (refused-at #f)
              (refused-fuels 0) (past 0) (straddle 0))
    (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (news news)
                (refused-at refused-at) (seen #f) (past past) (straddle straddle))
      (let* ((t (interleaved-trial pass fuel g))
             (kind (car t))
             (found (trial-deviations t))
             (deviations (if (null? found) deviations (cons (list fuel g found) deviations)))
             (answered (if (and (integer? (caddr t)) (> (caddr t) 0)) (+ answered 1) answered))
             (news (if (eqv? (caddr t) 2) (cons fuel news) news))
             (refused (refused-before? t))
             (refused-at (or refused-at (and refused fuel)))
             (seen (or seen (and (member refused-answer (cadr t)) #t)))
             (past (if (and (cadddr t) (list-ref t 4)) (+ past 1) past))
             (straddle (if (and (not (cadddr t)) (list-ref t 4)) (+ straddle 1) straddle))
             (trials (+ trials 1)))
        (cond ((eq? kind 'completed)
               (list fuel trials (reverse deviations) answered (reverse news) refused-at refused-fuels past
                     straddle))
              ((>= fuel 20000)
               (list 'no-completion-by-20000 trials (reverse deviations) answered (reverse news) refused-at
                     refused-fuels past straddle))
              ((eq? kind 'last)
               (floop (+ fuel 1) trials deviations answered news refused-at
                      (if seen (+ refused-fuels 1) refused-fuels) past straddle))
              (else (gloop (+ g 1) trials deviations answered news refused-at seen past straddle)))))))

;; interleave-reported : String Pass Boolean -> Any
;; interleave-sweep in PASS, printed, naming WHAT, and judged: no
;; deviation; trials running an init three a fuel on average, so no
;; remainder served two trials; refusals at half the fuels at least; every
;; whole new call below the first refusal the sweep saw itself, R taken
;; before the section; and, when STRADDLE?, R before the section and R1
;; past it in some trial, failing by name where none was.
(define (interleave-reported what pass straddle?)
  (let ((run (interleave-sweep pass)))
    (display "  ")
    (display what)
    (display ": completed without expiring at fuel ")
    (write (car run))
    (display "; trials ")
    (write (cadr run))
    (display "; trials running an init ")
    (write (list-ref run 3))
    (display "; fuels seeing a refusal ")
    (write (list-ref run 6))
    (display "; both past the section in ")
    (write (list-ref run 7))
    (display "; R before it and R1 past it in ")
    (write (list-ref run 8))
    (display "; whole new calls ")
    (write (length (list-ref run 4)))
    (display ", the last at fuel ")
    (write (if (null? (list-ref run 4)) 0 (apply max (list-ref run 4))))
    (display ", below the first refusal before the section, at fuel ")
    (write (list-ref run 5))
    (newline)
    (let ((fuel (car run)) (news (list-ref run 4)) (refused-at (list-ref run 5)))
      (list (if (integer? fuel) (summarized (caddr run)) (list fuel (summarized (caddr run))))
            (if (and (integer? fuel) (>= (list-ref run 3) (* 3 fuel)) (>= (* 2 (list-ref run 6)) fuel))
                'three-a-fuel-and-refused-at-half-the-fuels
                (list 'answered (list-ref run 3) 'refused-fuels (list-ref run 6) 'over fuel))
            (if (and refused-at (for-all (lambda (f) (< f refused-at)) news))
                'whole-new-calls-below-a-refusal
                (list 'whole-new-calls-not-below-a-refusal news refused-at))
            (cond ((not straddle?) 'not-asked)
                  ((> (list-ref run 8) 0) 'straddled)
                  (else (list 'too-few-trials-straddling-the-section (list-ref run 8))))))))

(engine-row "the load's remainder R, taken at every fuel from 1 until the load completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1, each trial on a fresh connection and engine, no collect request in its runs: each run answers or is refused with &sqlite-closed; the init runs once a call, counted on the pin whatever the runs answered, twice only for a whole new call, below the first refusal the sweep saw itself; chez_half present; trials run an init three a fuel on average, and refusals come at half the fuels at least"
  (list '() 'three-a-fuel-and-refused-at-half-the-fuels 'whole-new-calls-below-a-refusal 'not-asked)
  (lambda () (interleave-reported "load-extension!, interleaved" 'high #f)))

(engine-row "the same, its runs under a collect trip of 256 bytes: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals, and in some trial R is taken before the section and R1 past it, so a run that loads is raced against one past the section"
  (list '() 'three-a-fuel-and-refused-at-half-the-fuels 'whole-new-calls-below-a-refusal 'straddled)
  (lambda () (interleave-reported "load-extension!, interleaved, low trip" 'low #t)))

;; --- a timer's continuation, re-entered ---------------------------------------------------------

;; reentered-at : Pass Positive-Integer -> (U 'no-capture (List Any Any Any Natural))
;; The load on a fresh connection, in PASS, a timer's handler taking a
;; continuation at the call's tick I, and the timer then stopped. Once the
;; call has returned, the continuation is called, once, and the call goes
;; on from there. no-capture when tick I fell after the call; else the
;; first return's answer, the re-entry's, how many inits had run at the
;; capture, and how many the re-entry ran, read on the pin.
(define (reentered-at pass i)
  (begun! pass)
  (let* ((db (opted))
         (before (pin-inits))
         (ticks 0) (saved #f) (at-capture #f) (first #f) (runs 0) (after-first #f)
         (old (timer-interrupt-handler))
         (r (dynamic-wind
              (lambda ()
                (timer-interrupt-handler
                 (lambda ()
                   (set! ticks (+ ticks 1))
                   (if (= ticks i)
                       (begin (set! at-capture (pin-inits))
                              (call/cc (lambda (k) (set! saved k))))
                       (set-timer 1)))))
              (lambda ()
                (set-timer 1)
                (let ((answer ((load-thunk db))))
                  (set-timer 0)
                  (set! runs (+ runs 1))
                  (cond ((> runs 1) (list first answer))
                        ((not saved) 'no-capture)
                        (else (set! first answer)
                              (set! after-first (pin-inits))
                              (let ((k saved)) (k #f))))))
              (lambda ()
                (set-timer 0)
                (timer-interrupt-handler old)))))
    (let ((after (pin-inits)))
      (close-answer db)
      (ended!)
      (if (eq? r 'no-capture)
          r
          (list (car r) (cadr r)
                (if (and (integer? at-capture) (integer? before)) (- at-capture before) at-capture)
                (if (and (integer? after) (integer? after-first)) (- after after-first) after))))))

;; reentry-kind : Any -> Symbol
;; done for no-capture; refused, the re-entry refused, no init; again, the
;; re-entry past the section, answering with no init; new, a whole new
;; call, one init of its own; else deviation. The first return must have
;; answered with one init.
(define (reentry-kind r)
  (cond ((eq? r 'no-capture) 'done)
        ((not (and (list? r) (= (length r) 4) (eq? (car r) 'loaded))) 'deviation)
        ((and (equal? (cadr r) refused-answer) (eqv? (cadddr r) 0)) 'refused)
        ((and (eq? (cadr r) 'loaded) (eqv? (cadddr r) 0)) 'again)
        ((and (eq? (cadr r) 'loaded) (eqv? (cadddr r) 1)) 'new)
        (else 'deviation)))

;; reentry-sweep : Pass -> (List Natural (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
(define (reentry-sweep pass)
  (let loop ((i 1) (deviations '()) (kinds '()) (refused-at #f))
    (let* ((r (reentered-at pass i))
           (kind (reentry-kind r))
           (found (append (if (eq? kind 'deviation) (list r) '())
                          (if (and (eq? kind 'new) refused-at) (list (list 'new-past-a-refusal refused-at)) '())))
           (deviations (if (null? found) deviations (cons (cons i found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (eqv? (caddr r) 0) i))))
      (cond ((or (eq? kind 'done) (>= i 20000)) (list i (reverse deviations) kinds refused-at))
            (else (loop (+ i 1) deviations (counted-up kind kinds) refused-at))))))

;; reentry-reported : String Pass Boolean -> Any
;; reentry-sweep in PASS, printed, naming WHAT, and judged: no deviation;
;; refusals at half the ticks at least, one before the section; and, when
;; PAST?, a continuation taken past the section at some tick, answering
;; again.
(define (reentry-reported what pass past?)
  (let ((r (reentry-sweep pass)))
    (display "  ")
    (display what)
    (display ": the call ended before tick ")
    (write (car r))
    (display "; re-entries ")
    (write (caddr r))
    (display "; refused before the section first at tick ")
    (write (cadddr r))
    (newline)
    (list (summarized (cadr r))
          (let ((refused (kind-count (caddr r) 'refused)))
            (if (and (cadddr r) (>= (* 2 refused) (car r)))
                'refused-before-the-section-and-at-half-the-ticks
                (list 'refused refused 'of (car r) 'before-first-at (cadddr r))))
          (cond ((not past?) 'not-asked)
                ((> (kind-count (caddr r) 'again) 0) 'taken-past-the-section-at-a-tick)
                (else (list 'none-taken-past-the-section (caddr r)))))))

(engine-row "the load re-entered through a continuation a timer's handler took at each tick from 1 until the call ends, called once the call has returned, no collect request in its runs: taken before the section, it raises &sqlite-closed, refused, the init not run again; taken past it, it answers again, no init; refused at half the ticks at least and at some before the section; a whole new call, its own init, only below every refusal before the section"
  (list '() 'refused-before-the-section-and-at-half-the-ticks 'not-asked)
  (lambda () (reentry-reported "load-extension! re-entered" 'high #f)))

(engine-row "the same, its runs under a collect trip of 256 bytes: the same verdicts, and at some tick the continuation is taken past the section, the re-entry answering again with no init"
  (list '() 'refused-before-the-section-and-at-half-the-ticks 'taken-past-the-section-at-a-tick)
  (lambda () (reentry-reported "load-extension! re-entered, low trip" 'low #t)))

;; --- the caller's own strings, changed between an expiry and its resume -------------------------
;; The caller's code runs between an engine's expiry and its resume, and
;; can change the strings it handed the verb. The verb checks a copy and
;; hands C that copy: so a change made before the check is refused by the
;; check's own rule, and one made after it reaches nothing. A verb that
;; checked one string and handed C another would let the changed one
;; through: a relative path to dlopen, which SQLite then refuses, or an
;; entry point holding U+0000 to call-with-c-string, which refuses it by a
;; rule of its own.

;; caller-at : Positive-Integer (-> (Listof Any)) ((Listof Any) -> Any) -> (List Any Any)
;; The load at FUEL on a fresh connection, its arguments after the
;; database MAKE-ARGS' fresh strings, one slice; expired, MUTATE! changes
;; them, then the remainder is resumed to its end: what it answered, or
;; (completed V) where the first slice completed; and chez_half after.
(define (caller-at fuel make-args mutate!)
  (quieted!)
  (let* ((db (opted))
         (args (make-args))
         (r (slice (make-engine (lambda () (attempt (lambda () (apply load-extension! db args) 'loaded))))
                   fuel))
         (answer (if (eq? (car r) 'completed)
                     (list 'completed (cadr r))
                     (begin (mutate! args) (finish (cadr r)))))
         (h (half db)))
    (close-answer db)
    (list answer h)))

;; caller-sweep : (-> (Listof Any)) ((Listof Any) -> Any) Symbol -> (List Any (Listof Any) Natural Natural)
;; caller-at at every fuel from 1 until the first slice completes: that
;; fuel; the fuels that deviated; and how many loaded, chez_half present,
;; and how many were refused by RULE, chez_half absent.
(define (caller-sweep make-args mutate! rule)
  (let ((refusal (list 'raised (list 'assertion-violation 'load-extension! (list rule '(kind string))))))
    (let loop ((fuel 1) (deviations '()) (loads 0) (refusals 0))
      (let ((r (caller-at fuel make-args mutate!)))
        (cond ((and (pair? (car r)) (eq? (car (car r)) 'completed))
               (list fuel (reverse deviations) loads refusals))
              ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) loads refusals))
              ((equal? r '(loaded present)) (loop (+ fuel 1) deviations (+ loads 1) refusals))
              ((equal? r (list refusal '(absent error))) (loop (+ fuel 1) deviations loads (+ refusals 1)))
              (else (loop (+ fuel 1) (cons (cons fuel r) deviations) loads refusals)))))))

;; caller-reported : String Any -> Any
(define (caller-reported what r)
  (display "  ")
  (display what)
  (display ": completed without expiring at fuel ")
  (write (car r))
  (display "; loaded at ")
  (write (caddr r))
  (display " fuels, refused at ")
  (write (cadddr r))
  (newline)
  (list (summarized (cadr r))
        (if (and (> (caddr r) 0) (> (cadddr r) 0)) 'both-seen (list 'loads (caddr r) 'refusals (cadddr r)))))

(engine-row "the caller's path changed between an expiry and its resume, its / made x, at every fuel until the load completes unexpired: the load answers with chez_half present, the change made after the check, or is refused path-not-absolute, made before it; never a relative path handed to C; both are seen"
  (list '() 'both-seen)
  (lambda ()
    (caller-reported "the caller's path changed"
                     (caller-sweep (lambda () (list (string-copy ext)))
                                   (lambda (args) (string-set! (car args) 0 #\x))
                                   'path-not-absolute))))

(engine-row "the caller's entry point changed between an expiry and its resume, its last character made U+0000, at every fuel until the load completes unexpired: the named variant's load answers with chez_half present, or is refused entry-point-holds-nul; never the changed string handed on; both are seen"
  (list '() 'both-seen)
  (lambda ()
    (caller-reported "the caller's entry point changed"
                     (caller-sweep (lambda () (list (string-copy ext-named) (string-copy "chez_named_init")))
                                   (lambda (args)
                                     (let ((s (cadr args))) (string-set! s (- (string-length s) 1) #\nul)))
                                   'entry-point-holds-nul))))

;; --- depth ---------------------------------------------------------------------------------------

;; depth-of : (-> Any) -> (List Any Any)
;; The interrupt depth a with-exception-handler handler of THUNK's raise
;; ran at, depth-1 outside any critical section, and what was raised.
(define (depth-of thunk)
  (let* ((at #f)
         (r (guard (e (#t (list 'raised (what-raised e))))
              (with-exception-handler
               (lambda (c)
                 (unless at
                   (set! at (let ((n (disable-interrupts)))
                              (enable-interrupts)
                              (string->symbol (string-append "depth-" (number->string n))))))
                 (raise c))
               (lambda () (thunk) 'no-raise)))))
    (list at r)))

;; refused-depth : -> Any
;; At the first fuel from 1 whose remainder, resumed to its end twice, is
;; refused the second time, that refusal's handler depth and what it raised,
;; and the fuel; or none-refused.
(define (refused-depth)
  (let loop ((fuel 1))
    (quieted!)
    (let* ((db (opted))
           (r (slice (make-engine (lambda () (depth-of (lambda () (load-extension! db ext))))) fuel)))
      (if (eq? (car r) 'completed)
          (begin (close-answer db) 'none-refused)
          (let* ((first (finish (cadr r)))
                 (second (finish (cadr r))))
            (close-answer db)
            (if (and (list? second) (equal? (cadr second) refused-answer))
                (list second fuel)
                (loop (+ fuel 1))))))))

(engine-row "a refused run raises &sqlite-closed after its section: at the first fuel whose remainder's second resume is refused, a with-exception-handler handler of the refusal runs at interrupt depth 1"
  (list 'depth-1 refused-answer)
  (lambda ()
    (let ((r (refused-depth)))
      (if (pair? r) (car r) r))))

(test-equal "the pin closes, and every count is zero at the end"
  zero-counts
  (begin
    (when (a-database? pin) (close-answer pin))
    (native-counts)))

(test-end "load-extension-engines")

(exit (suite-exit-status runner))
