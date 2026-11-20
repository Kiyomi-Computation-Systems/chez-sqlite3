#!r6rs
;;; (extension-build): the loadable extension the load-extension! suites
;;; load, tests/extension.c, compiled at test time (ADR-0021, consequences).
;;;
;;;   extension-suffix   the suffix SQLite appends to a path it cannot
;;;                      load, and the one the built files take: .so, or
;;;                      .dylib on macOS, by Chez's machine type
;;;   build-extensions   each variant compiled into a directory, with $CC
;;;                      -Wall -Werror against the lane's sqlite3ext.h:
;;;                      their paths, or the first compile's whole failure
;;;   built-where-loadable
;;;                      build-extensions where native records
;;;                      sqlite3_load_extension, and (unavailable), nothing
;;;                      compiled, where it records none
;;;   extension-path     one variant's path, from build-extensions' answer
;;;
;;; The compiler is a test oracle, never an install dependency: a missing
;;; compiler or header fails the compile, and the suite's first row names it,
;;; never a skip (ADR-0001). The one exception is a library that lacks
;;; sqlite3_load_extension, as Apple's does: no connection of it can load an
;;; extension, so the build is named unavailable there, and the suites assert
;;; the opt-in's refusal in its place. $CC is read as the constants' oracle
;;; reads it, (libsqlite3-oracle)'s c-compiler, and the header comes from the
;;; compiler's own path, which C_INCLUDE_PATH leads on a floor run. Nothing
;;; here runs at import: each compile runs when a suite calls for it.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path. It loads no libsqlite3.
(library (extension-build)
  (export extension-suffix build-extensions built-where-loadable extension-path extension-variants)
  (import (rnrs)
          (chez-sqlite3-testing)
          (only (libsqlite3-oracle) c-compiler)
          (only (chezscheme) getenv machine-type))

  ;; mac? : Boolean
  ;; Whether Chez runs on macOS: its machine types end in osx.
  (define mac?
    (let* ((name (symbol->string (machine-type)))
           (n (string-length name)))
      (and (>= n 3) (string=? (substring name (- n 3) n) "osx"))))

  ;; extension-suffix : String
  ;; .so on Linux, .dylib on macOS: what SQLite appends to a path that does
  ;; not load, by its own azEndings.
  (define extension-suffix (if mac? ".dylib" ".so"))

  ;; shared-flags : (Listof String)
  (define shared-flags (if mac? '("-dynamiclib") '("-shared" "-fPIC")))

  ;; extension-variants : (Listof (List Symbol String (Listof String)))
  ;; Each variant: its name, its file's base name, and its switches.
  (define extension-variants
    '((default "ext" ())
      (named "ext-named" ("-DEXT_NAMED"))
      (derived "libchezext" ("-DEXT_DERIVED"))
      (failing "ext-failing" ("-DEXT_FAILING"))
      (exec-failing "ext-exec-failing" ("-DEXT_EXEC_FAILING"))
      (leaves "ext-leaves" ("-DEXT_LEAVES_STATEMENT"))))

  (define source "tests/extension.c")

  ;; compiled : String (List Symbol String (Listof String))
  ;;            -> (U (Pairof Symbol String) (List 'not-built Symbol Any))
  ;; VARIANT compiled into DIR: (NAME . PATH), or (not-built NAME ANSWER),
  ;; ANSWER the compiler's whole answer, or what was raised.
  (define (compiled dir variant)
    (let ((path (string-append dir "/" (cadr variant) extension-suffix)))
      (let ((answer (guard (e (#t (list 'raised (describe e))))
                      (capture-command
                       (append (c-compiler getenv)
                               (list "-Wall" "-Werror")
                               shared-flags
                               (list "-o" path source)
                               (caddr variant))))))
        (if (and (pair? answer) (eqv? (car answer) 0))
            (cons (car variant) path)
            (list 'not-built (car variant) answer)))))

  ;; build-extensions : String -> (U (Listof (Pairof Symbol String)) (List 'not-built Symbol Any))
  ;; Every variant compiled into DIR, an absolute directory, in
  ;; extension-variants' order: each name and its path; or the first that
  ;; failed, (not-built NAME ANSWER), the rest not tried.
  (define (build-extensions dir)
    (let loop ((rest extension-variants) (built '()))
      (if (null? rest)
          (reverse built)
          (let ((r (compiled dir (car rest))))
            (if (eq? (car r) 'not-built)
                r
                (loop (cdr rest) (cons r built)))))))

  ;; built-where-loadable : Any String
  ;;                        -> (U (Listof (Pairof Symbol String)) (List 'not-built Symbol Any)
  ;;                              (List 'unavailable))
  ;; build-extensions' answer for DIR, unless AVAILABLE, native's record of
  ;; sqlite3_load_extension, is #f: then (unavailable), and nothing is
  ;; compiled or written. Any other value, the record unread among them,
  ;; builds, so a missing compiler or header fails there.
  (define (built-where-loadable available dir)
    (if (eq? available #f)
        '(unavailable)
        (build-extensions dir)))

  ;; extension-path : Any Symbol -> String
  ;; NAME's path in BUILT, build-extensions' answer; when BUILT is a
  ;; failure, or holds no NAME, a path no file stands at, so a load of it
  ;; fails, and the build's own row names why.
  (define (extension-path built name)
    (let ((found (and (list? built) (for-all pair? built) (assq name built))))
      (if found (cdr found) "/nonexistent/chez-sqlite3-extension-not-built"))))
