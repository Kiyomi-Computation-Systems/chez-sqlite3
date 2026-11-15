#!r6rs
;;; (library-loading): what the two suites that load libsqlite3 end to end
;;; share, tests/test-library-loading-decoys.sps and
;;; tests/test-library-loading-real.sps (ADR-0002, ADR-0003, ADR-0010,
;;; ADR-0013). They were one suite, tests/test-library-loading.sps, until it
;;; passed 450 s under the memory gate on CI, three quarters of
;;; MEMORY_TIMEOUT, where ADR-0005 (amended) splits it in two. Its cost is its
;;; children, each under a Valgrind of its own there, so each suite runs about
;;; half of them.
;;;
;;;   the probe         spawn a child through env and gated-command, and
;;;                     read what tests/refusal-probe.sps printed, as data
;;;   the answers       a probe's whole expected answer: loaded, refused,
;;;                     with its counts, its Valgrind line and its call log
;;;   the floors        the decoy's versions, from packaging/floors.sexp
;;;   the entries       every entry point (chez-sqlite3 private native)
;;;                     binds, and its partition: each suite's half, by the
;;;                     suite's file name. Each entry's missing-api row runs
;;;                     in exactly one suite, and a row in each holds that
;;;                     the halves, merged in the convention table's order,
;;;                     are its names, each once
;;;   the decoys        each build of tests/decoy-libsqlite3.c, compiled in
;;;                     a suite's scratch directory, and a row on one
;;;   the missing-api rows
;;;                     one per entry point of a half
;;;
;;; Each suite keeps its own runner, scratch directory and floors, and names
;;; the helpers here that take them by the names its rows use. Nothing here
;;; runs at import but reading two environment variables: every child, every
;;; compile and every row runs when a suite calls for it.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path. It loads no libsqlite3, and each suite requires as much at its end.
(library (library-loading)
  (export chez set? string-prefix? string-suffix? absolute? join
          spawn-in probe-with probe override switch-args as-data
          once no-native-objects gated? valgrind-line
          outcome report loaded-lines refused-lines report-of loaded refused
          read-floor-values
          report-entries rest-entries every-entry decoy-halves suite-half merge-halves
          lacks-build decoy-builds compile-decoys decoy-status decoy-row-in
          read-switch the-report-three threadsafe-call initialize-call log-of memory-used-call
          loaded-calls every-call code-of missing-api-rows)
  (import (rnrs)
          (srfi :64)
          (chez-sqlite3-testing)
          (libsqlite3-oracle)
          (floors)
          (only (chezscheme) getenv)
          (chez-sqlite3 private verify)
          (chez-sqlite3 private constants))

  ;; --- strings ---------------------------------------------------------------

  ;; string-prefix? : String String -> Boolean
  (define (string-prefix? prefix s)
    (let ((n (string-length s)) (m (string-length prefix)))
      (and (>= n m) (string=? (substring s 0 m) prefix))))

  ;; string-suffix? : String String -> Boolean
  (define (string-suffix? suffix s)
    (let ((n (string-length s)) (m (string-length suffix)))
      (and (>= n m) (string=? (substring s (- n m) n) suffix))))

  ;; absolute? : Any -> Boolean
  (define (absolute? s)
    (and (string? s) (string-prefix? "/" s)))

  ;; join : (Listof String) -> String
  ;; ENTRIES with one space between: a decoy's call log.
  (define (join entries)
    (if (null? entries)
        ""
        (fold-left (lambda (all entry) (string-append all " " entry))
                   (car entries) (cdr entries))))

  ;; set? : Any -> Boolean
  (define (set? value) (and (string? value) (not (string=? value ""))))

  ;; --- the processes a suite spawns ----------------------------------------------

  ;; chez : (U String #f)
  ;; The Chez to spawn: the Makefile exports CHEZ, so a suite spawns the Chez
  ;; that runs it. Each suite's first row requires it set.
  (define chez (getenv "CHEZ"))

  ;; read-data : String -> (U (Listof Any) (List 'unreadable String))
  ;; TEXT read as a sequence of data.
  (define (read-data text)
    (guard (e (#t (list 'unreadable text)))
      (let ((port (open-string-input-port text)))
        (let loop ((data '()))
          (let ((datum (read port)))
            (if (eof-object? datum)
                (reverse data)
                (loop (cons datum data))))))))

  ;; env-order : (Listof String) -> (Listof String)
  ;; ENV-ARGS with every -u NAME pair first, then each NAME=VALUE, each group in
  ;; its own order: env reads -u only before the first assignment.
  (define (env-order env-args)
    (let loop ((rest env-args) (unsets '()) (sets '()))
      (cond ((null? rest) (append (reverse unsets) (reverse sets)))
            ((and (string=? (car rest) "-u") (pair? (cdr rest)))
             (loop (cddr rest) (cons* (cadr rest) "-u" unsets) sets))
            (else (loop (cdr rest) unsets (cons (car rest) sets))))))

  ;; spawn-in : String (Listof String) String (Listof String)
  ;;            -> (U (List Integer String String) (List 'raised String))
  ;; Runs PROGRAM with ARGS in a fresh Chez with LIBDIRS as its library path,
  ;; under the memory gate's Valgrind when the gate asks (gated-command),
  ;; through env with ENV-ARGS (NAME=VALUE to set, -u NAME to unset): its exit
  ;; status, stdout and stderr. Never env -i: CHEZ and PATH survive
  ;; (.plans/traps.md).
  (define (spawn-in libdirs env-args program args)
    (guard (e (#t (list 'raised (describe e))))
      (capture-command
       (append '("env") (env-order env-args)
               (gated-command getenv (append (list chez "--libdirs" libdirs "--program" program)
                                             args))))))

  (define (spawn env-args program args) (spawn-in "src" env-args program args))

  ;; as-data : (U (List Integer String String) (List 'raised String))
  ;;           -> (U (List Integer (Listof Any) String) (List 'raised String))
  ;; A probe's answer, with what it printed read as data.
  (define (as-data answer)
    (if (eq? (car answer) 'raised)
        answer
        (list (car answer) (read-data (cadr answer)) (caddr answer))))

  ;; probe-with : (Listof String) (Listof String)
  ;;              -> (U (List Integer (Listof Any) String) (List 'raised String))
  ;; tests/refusal-probe.sps under ENV-ARGS, with ARGS.
  (define (probe-with env-args args)
    (as-data (spawn env-args "tests/refusal-probe.sps" args)))

  ;; probe : (Listof String) -> (U (List Integer (Listof Any) String) (List 'raised String))
  (define (probe env-args) (probe-with env-args '()))

  ;; override : String -> String
  (define (override path) (string-append "CHEZ_SQLITE3_LIBRARY=" path))

  ;; switch-args : (U String #f) -> (Listof String)
  ;; CHEZ_SQLITE3_DECOY set to SWITCH, or unset for #f: every child gets one or
  ;; the other, so a value left in this process's environment never reaches a
  ;; row.
  (define (switch-args switch)
    (if switch
        (list (string-append "CHEZ_SQLITE3_DECOY=" switch))
        '("-u" "CHEZ_SQLITE3_DECOY")))

  ;; --- what a probe answers ---------------------------------------------------------

  ;; The probe references loaded-libsqlite3 three times. A load runs once per
  ;; process, whatever it decided, so the two later references answer the very
  ;; object the first did: the report, or the refusal raised again.
  (define once '(again . (same same)))

  ;; Every count zero, whatever the load decided (ADR-0005, decision 4).
  (define no-native-objects '(counts . ((block . 0) (connection . 0) (statement . 0))))

  ;; Under make test-memory, every child runs under the gate's own Valgrind,
  ;; and says so; anywhere else, none does.
  (define gated? (and (getenv "CHEZ_SQLITE3_GATE_CHILD") #t))
  (define valgrind-line (cons 'valgrind (if gated? 'yes 'no)))

  ;; outcome : Integer (Listof Pair) (Listof Pair) (Listof Pair) (U (Listof String) #f)
  ;;           -> Expected
  ;; The probe's whole answer: STATUS; the lines of its first reference, HEAD;
  ;; BEFORE (then-override) and the references' again; the counts; AFTER
  ;; (marker); whether it ran under Valgrind; and the decoy's call log, CALLS,
  ;; as entries, or no calls line for a library without one. Its stderr is
  ;; empty.
  (define (outcome status head before after calls)
    (list status
          (append head before (list once no-native-objects) after (list valgrind-line)
                  (if calls (list (cons 'calls (join calls))) '()))
          ""))

  ;; report : String Natural String -> Report
  ;; A report is what a loaded library says about itself, as the probe prints
  ;; it after the path and source: (version . V) (version-number . N)
  ;; (source-id . ID).
  (define (report version number source-id)
    (list (cons 'version version) (cons 'version-number number) (cons 'source-id source-id)))

  ;; loaded-lines : String Symbol Report Any -> (Listof Pair)
  (define (loaded-lines path source report threadsafe)
    (append (list (cons 'loaded path) (cons 'source source)) report
            (list (cons 'threadsafe threadsafe))))

  ;; refused-lines : Symbol (U String #f) (U Symbol #f) Any (Listof String) Any
  ;;                  (Listof Any) -> (Listof Pair)
  ;; LIBRARY is report-of's list for a refusal made after the version was
  ;; read, else #f. IRRITANTS are the condition's: the path, as the one
  ;; irritant, for each refusal that has a path.
  (define (refused-lines reason path source detail candidates library irritants)
    (list (cons 'reason reason) (cons 'who 'chez-sqlite3) (cons 'path path)
          (cons 'source source) (cons 'detail detail) (cons 'candidates candidates)
          (cons 'library library) (cons 'irritants irritants)))

  ;; report-of : String Symbol Report -> (Listof Any)
  ;; A refusal's library as the probe prints it: path, source, then the
  ;; report's values.
  (define (report-of path source report)
    (cons* path source (map cdr report)))

  ;; loaded : String Symbol Report Any (U (Listof String) #f) -> Expected
  (define (loaded path source report threadsafe calls)
    (outcome 0 (loaded-lines path source report threadsafe) '() '() calls))

  ;; refused : Symbol (U String #f) (U Symbol #f) Any (Listof String) Any
  ;;           (U (Listof String) #f) [(Listof Any)] -> Expected
  (define refused
    (case-lambda
      ((reason path source detail candidates library calls)
       (refused reason path source detail candidates library calls (list path)))
      ((reason path source detail candidates library calls irritants)
       (outcome 1 (refused-lines reason path source detail candidates library irritants)
                '() '() calls))))

  ;; --- the floors ---------------------------------------------------------------------

  ;; read-floor-values : -> (U (List String Natural String Natural) (List 'no-floors Any))
  ;; SQLite's floor from packaging/floors.sexp, its number as
  ;; sqlite3_libversion_number encodes it, and the version one below it, as
  ;; text and number: the decoy's versions (ADR-0008). Never a raise.
  (define (read-floor-values)
    (guard (e (#t (list 'no-floors (describe e))))
      (let* ((floors (read-floors))
             (parts (floor-numbers floors 'sqlite))
             (number (+ (* (car parts) 1000000) (* (cadr parts) 1000) (caddr parts)))
             (below (- number 1)))
        (list (floor-text floors 'sqlite) number (version-number->string below) below))))

  ;; --- the entries and their partition ---------------------------------------------

  ;; The entry points (chez-sqlite3 private native) binds, in its order
  ;; (ADR-0002, amended): the report's three, threadsafe, initialize, and the
  ;; rest, M1's ten and then M2's 21. A thirty-seventh that native binds and
  ;; the decoy lacks refuses the control, and the control's row fails. A row
  ;; holds the list to the convention table's names, whole and in order.
  (define report-entries '("sqlite3_libversion_number" "sqlite3_libversion" "sqlite3_sourceid"))
  (define rest-entries
    '("sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2" "sqlite3_close"
      "sqlite3_errmsg" "sqlite3_errstr" "sqlite3_errcode" "sqlite3_extended_errcode"
      "sqlite3_next_stmt" "sqlite3_memory_used"
      "sqlite3_prepare_v3" "sqlite3_finalize" "sqlite3_step" "sqlite3_reset"
      "sqlite3_clear_bindings" "sqlite3_bind_parameter_count" "sqlite3_bind_parameter_index"
      "sqlite3_bind_null" "sqlite3_bind_int64" "sqlite3_bind_double" "sqlite3_bind_text64"
      "sqlite3_bind_blob64" "sqlite3_column_count" "sqlite3_column_name" "sqlite3_column_type"
      "sqlite3_column_int64" "sqlite3_column_double" "sqlite3_column_text" "sqlite3_column_blob"
      "sqlite3_column_bytes" "sqlite3_error_offset"))
  (define every-entry (append report-entries '("sqlite3_threadsafe" "sqlite3_initialize") rest-entries))

  ;; decoy-halves : (Listof (Pairof String (Listof String)))
  ;; The partition: each suite's file name under tests/, then the entry points
  ;; whose missing-api rows it makes, in native's order. Every other entry
  ;; point goes to each, so each half holds M1's and M2's alike, and each
  ;; suite about half the gated children. A suite finds its half by its own
  ;; file's name (suite-half), so a suite copied from the other cannot run
  ;; the other's half. A row in each suite holds that the halves partition
  ;; the convention table, and another that each suite named is a file.
  (define decoy-halves
    '(("test-library-loading-decoys.sps"
       "sqlite3_libversion_number" "sqlite3_sourceid" "sqlite3_initialize"
       "sqlite3_compileoption_get" "sqlite3_close" "sqlite3_errstr" "sqlite3_extended_errcode"
       "sqlite3_memory_used" "sqlite3_finalize" "sqlite3_reset" "sqlite3_bind_parameter_count"
       "sqlite3_bind_null" "sqlite3_bind_double" "sqlite3_bind_blob64" "sqlite3_column_name"
       "sqlite3_column_int64" "sqlite3_column_text" "sqlite3_column_bytes")
      ("test-library-loading-real.sps"
       "sqlite3_libversion" "sqlite3_threadsafe" "sqlite3_compileoption_used" "sqlite3_open_v2"
       "sqlite3_errmsg" "sqlite3_errcode" "sqlite3_next_stmt" "sqlite3_prepare_v3" "sqlite3_step"
       "sqlite3_clear_bindings" "sqlite3_bind_parameter_index" "sqlite3_bind_int64"
       "sqlite3_bind_text64" "sqlite3_column_count" "sqlite3_column_type" "sqlite3_column_double"
       "sqlite3_column_blob" "sqlite3_error_offset")))

  ;; suite-half : (Listof String) -> (U (Pairof String (Listof String)) #f)
  ;; The half of the suite whose command line is ARGS, (command-line), found
  ;; by its program's file name, without the directories before it; #f for a
  ;; program the partition does not name.
  (define (suite-half args)
    (and (pair? args) (string? (car args))
         (assoc (file-name (car args)) decoy-halves)))

  ;; file-name : String -> String
  ;; PATH after its last slash.
  (define (file-name path)
    (let loop ((i (string-length path)))
      (cond ((= i 0) path)
            ((char=? (string-ref path (- i 1)) #\/) (substring path i (string-length path)))
            (else (loop (- i 1))))))

  ;; merge-halves : (Listof String) (Listof (Listof String)) -> (Listof String)
  ;; HALVES merged in ORDER's order. A merge keeps each half's own order and
  ;; every element of each, so the answer is ORDER exactly when the halves
  ;; partition it, each half in its order: an entry dropped, doubled, out of
  ;; order or not in ORDER shows. A name ORDER lacks sorts after every name in
  ;; it.
  (define (merge-halves order halves)
    (define (rank name)
      (let loop ((rest order) (i 0))
        (cond ((null? rest) i)
              ((equal? (car rest) name) i)
              (else (loop (cdr rest) (+ i 1))))))
    (define (merge a b)
      (let loop ((a a) (b b) (merged '()))
        (cond ((null? a) (append (reverse merged) b))
              ((null? b) (append (reverse merged) a))
              ((<= (rank (car a)) (rank (car b))) (loop (cdr a) b (cons (car a) merged)))
              (else (loop a (cdr b) (cons (car b) merged))))))
    (fold-left merge '() halves))

  ;; --- decoys --------------------------------------------------------------------------

  (define decoy-source "tests/decoy-libsqlite3.c")

  (define (lacks entry) (string-append "-DDECOY_LACKS_" entry))

  ;; lacks-build : String -> String
  ;; The name of the build that leaves ENTRY out.
  (define (lacks-build entry) (string-append "lacks-" entry))

  ;; all-builds : (Listof (Pairof String (Listof String)))
  ;; Each build's name and its switches.
  (define all-builds
    (append (list (list "control")
                  (list "marked" "-DDECOY_MARKER")
                  (list "not-sqlite" "-DDECOY_NOT_SQLITE")
                  (cons "lacks-rest" (map lacks rest-entries)))
            (map (lambda (entry) (list (lacks-build entry) (lacks entry))) every-entry)))

  ;; decoy-builds : (Listof String) -> (Listof (Pairof String (Listof String)))
  ;; The builds NAMES names, in all-builds' order, each once. A name that is
  ;; no build is left out, and the row that uses it finds no such build.
  (define (decoy-builds names)
    (filter (lambda (build) (member (car build) names)) all-builds))

  ;; compile-decoy : (String -> String) FloorValues String (Listof String)
  ;;                 -> (U 0 (List Integer String String) (List 'raised String))
  ;; Compiles the decoy as BUILD at (SO-OF BUILD) under SWITCHES, with the
  ;; floor's versions from FLOOR-VALUES: 0, or the compiler's whole answer when
  ;; it failed.
  (define (compile-decoy so-of floor-values build switches)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((floor-version (car floor-values))
             (floor-number (cadr floor-values))
             (below-version (caddr floor-values))
             (below-number (cadddr floor-values))
             (answer (capture-command
                      (append (c-compiler getenv)
                              (list "-Wall" "-Werror" "-shared" "-fPIC" "-o" (so-of build) decoy-source
                                    (string-append "-DDECOY_VERSION_NUMBER=" (number->string floor-number))
                                    (string-append "-DDECOY_VERSION=\"" floor-version "\"")
                                    (string-append "-DDECOY_BELOW_NUMBER=" (number->string below-number))
                                    (string-append "-DDECOY_BELOW=\"" below-version "\""))
                              switches))))
        (if (eqv? (car answer) 0) 0 answer))))

  ;; compile-decoys : (String -> String) FloorValues (Listof (Pairof String (Listof String)))
  ;;                  -> (Listof (Pairof String Any))
  ;; Every build of BUILDS, compiled once, in order: each name and its status.
  (define (compile-decoys so-of floor-values builds)
    (let loop ((rest builds) (done '()))
      (if (null? rest)
          (reverse done)
          (let ((status (compile-decoy so-of floor-values (caar rest) (cdar rest))))
            (loop (cdr rest) (cons (cons (caar rest) status) done))))))

  ;; decoy-status : (Listof (Pairof String Any)) String -> Any
  ;; BUILD's compile status in COMPILED, or (no-such-build BUILD).
  (define (decoy-status compiled build)
    (cond ((assoc build compiled) => cdr) (else (list 'no-such-build build))))

  ;; decoy-row-in : (String -> String) (String -> Any) String (U String #f) (Listof String) String
  ;;                (String -> Expected) -> Void
  ;; The test DESCRIPTION: the probe, with ARGS, on BUILD, at (SO-OF BUILD),
  ;; under SWITCH; the build's compile, (COMPILED-STATUS BUILD), must have
  ;; answered 0, then EXPECTED of its path. Every row references
  ;; loaded-libsqlite3 three times, so each log asserted whole also shows that
  ;; the load ran once. A suite names it decoy-row, with its own two.
  (define (decoy-row-in so-of compiled-status build switch args description expected)
    (test-equal (string-append "decoy " build
                               (if switch (string-append " under \"" switch "\"") "")
                               ": " description)
      (cons 0 (expected (so-of build)))
      (cons (compiled-status build)
            (probe-with (cons (override (so-of build)) (switch-args switch)) args))))

  ;; The call log's entries, as tests/decoy-libsqlite3.c writes them: first the
  ;; switch it read, then each call.
  (define (read-switch switch) (string-append "decoy(" switch ")"))
  (define the-report-three '("sqlite3_libversion_number()" "sqlite3_libversion()" "sqlite3_sourceid()"))
  (define threadsafe-call "sqlite3_threadsafe()")
  (define initialize-call "sqlite3_initialize()")
  (define (log-of switch . calls) (cons (read-switch switch) calls))
  (define memory-used-call "sqlite3_memory_used()")
  ;; A successful load's six calls: native's step 8 reads the memory baseline
  ;; after initialize. No refusal reaches it.
  (define (loaded-calls switch) (append (every-call switch) (list memory-used-call)))
  (define (every-call switch)
    (append (list (read-switch switch)) the-report-three (list threadsafe-call initialize-call)))

  ;; code-of : Symbol -> (U Integer (List 'no-code Symbol))
  ;; A result code's value, from (chez-sqlite3 private constants), which
  ;; tests/test-constants.sps holds to sqlite3.h. A name it lacks answers
  ;; (no-code NAME), which no probe prints, so that row fails by name.
  (define (code-of name)
    (guard (e (#t (list 'no-code name)))
      (cdr (assq name sqlite-result-codes))))

  ;; missing-api-rows : (String (U String #f) (Listof String) String (String -> Expected) -> Void)
  ;;                    (String -> (Listof Any)) (Listof String) -> Void
  ;; Each entry point of ENTRIES left out, one at a time, through the suite's
  ;; DECOY-ROW: refused by name before anything calls it, never Chez's "no
  ;; entry for". The report's three are each bound before any is called, so a
  ;; library lacking one has had no call, and no report. Every later refusal
  ;; carries the report, (CONTROL-LIBRARY SO).
  (define (missing-api-rows decoy-row control-library entries)
    (for-each
     (lambda (entry)
       (decoy-row (lacks-build entry) #f '()
         (string-append "a library without " entry " is missing-api, naming it")
         (lambda (so)
           (cond ((member entry report-entries)
                  (refused 'missing-api so 'override entry '() #f (log-of "control")))
                 ((string=? entry "sqlite3_threadsafe")
                  (refused 'missing-api so 'override entry '() (control-library so)
                           (apply log-of "control" the-report-three)))
                 ((string=? entry "sqlite3_initialize")
                  (refused 'missing-api so 'override entry '() (control-library so)
                           (append (apply log-of "control" the-report-three) (list threadsafe-call))))
                 (else
                  (refused 'missing-api so 'override entry '() (control-library so)
                           (every-call "control")))))))
     entries)))
