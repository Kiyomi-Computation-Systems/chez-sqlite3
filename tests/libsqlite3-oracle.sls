#!r6rs
;;; (libsqlite3-oracle): what a libsqlite3 says about itself, read by a C
;;; program compiled at test time, tests/libsqlite3-oracle.c. The suites that
;;; check what chez-sqlite3 reports compare it with this.
;;;
;;;   libsqlite3-oracle  the fields, read from the library at a path
;;;   oracle-fields      their names, in the order the program prints them
;;;   libsqlite3-oracle-rows
;;;                      every row and column of SQL run on :memory: there,
;;;                      each column read in C (the program's --rows mode)
;;;   libsqlite3-oracle-transient
;;;                      the header's SQLITE_TRANSIENT (its --transient mode)
;;;   c-compiler         $CC as a command's words, for every compile
;;;   split-words        a string cut at whitespace
;;;
;;; The program is compiled into a fresh directory of call-with-temp-directory's,
;;; never a fixed path, and removed with it. It dlopens the path it is given,
;;; exactly, and links no libsqlite3 (the program's header). It runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own: the gate takes a child named libsqlite3-oracle, as
;;; it takes Chez (ADR-0005, amended). Measured clean there: 0 errors, nothing
;;; lost, 3,732 bytes still reachable from its dlopen.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/.
(library (libsqlite3-oracle)
  (export libsqlite3-oracle oracle-fields libsqlite3-oracle-rows libsqlite3-oracle-transient
          c-compiler split-words)
  (import (rnrs)
          (chez-sqlite3-testing))

  ;; oracle-fields : (Listof Symbol)
  ;; What the oracle prints, in its order: sqlite3_libversion,
  ;; sqlite3_libversion_number, sqlite3_sourceid, sqlite3_threadsafe, the
  ;; compile options, and sqlite3_errstr of each code asked for. It then
  ;; prints (valgrind . yes) or (valgrind . no): whether it ran under memcheck.
  ;; libsqlite3-oracle answers it after these fields, never among them, so that
  ;; a suite comparing each field with another source leaves it out.
  (define oracle-fields '(version version-number source-id threadsafe compile-options errstr))

  ;; split-words : String -> (Listof String)
  ;; TEXT cut at each run of spaces, tabs and newlines, empty pieces
  ;; dropped.
  (define (split-words text)
    (let loop ((i 0) (start 0) (found '()))
      (define (piece) (if (> i start) (cons (substring text start i) found) found))
      (cond ((= i (string-length text)) (reverse (piece)))
            ((memv (string-ref text i) '(#\space #\tab #\newline))
             (loop (+ i 1) (+ i 1) (piece)))
            (else (loop (+ i 1) start found)))))

  ;; c-compiler : (String -> (U String #f)) -> (Listof String)
  ;; The C compiler as a command's first words: CC, read with GETENV, split
  ;; at whitespace, so CC='ccache gcc' runs ccache with gcc as its first
  ;; argument; ("cc") when CC is unset or blank.
  (define (c-compiler getenv)
    (let ((words (split-words (or (getenv "CC") ""))))
      (if (null? words) '("cc") words)))

  ;; libsqlite3-oracle : (String -> (U String #f)) String (Listof Integer)
  ;;                     -> (U (Listof (Pairof Symbol Any)) (List 'no-oracle Symbol Any))
  ;; Compiles tests/libsqlite3-oracle.c with (c-compiler GETENV), -Wall and
  ;; -Werror into a fresh directory from call-with-temp-directory, runs it on
  ;; PATH and CODES, through (gated-command GETENV ...), and answers what it printed, read as data: (FIELD . VALUE)
  ;; for each of oracle-fields, in order, then (valgrind . yes) or
  ;; (valgrind . no). Anything else is (no-oracle STEP
  ;; EVIDENCE), naming the step that went wrong: compile, run, output (that is
  ;; not the fields), or raised, with the text of a raise, which includes
  ;; mktemp's answer being refused. It never raises. The directory is removed,
  ;; a raise included.
  (define (libsqlite3-oracle getenv path codes)
    (oracle-answer getenv (cons path (map number->string codes)) oracle-fields))

  ;; libsqlite3-oracle-rows : (String -> (U String #f)) String String
  ;;                          -> (U (List (Pairof 'rows (Listof Row)) (Pairof 'valgrind Symbol))
  ;;                                (List 'no-oracle Symbol Any))
  ;; Row = (Listof Column)
  ;; Column = (List (U Bytevector #f) Integer Integer Integer Natural
  ;;                (U Bytevector #f) (U Bytevector #f))
  ;; What the program's --rows mode reads from the library at PATH, running
  ;; SQL on a fresh :memory: database, as libsqlite3-oracle reads its fields:
  ;; (rows ROW ...), each column (NAME TYPE BYTES INT64 BITS TEXT BLOB) as the
  ;; program's header gives them, then the valgrind line; or (no-oracle STEP
  ;; EVIDENCE). The SQL goes as hex of its UTF-8 bytes, so a shell changes
  ;; none of them. It never raises.
  (define (libsqlite3-oracle-rows getenv path sql)
    (oracle-answer getenv (list "--rows" path (utf8-hex sql)) '(rows)))

  ;; libsqlite3-oracle-transient : (String -> (U String #f))
  ;;                               -> (U (List (Pairof 'transient Natural) (Pairof 'valgrind Symbol))
  ;;                                     (List 'no-oracle Symbol Any))
  ;; The header's (uintptr_t)SQLITE_TRANSIENT, as the program compiled here
  ;; prints it, then the valgrind line; or (no-oracle STEP EVIDENCE). It
  ;; loads no library. It never raises.
  (define (libsqlite3-oracle-transient getenv)
    (oracle-answer getenv '("--transient") '(transient)))

  ;; oracle-answer : (String -> (U String #f)) (Listof String) (Listof Symbol)
  ;;                 -> (U (Listof (Pairof Symbol Any)) (List 'no-oracle Symbol Any))
  ;; The program, compiled into a fresh directory and run with ARGUMENTS
  ;; through gated-command: what it printed, when that is (FIELD . VALUE)
  ;; for each of FIELDS in order and then the valgrind line.
  (define (oracle-answer getenv arguments fields)
    (guard (e (#t (list 'no-oracle 'raised (describe e))))
      (call-with-temp-directory
       (lambda (dir)
         (run-oracle getenv (string-append dir "/libsqlite3-oracle") arguments fields)))))

  (define (run-oracle getenv program arguments fields)
    (let ((compiled (capture-command
                     (append (c-compiler getenv)
                             (list "-Wall" "-Werror" "-o" program "tests/libsqlite3-oracle.c"
                                   "-ldl")))))
      (if (not (= (car compiled) 0))
          (list 'no-oracle 'compile compiled)
          (let ((ran (capture-command (gated-command getenv (cons program arguments)))))
            (if (not (= (car ran) 0))
                (list 'no-oracle 'run ran)
                (let ((data (read-all (cadr ran))))
                  (if (and (list? data)
                           (= (length data) (+ (length fields) 1))
                           (for-all (lambda (datum field)
                                      (and (pair? datum) (eq? (car datum) field)))
                                    data (append fields '(valgrind))))
                      data
                      (list 'no-oracle 'output (cadr ran)))))))))

  ;; utf8-hex : String -> String
  ;; TEXT's UTF-8 bytes, two lowercase hex digits each.
  (define (utf8-hex text)
    (let ((digits "0123456789abcdef"))
      (call-with-string-output-port
       (lambda (port)
         (for-each (lambda (b)
                     (put-char port (string-ref digits (div b 16)))
                     (put-char port (string-ref digits (mod b 16))))
                   (bytevector->u8-list (string->utf8 text)))))))

  ;; read-all : String -> (U (Listof Any) #f)
  ;; TEXT read as a sequence of data, or #f when it does not read.
  (define (read-all text)
    (guard (e (#t #f))
      (let ((port (open-string-input-port text)))
        (let loop ((data '()))
          (let ((datum (read port)))
            (if (eof-object? datum)
                (reverse data)
                (loop (cons datum data)))))))))
