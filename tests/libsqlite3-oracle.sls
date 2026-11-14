#!r6rs
;;; (libsqlite3-oracle): what a libsqlite3 says about itself, read by a C
;;; program compiled at test time, tests/libsqlite3-oracle.c. The suites that
;;; check what chez-sqlite3 reports compare it with this.
;;;
;;;   libsqlite3-oracle  the fields, read from the library at a path
;;;   oracle-fields      their names, in the order the program prints them
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
  (export libsqlite3-oracle oracle-fields c-compiler split-words)
  (import (rnrs)
          (chez-sqlite3-testing))

  ;; oracle-fields : (Listof Symbol)
  ;; What the oracle prints, in its order: sqlite3_libversion,
  ;; sqlite3_libversion_number, sqlite3_sourceid, sqlite3_threadsafe, the
  ;; compile options, and sqlite3_errstr of each code asked for.
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
  ;; for each of oracle-fields, in order. Anything else is (no-oracle STEP
  ;; EVIDENCE), naming the step that went wrong: compile, run, output (that is
  ;; not the fields), or raised, with the text of a raise, which includes
  ;; mktemp's answer being refused. It never raises. The directory is removed,
  ;; a raise included.
  (define (libsqlite3-oracle getenv path codes)
    (guard (e (#t (list 'no-oracle 'raised (describe e))))
      (call-with-temp-directory
       (lambda (dir)
         (run-oracle getenv (string-append dir "/libsqlite3-oracle") path codes)))))

  (define (run-oracle getenv program path codes)
    (let ((compiled (capture-command
                     (append (c-compiler getenv)
                             (list "-Wall" "-Werror" "-o" program "tests/libsqlite3-oracle.c"
                                   "-ldl")))))
      (if (not (= (car compiled) 0))
          (list 'no-oracle 'compile compiled)
          (let ((ran (capture-command
                      (gated-command getenv (cons program (cons path (map number->string codes)))))))
            (if (not (= (car ran) 0))
                (list 'no-oracle 'run ran)
                (let ((data (read-all (cadr ran))))
                  (if (and (list? data)
                           (= (length data) (length oracle-fields))
                           (for-all (lambda (datum field)
                                      (and (pair? datum) (eq? (car datum) field)))
                                    data oracle-fields))
                      data
                      (list 'no-oracle 'output (cadr ran)))))))))

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
