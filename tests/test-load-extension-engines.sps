#!r6rs
;;; The suite for load-extension! under engines and a timer's continuations
;;; (ADR-0021, decision 7; ADR-0016, amended in M3 slice 3 and in M3's
;;; closing review; the M4 plan, sections 4.4 and 4.7, and section 5, item
;;; 4), in (chez-sqlite3 private extension). The call's one section claims
;;; its claim's position 0, inside the section: a run the call has passed is
;;; refused there, touching nothing. Every load runs the extension's init
;;; again (the research, L4), so a whole call is counted by its effect, the
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
;;;                  whatever the runs answered, two only where the fuel's
;;;                  control made a whole new call. No tick falls after the
;;;                  section, which is the call's last work, so no remainder
;;;                  is taken past it: R1 lies before it with R, and the
;;;                  sweep prints how many trials found otherwise
;;;   re-entered     a continuation a timer's handler took at each tick of the
;;;                  call, called once the call has returned: refused, or
;;;                  past the section answering again, never the init run
;;;                  again but by a whole new call, below a refusal the sweep
;;;                  sees itself
;;;
;;; Each trial runs on a fresh connection, opened with the opt-in outside
;;; the engine, and a fresh engine. A pin, a connection of the suite's that
;;; loaded the extension first and stays open, keeps the file loaded, so the
;;; count reads across trials, each trial's inits the count's growth over
;;; it, read on the pin. An engine spends no ticks inside a critical
;;; section, so the fuels measure the Scheme work between the call's
;;; sections (.plans/traps.md). Each fuel and tick begins with a collection,
;;; collect-trip-bytes raised far above what its runs allocate, so no
;;; collect request falls in them (.plans/research/m3-slice-5/). Each bound
;;; on a whole new call is a refusal the sweep sees itself, never a refused
;;; call's fuel or a control on another call (AGENTS.md).
;;;
;;; Where the library lacks sqlite3_load_extension, no connection can opt
;;; in: each row is printed unavailable, and the open's refusal asserted in
;;; its place (ADR-0005, amended).
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
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
      (guard (e (#t (list 'raised (describe e)))) (build-extensions dir))
      (list 'no-scratch dir)))

(define ext (extension-path built 'default))

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

(test-equal "tests/extension.c's default variant compiles, and, where the library has sqlite3_load_extension, the pin loads it, its count 1"
  (list 'built (if (eq? available #t) 1 'no-pin))
  (list (if (and (list? built) (assq 'default built)) 'built built)
        (if (eq? available #t) (if (a-database? pin) (pin-inits) pin) 'no-pin)))

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

;; --- resumed twice ------------------------------------------------------------------------------

;; twice : Positive-Integer -> (List Boolean Symbol (Listof Any) Boolean)
;; The load at FUEL on a fresh connection, one slice. Completed: (#f none
;; () #f). Expired, its remainder is resumed to its end, FIRST, which must
;; answer with one init; then resumed again, SECOND: refused, &sqlite-closed,
;; no init; again, answering past the section, no init; or new, a whole new
;; call, answering with one init of its own. Last, whether the init had run
;; at the expiry.
(define (twice fuel)
  (let* ((db (opted))
         (before (pin-inits))
         (r (slice (make-engine (load-thunk db)) fuel)))
    (if (eq? (car r) 'completed)
        (begin (close-answer db) (list #f 'none '() #f))
        (let* ((more (cadr r))
               (at-expiry (pin-inits))
               (first (finish more))
               (after-first (pin-inits))
               (second (finish more))
               (after-second (pin-inits))
               (grew (and (integer? after-first) (integer? after-second) (- after-second after-first)))
               (kind (cond ((and (equal? second refused-answer) (eqv? grew 0)) 'refused)
                           ((and (eq? second 'loaded) (eqv? grew 0)) 'again)
                           ((and (eq? second 'loaded) (eqv? grew 1)) 'new)
                           (else 'other)))
               (h (half db)))
          (close-answer db)
          (list #t kind
                (append (if (eq? first 'loaded) '() (list (list 'first first)))
                        (if (and (integer? before) (integer? after-first) (= (- after-first before) 1)) '()
                            (list (list 'first-inits before after-first)))
                        (if (eq? kind 'other) (list (list 'second second grew)) '())
                        (if (eq? h 'present) '() (list (list 'half h))))
                (and (integer? at-expiry) (integer? before) (> at-expiry before)))))))

;; twice-sweep : -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
;; twice at every fuel from 1 until the load completes without expiring:
;; that fuel; each fuel's deviations; how many fuels each kind of second
;; resume came at; and the first fuel at which a remainder taken before the
;; section, no init at its expiry, was refused, the sweep's own bound: a
;; whole new call past it deviates.
(define (twice-sweep)
  (let loop ((fuel 1) (deviations '()) (kinds '()) (refused-at #f))
    (quieted!)
    (let* ((r (twice fuel))
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

(engine-row "the load's remainder resumed twice, at every fuel from 1 until it completes without expiring, each fuel on a fresh connection: resumed to its end it answers, the init run once; resumed again, it raises &sqlite-closed, refused at its section, the init not run again, at half the fuels at least and at some before the section; or, taken past the section, it answers again, no init; a whole new call, its own init, comes only below every refusal before the section; chez_half present"
  (list '() 'refused-before-the-section-and-at-half-the-fuels)
  (lambda ()
    (let ((r (twice-sweep)))
      (display "  load-extension! resumed twice: completed without expiring at fuel ")
      (write (car r))
      (display "; second resumes ")
      (write (caddr r))
      (display "; refused before the section first at fuel ")
      (write (cadddr r))
      (newline)
      (list (if (integer? (car r)) (summarized (cadr r)) (list (car r) (summarized (cadr r))))
            (let* ((kinds (caddr r))
                   (refused (+ (kind-count kinds 'refused) (kind-count kinds 'refused-before))))
              (if (and (cadddr r) (integer? (car r)) (>= (* 2 refused) (car r)))
                  'refused-before-the-section-and-at-half-the-fuels
                  (list 'refused refused 'kinds kinds 'of (car r) 'before-first-at (cadddr r))))))))

;; --- interleaved ----------------------------------------------------------------------------------

;; Trial = (List Symbol Natural (Listof Any) (U 'both 'straddle #f))
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; how many inits the
;; trial ran, read on the pin; what deviated; and, for an interleaved
;; trial, where its remainders lay against the section, each read at its
;; own expiry by whether the init had run: both past it; straddle, R
;; before it and R1, taken later on R's own resume, past it; or #f.

;; judged : Boolean Natural (Listof Any) Any Database -> (List Natural (Listof Any))
;; RUNS' answers, NEW? whether a whole new call may come at the fuel, and
;; GREW the inits the trial ran: each run answered or was refused; one init
;; a call, two only where NEW? lets a whole new call come; chez_half
;; present on DB. The whole calls are counted by their inits, never by the
;; runs that answered: a run past the section answers again, running none.
(define (judged new? grew runs db)
  (let* ((deviations
          (let loop ((rest runs) (found '()))
            (if (null? rest)
                (reverse found)
                (loop (cdr rest)
                      (if (or (eq? (car rest) 'loaded) (equal? (car rest) refused-answer))
                          found
                          (cons (list 'answer (car rest)) found))))))
         (deviations (if (or (eqv? grew 1) (and new? (eqv? grew 2)))
                         deviations
                         (append deviations (list (list 'inits grew)))))
         (h (half db))
         (deviations (if (eq? h 'present) deviations (append deviations (list (list 'half h)))))
         (whole (if (integer? grew) grew 0)))
    (list whole deviations)))

;; interleaved-trial : Natural Natural Boolean -> Trial
(define (interleaved-trial fuel g new?)
  (let* ((db (opted))
         (before (pin-inits))
         (grew (lambda () (let ((now (pin-inits))) (if (and (integer? now) (integer? before)) (- now before) now))))
         (r (slice (make-engine (load-thunk db)) fuel)))
    (let ((t (if (eq? (car r) 'completed)
                 (cons 'completed (append (judged new? (grew) (list (cadr r)) db) (list #f)))
                 (let* ((R (cadr r))
                        (r-past (eqv? (grew) 1))
                        (r1 (slice R g)))
                   (if (eq? (car r1) 'completed)
                       (let ((second (finish R)))
                         (cons 'last (append (judged new? (grew) (list (cadr r1) second) db) (list #f))))
                       (let* ((R1 (cadr r1))
                              (r1-past (eqv? (grew) 1))
                              (second (finish R))
                              (third (finish R1)))
                         (cons 'interleaved
                               (append (judged new? (grew) (list second third) db)
                                       (list (cond ((and r-past r1-past) 'both)
                                                   (r1-past 'straddle)
                                                   (else #f)))))))))))
      (close-answer db)
      t)))

;; interleaved-control : Natural -> (U 'completed (List Boolean Boolean))
;; The load at FUEL on a fresh connection: completed; or whether its
;; remainder, resumed to its end twice, made a whole new call the second
;; time, its own init; and whether it was refused then, taken before the
;; section, no init at its expiry.
(define (interleaved-control fuel)
  (let* ((db (opted))
         (before (pin-inits))
         (r (slice (make-engine (load-thunk db)) fuel)))
    (if (eq? (car r) 'completed)
        (begin (close-answer db) 'completed)
        (let* ((at-expiry (pin-inits))
               (first (finish (cadr r)))
               (n (pin-inits))
               (second (finish (cadr r)))
               (new (and (integer? n) (eqv? (pin-inits) (+ n 1)))))
          (close-answer db)
          (list new (and (eqv? at-expiry before) (not new) (equal? second refused-answer)))))))

;; Sweep = (List Any Natural (Listof Any) Natural Natural Natural (U Natural #f) Natural Natural)
;; The fuel at which the load completes without expiring; how many trials
;; ran; each trial's deviations, with its fuels; the trials whose runs ran
;; an init; those in which two runs made whole calls; the last fuel at
;; which the control made a whole new call, 0 for none; the first fuel at
;; which the control was refused before the section, #f for none; the
;; trials with both remainders past the section, and those straddling it.
(define (interleave-sweep)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (new 0) (last-new 0) (was-new #f)
              (refused-at #f) (past 0) (straddle 0))
    (let* ((made (begin (quieted!) (interleaved-control fuel)))
           (made-new (and (pair? made) (car made)))
           (new? (or made-new was-new))
           (refused-at (or refused-at (and (pair? made) (cadr made) fuel))))
      (if (eq? made 'completed)
          (list fuel trials (reverse deviations) answered new last-new refused-at past straddle)
          (let ((last-new (if made-new fuel last-new)))
            (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (new new)
                        (past past) (straddle straddle))
              (let* ((t (interleaved-trial fuel g new?))
                     (kind (car t))
                     (deviations (if (null? (caddr t)) deviations
                                     (cons (list fuel g (caddr t)) deviations)))
                     (answered (if (> (cadr t) 0) (+ answered 1) answered))
                     (new (if (> (cadr t) 1) (+ new 1) new))
                     (past (if (eq? (cadddr t) 'both) (+ past 1) past))
                     (straddle (if (eq? (cadddr t) 'straddle) (+ straddle 1) straddle))
                     (trials (+ trials 1)))
                (cond ((eq? kind 'completed)
                       (list fuel trials (reverse deviations) answered new last-new refused-at past straddle))
                      ((>= fuel 20000)
                       (list 'no-completion-by-20000 trials (reverse deviations) answered new last-new
                             refused-at past straddle))
                      ((eq? kind 'last)
                       (floop (+ fuel 1) trials deviations answered new last-new made-new refused-at past
                              straddle))
                      (else (gloop (+ g 1) trials deviations answered new past straddle))))))))))

(engine-row "the load's remainder R, taken at every fuel from 1 until the load completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1, each trial on a fresh connection and engine: each run answers or is refused with &sqlite-closed; the init runs once a call, counted on the pin whatever the runs answered, twice only where the fuel's control made a whole new call; chez_half present; trials run an init three a fuel on average, so no remainder served two trials; and the control is refused before the section at some fuel, every whole new call below the first"
  (list '() 'three-a-fuel 'whole-new-calls-below-a-refusal)
  (lambda ()
    (let ((run (interleave-sweep)))
      (display "  load-extension!, interleaved: completed without expiring at fuel ")
      (write (car run))
      (display "; trials ")
      (write (cadr run))
      (display "; trials running an init ")
      (write (list-ref run 3))
      (display "; both past the section in ")
      (write (list-ref run 7))
      (display "; R before it and R1 past it in ")
      (write (list-ref run 8))
      (display "; whole new calls ")
      (write (list-ref run 4))
      (display "; the last fuel at which the control made one ")
      (write (list-ref run 5))
      (display ", below the first at which it was refused before the section, ")
      (write (list-ref run 6))
      (newline)
      (list (if (integer? (car run)) (summarized (caddr run)) (list (car run) (summarized (caddr run))))
            (if (and (integer? (car run)) (>= (list-ref run 3) (* 3 (car run))))
                'three-a-fuel
                (list 'answered (list-ref run 3) 'over (car run)))
            (let ((last-new (list-ref run 5)) (refused-at (list-ref run 6)))
              (if (and refused-at (< last-new refused-at))
                  'whole-new-calls-below-a-refusal
                  (list 'whole-new-calls-not-below-a-refusal last-new refused-at)))))))

;; --- a timer's continuation, re-entered ---------------------------------------------------------

;; reentered-at : Positive-Integer -> (U 'no-capture (List Any Any Any Natural))
;; The load on a fresh connection, a timer's handler taking a continuation
;; at the call's tick I, and the timer then stopped. Once the call has
;; returned, the continuation is called, once, and the call goes on from
;; there. no-capture when tick I fell after the call; else the first
;; return's answer, the re-entry's, how many inits had run at the capture,
;; and how many the re-entry ran, read on the pin.
(define (reentered-at i)
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

;; reentry-sweep : -> (List Natural (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
(define (reentry-sweep)
  (let loop ((i 1) (deviations '()) (kinds '()) (refused-at #f))
    (quieted!)
    (let* ((r (reentered-at i))
           (kind (reentry-kind r))
           (found (append (if (eq? kind 'deviation) (list r) '())
                          (if (and (eq? kind 'new) refused-at) (list (list 'new-past-a-refusal refused-at)) '())))
           (deviations (if (null? found) deviations (cons (cons i found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (eqv? (caddr r) 0) i))))
      (cond ((or (eq? kind 'done) (>= i 20000)) (list i (reverse deviations) kinds refused-at))
            (else (loop (+ i 1) deviations (counted-up kind kinds) refused-at))))))

(engine-row "the load re-entered through a continuation a timer's handler took at each tick from 1 until the call ends, called once the call has returned: taken before the section, it raises &sqlite-closed, refused, the init not run again; taken past it, it answers again, no init; refused at half the ticks at least and at some before the section; a whole new call, its own init, only below every refusal before the section"
  (list '() 'refused-before-the-section-and-at-half-the-ticks)
  (lambda ()
    (let ((r (reentry-sweep)))
      (display "  load-extension! re-entered: the call ended before tick ")
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
                  (list 'refused refused 'of (car r) 'before-first-at (cadddr r))))))))

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
