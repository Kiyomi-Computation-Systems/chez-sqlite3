#!r6rs
;;; tests/refusal-probe.sps: loads libsqlite3 as chez-sqlite3 does, in a
;;; process of its own, and prints what happened as data, one datum per
;;; line, for the tests/test-library-loading-*.sps suites, through
;;; tests/library-loading.sls, to read. It is not a suite: its name lies outside the
;;; tests/test-*.sps glob, so make test never runs it directly (ADR-0007).
;;;
;;;   refusal-probe.sps [--then-override PATH] [--marker NAME] [--message yes]
;;;                     [--extension-loading yes] [--opens CASES] [--loads CASES]
;;;
;;; It references loaded-libsqlite3 three times, each inside its guard. The
;;; first reference prints what happened:
;;;
;;;   loaded:   (loaded . PATH) (source . SYMBOL) (version . STRING)
;;;             (version-number . N) (source-id . STRING), the report's
;;;             fields; then (threadsafe . N), (chez-sqlite3 private
;;;             native)'s loaded-threadsafe; with --extension-loading,
;;;             (load-extension-available? . BOOLEAN), native's record of the
;;;             optional sqlite3_load_extension; with --opens,
;;;             (opens . RESULTS), below; with --loads, (loads . RESULTS),
;;;             below; and the exit status is 0
;;;   refused:  (reason . SYMBOL) (who . WHO) (path . P) (source . S)
;;;             (detail . D) (candidates . LIST) (library . L)
;;;             (irritants . LIST), and the exit status is 1. WHO is the
;;;             condition's &who. L is #f, or the report read before the
;;;             refusal, as the list (PATH SOURCE VERSION VERSION-NUMBER
;;;             SOURCE-ID). LIST of irritants is the condition's &irritants,
;;;             or #f when it has none. With --message, (message . TEXT)
;;;             follows: the condition's &message, which tests/preflight.sps
;;;             prints as its remedy. Tests never assert it as text
;;;             (ADR-0002); test-library-loading-preflight compares preflight's remedy
;;;             line with it
;;;   anything else raised: (raised WHO TYPES), and the exit status is 2.
;;;             WHO is the condition's &who, or #f; TYPES lists, by name, the
;;;             condition types it is, in a fixed order: serious, error,
;;;             violation, assertion, warning, who, message, irritants,
;;;             library-unavailable. Never its text (ADR-0013)
;;;
;;; With --then-override, CHEZ_SQLITE3_LIBRARY is set to PATH after the
;;; first reference, and (then-override . VALUE) shows what getenv then
;;; reads. The two later references print one line, (again . (A B)). Each is
;;; `same` when the reference returned or raised the very object the first
;;; one did (eq?), else (loaded PATH), (refused REASON) or (raised WHO TYPES). A
;;; load that ran once answers `same` twice; a load that ran again answers a
;;; fresh object.
;;;
;;; Then (counts . ALIST): (chez-sqlite3 private counters)' native-counts,
;;; read once the three references are done. The counters count per
;;; process, and a suite's suite-exit-status reads only its own, so this
;;; process prints its counts, and its suite requires every one zero,
;;; refusals included (ADR-0005).
;;;
;;; With --marker, (marker . present) or (marker . absent) follows: whether
;;; this process has the entry point NAME, as foreign-entry? answers.
;;;
;;; Then (valgrind . yes) or (valgrind . no): whether this process runs under
;;; Valgrind's memcheck, read from /proc/self/maps, which then maps memcheck's
;;; preload. Under make test-memory, the test-library-loading suites run
;;; this probe through the gate's own Valgrind, and require yes there and no
;;; elsewhere, so a child the gate should check that ran outside it fails its
;;; row (ADR-0005).
;;;
;;; Last comes (calls . LOG) when the most recently loaded library has the
;;; entry point decoy_calls, as tests/decoy-libsqlite3.c does: its call log,
;;; read byte by byte from the address the call returns, never through
;;; Chez's string type (ADR-0011).
;;;
;;; With --opens, CASES is one datum, a list of cases, each the arguments of
;;; an open, its filename first. Once the load has succeeded, each case runs
;;; through open-database, then through call-with-database with a procedure
;;; appended, in order, and RESULTS holds one (OPEN CALL CALLED) a case:
;;; CALLED is called or not-called, whether call-with-database called its
;;; procedure, and OPEN and CALL are each what the verb did:
;;;
;;;   (opened)  it answered a database, closed at once; for call-with-
;;;             database, (answered V), the procedure's answer
;;;   (extensions-unavailable WHO KIND DEPTH COUNTS)
;;;             it raised &sqlite-extensions-unavailable: its &who; KIND
;;;             library-condition when it is a &chez-sqlite3-error and no
;;;             &sqlite-error, else other-kind; DEPTH, depth-N, the
;;;             interrupt depth a with-exception-handler handler of the raise
;;;             ran at, depth-1 outside any critical section; COUNTS, native-
;;;             counts read by that handler, before anything unwound
;;;   (sqlite-error WHO CODE DEPTH COUNTS)
;;;             it raised &sqlite-error, its primary code by name
;;;   (assertion WHO IRRITANTS DEPTH COUNTS)
;;;             an assertion violation, by its &who and &irritants
;;;   (raised WHO TYPES)
;;;             anything else, as the first reference's line names it
;;;
;;; Where the library lacks sqlite3_load_extension, as the decoy built
;;; DECOY_LACKS_sqlite3_load_extension does, an open that opts in is refused
;;; before anything opens, and the decoy's call log, which always follows,
;;; shows whether sqlite3_open_v2 was called.
;;;
;;; With --loads, CASES is one datum, a list of cases, each the arguments of
;;; a call of (chez-sqlite3)'s load-extension!, after the open's cases, in
;;; order, and RESULTS holds what each did, as OPEN above shows it: (answered
;;; V) for an answer. A case is data, so no case holds a database: what a
;;; row on the decoy can see is that the verb's library loads where the
;;; library lacks sqlite3_load_extension, that its refusals come at depth 1
;;; with every count zero, and, from the call log, that nothing of SQLite's is
;;; called (the decoy's open always fails, so no connection of it reaches a
;;; load).
;;;
;;; Why eval, and no import of (chez-sqlite3 private native): Chez runs the
;;; libraries a program imports before the program's body, so a guard in the
;;; body never sees a raise from an imported library's body.
;;; Native's body is the load. So this program evaluates (loaded-libsqlite3)
;;; in native's environment inside the guard, and the load runs within it.
;;; The libraries it imports load nothing: conditions and libsqlite3-info
;;; define types and procedures, and the counters count.
(import (rnrs)
        (only (chezscheme) eval environment foreign-entry? foreign-procedure foreign-ref
              putenv getenv disable-interrupts enable-interrupts)
        (chez-sqlite3 private conditions)
        (chez-sqlite3 private libsqlite3-info)
        (chez-sqlite3 private counters))

;; show : Symbol Any -> Void
;; One datum, (KEY . VALUE), on a line of its own.
(define (show key value)
  (write (cons key value))
  (newline))

;; condition-types : Any -> (Listof Symbol)
;; The names of the condition types OBJ is, in a fixed order; none for what
;; is no condition.
(define (condition-types obj)
  (if (condition? obj)
      (let loop ((rest (list (cons 'serious serious-condition?) (cons 'error error?)
                             (cons 'violation violation?) (cons 'assertion assertion-violation?)
                             (cons 'warning warning?) (cons 'who who-condition?)
                             (cons 'message message-condition?)
                             (cons 'irritants irritants-condition?)
                             (cons 'library-unavailable sqlite-library-unavailable?)))
                 (found '()))
        (cond ((null? rest) (reverse found))
              (((cdar rest) obj) (loop (cdr rest) (cons (caar rest) found)))
              (else (loop (cdr rest) found))))
      '()))

;; raised-facts : Any -> (List (U Symbol #f) (Listof Symbol))
;; What a raise is, without its text: its &who, or #f, and its types.
(define (raised-facts obj)
  (list (and (condition? obj) (who-condition? obj) (condition-who obj))
        (condition-types obj)))

;; option : String -> (U String #f)
;; The argument after NAME on the command line, or #f.
(define (option name)
  (let loop ((args (cdr (command-line))))
    (cond ((or (null? args) (null? (cdr args))) #f)
          ((string=? (car args) name) (cadr args))
          (else (loop (cdr args))))))

(define native (environment '(chez-sqlite3 private native)))

;; reference : -> (Pairof Symbol Any)
;; One reference to loaded-libsqlite3: (loaded . INFO), (refused . CONDITION)
;; or (raised . OBJECT).
(define (reference)
  (guard (e ((sqlite-library-unavailable? e) (cons 'refused e))
            (#t (cons 'raised e)))
    (cons 'loaded (eval '(loaded-libsqlite3) native))))

;; info-fields : Libsqlite3-Info -> (List String Symbol String Natural String)
(define (info-fields info)
  (list (libsqlite3-info-path info)
        (libsqlite3-info-source info)
        (libsqlite3-info-version info)
        (libsqlite3-info-version-number info)
        (libsqlite3-info-source-id info)))

;; later : (Pairof Symbol Any) (Pairof Symbol Any) -> Any
;; What a later reference did, against the first.
(define (later first answer)
  (cond ((eq? (cdr answer) (cdr first)) 'same)
        ((eq? (car answer) 'loaded) (list 'loaded (libsqlite3-info-path (cdr answer))))
        ((eq? (car answer) 'refused)
         (list 'refused (sqlite-library-unavailable-reason (cdr answer))))
        (else (cons 'raised (raised-facts (cdr answer))))))

;; read-c-string : Natural -> String
;; The NUL-terminated bytes at ADDRESS, decoded as UTF-8.
(define (read-c-string address)
  (let* ((n (let scan ((i 0))
              (if (eqv? (foreign-ref 'unsigned-8 address i) 0) i (scan (+ i 1)))))
         (bytes (make-bytevector n)))
    (let fill ((i 0))
      (when (< i n)
        (bytevector-u8-set! bytes i (foreign-ref 'unsigned-8 address i))
        (fill (+ i 1))))
    (utf8->string bytes)))

;; under-valgrind? : -> Boolean
;; Whether /proc/self/maps maps memcheck's preload; #f when it cannot be
;; read, as off Linux.
(define (under-valgrind?)
  (guard (e (#t #f))
    (let ((maps (call-with-port
                 (open-file-input-port "/proc/self/maps" (file-options) (buffer-mode block)
                                       (make-transcoder (utf-8-codec)))
                 get-string-all))
          (needle "vgpreload_memcheck"))
      (let ((n (string-length maps)) (m (string-length needle)))
        (let loop ((i 0))
          (cond ((> (+ i m) n) #f)
                ((string=? (substring maps i (+ i m)) needle) #t)
                (else (loop (+ i 1)))))))))

(define first (reference))

;; --- the opens, with --opens --------------------------------------------------------------

;; read-cases : String -> (U (Listof (Listof Any)) (List 'unreadable String))
(define (read-cases text)
  (guard (e (#t (list 'unreadable text)))
    (read (open-string-input-port text))))

;; raise-tag : (List Symbol)
;; What a guard below answers a raise under, so no answer can pass for one.
(define raise-tag (list 'raise-tag))

;; tried : (-> Any) -> (U (List 'answered Any) (List 'raised Any Any))
;; THUNK's answer, or what it raised with what a with-exception-handler
;; handler read as it ran: (depth-N COUNTS), before anything unwound.
(define (tried thunk)
  (let* ((at #f)
         (r (guard (e (#t (list raise-tag e)))
              (with-exception-handler
               (lambda (c)
                 (unless at
                   (set! at (let ((n (disable-interrupts)))
                              (enable-interrupts)
                              (list (string->symbol (string-append "depth-" (number->string n)))
                                    (native-counts)))))
                 (raise c))
               (lambda () (list 'answered (thunk)))))))
    (if (and (pair? r) (eq? (car r) raise-tag))
        (list 'raised (cadr r) at)
        r)))

;; shown : (U (List 'answered Any) (List 'raised Any Any)) (Any -> Any) -> Any
;; TRIED's outcome as RESULTS shows it, ANSWERED showing an answer.
(define (shown outcome answered)
  (if (eq? (car outcome) 'answered)
      (answered (cadr outcome))
      (let* ((e (cadr outcome))
             (at (or (caddr outcome) '(no-depth no-counts)))
             (who (and (condition? e) (who-condition? e) (condition-who e))))
        (cond ((sqlite-extensions-unavailable? e)
               (list 'extensions-unavailable who
                     (if (and (chez-sqlite3-error? e) (not (sqlite-error? e)))
                         'library-condition
                         'other-kind)
                     (car at) (cadr at)))
              ((sqlite-error? e) (list 'sqlite-error who (sqlite-error-code e) (car at) (cadr at)))
              ((assertion-violation? e)
               (list 'assertion who (and (irritants-condition? e) (condition-irritants e))
                     (car at) (cadr at)))
              (else (cons 'raised (raised-facts e)))))))

;; opens : (Listof (Listof Any)) -> (Listof Any)
;; Each case of CASES through both verbs, in order, as RESULTS shows them.
(define (opens cases)
  (let ((public (environment '(chez-sqlite3))))
    (let loop ((rest cases) (found '()))
      (if (not (pair? rest))
          (reverse found)
          (let* ((args (car rest))
                 (called 'not-called)
                 (open (tried (lambda () (apply (eval 'open-database public) args))))
                 (open-shown
                  (shown open
                         (lambda (db)
                           (guard (e (#t (cons 'raised (raised-facts e))))
                             ((eval 'close-database! public) db)
                             '(opened)))))
                 (call (tried (lambda ()
                                (apply (eval 'call-with-database public)
                                       (append args (list (lambda (db) (set! called 'called) 'answered)))))))
                 (call-shown (shown call (lambda (v) (list 'answered v)))))
            (loop (cdr rest) (cons (list open-shown call-shown called) found)))))))

;; loads : (Listof (Listof Any)) -> (Listof Any)
;; Each case of CASES through load-extension!, in order, as RESULTS shows
;; them.
(define (loads cases)
  (let ((load (eval 'load-extension! (environment '(chez-sqlite3)))))
    (let loop ((rest cases) (found '()))
      (if (not (pair? rest))
          (reverse found)
          (loop (cdr rest)
                (cons (shown (tried (lambda () (apply load (car rest)))) (lambda (v) (list 'answered v)))
                      found))))))

(define status
  (case (car first)
    ((loaded)
     (let ((fields (info-fields (cdr first))))
       (show 'loaded (list-ref fields 0))
       (show 'source (list-ref fields 1))
       (show 'version (list-ref fields 2))
       (show 'version-number (list-ref fields 3))
       (show 'source-id (list-ref fields 4))
       (show 'threadsafe (guard (e (#t (cons 'raised (raised-facts e))))
                           (eval '(loaded-threadsafe) native)))
       (when (option "--extension-loading")
         (show 'load-extension-available?
               (guard (e (#t (cons 'raised (raised-facts e))))
                 (eval 'load-extension-available? native))))
       (let ((cases (option "--opens")))
         (when cases
           (show 'opens (let ((read (read-cases cases)))
                          (if (and (list? read) (pair? read) (not (eq? (car read) 'unreadable)))
                              (opens read)
                              read)))))
       (let ((cases (option "--loads")))
         (when cases
           (show 'loads (let ((read (read-cases cases)))
                          (if (and (list? read) (pair? read) (not (eq? (car read) 'unreadable)))
                              (guard (e (#t (cons 'raised (raised-facts e)))) (loads read))
                              read)))))
       0))
    ((refused)
     (let ((e (cdr first)))
       (show 'reason (sqlite-library-unavailable-reason e))
       (show 'who (and (who-condition? e) (condition-who e)))
       (show 'path (sqlite-library-unavailable-path e))
       (show 'source (sqlite-library-unavailable-source e))
       (show 'detail (sqlite-library-unavailable-detail e))
       (show 'candidates (sqlite-library-unavailable-candidates e))
       (show 'library (let ((library (sqlite-library-unavailable-library e)))
                        (and library (info-fields library))))
       (show 'irritants (and (irritants-condition? e) (condition-irritants e)))
       (when (option "--message")
         (show 'message (and (message-condition? e) (condition-message e))))
       1))
    (else
     (show 'raised (raised-facts (cdr first)))
     2)))

(let ((path (option "--then-override")))
  (when path
    (putenv "CHEZ_SQLITE3_LIBRARY" path)
    (show 'then-override (getenv "CHEZ_SQLITE3_LIBRARY"))))

(let* ((second (reference))
       (third (reference)))
  (show 'again (list (later first second) (later first third))))

(show 'counts (native-counts))

(let ((marker (option "--marker")))
  (when marker
    (show 'marker (if (foreign-entry? marker) 'present 'absent))))

(show 'valgrind (if (under-valgrind?) 'yes 'no))

(when (foreign-entry? "decoy_calls")
  (show 'calls (read-c-string ((foreign-procedure "decoy_calls" () uptr)))))

(exit status)
