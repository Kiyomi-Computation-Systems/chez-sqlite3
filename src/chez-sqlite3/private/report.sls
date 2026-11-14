#!r6rs
;;; (chez-sqlite3 private report): what the loaded libsqlite3 says it is,
;;; for (chez-sqlite3) (ADR-0002, amended; brief §2.6). Each answer is read
;;; from native's report, or asked of the library, at each call.
;;;
;;; Every string and list answered is a fresh copy: the report holds one
;;; string per field, and a caller that changed an answer in place would
;;; otherwise change every later answer.
;;;
;;; Reaching any of these runs native's body, the load: a refused library
;;; raises from there instead, at that reference and every later one.
(library (chez-sqlite3 private report)
  (export sqlite-version sqlite-version-number sqlite-source-id sqlite-library-path
          sqlite-library-source sqlite-compile-option? sqlite-compile-options)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private native)
          (chez-sqlite3 private libsqlite3-info)
          (only (chez-sqlite3 private conditions) shown-value))

  ;; sqlite-version : -> String
  ;; sqlite3_libversion: "3.53.1".
  (define (sqlite-version)
    (string-copy (libsqlite3-info-version (loaded-libsqlite3))))

  ;; sqlite-version-number : -> Natural
  ;; sqlite3_libversion_number: 3053001.
  (define (sqlite-version-number)
    (libsqlite3-info-version-number (loaded-libsqlite3)))

  ;; sqlite-source-id : -> String
  ;; sqlite3_sourceid.
  (define (sqlite-source-id)
    (string-copy (libsqlite3-info-source-id (loaded-libsqlite3))))

  ;; sqlite-library-path : -> String
  ;; The absolute path the library was loaded from.
  (define (sqlite-library-path)
    (string-copy (libsqlite3-info-path (loaded-libsqlite3))))

  ;; sqlite-library-source : -> Symbol
  ;; Where that path came from: override, guix-profile, system, ...
  ;; ((chez-sqlite3 private discovery)'s libsqlite3-sources).
  (define (sqlite-library-source)
    (libsqlite3-info-source (loaded-libsqlite3)))

  ;; sqlite-compile-option? : String -> Boolean
  ;; Whether sqlite3_compileoption_used answers 1 for NAME, which SQLite
  ;; matches without case, with or without its SQLITE_ prefix, up to an =.
  ;; A NAME that is no string is an assertion violation, by its rule and
  ;; shown-value; one holding U+0000 is call-with-c-string's, naming its
  ;; kind; each from sqlite-compile-option?.
  (define (sqlite-compile-option? name)
    (unless (string? name)
      (assertion-violation 'sqlite-compile-option? "an option's name is a string" 'not-a-string
                           (shown-value name)))
    (eqv? (call-with-c-string 'sqlite-compile-option? name sqlite3-compileoption-used) 1))

  ;; sqlite-compile-options : -> (Listof String)
  ;; Every option the library was compiled with, as
  ;; sqlite3_compileoption_get gives them, in its order: "THREADSAFE=1".
  (define (sqlite-compile-options)
    (let loop ((i 0) (found '()))
      (let ((address (sqlite3-compileoption-get i)))
        (if (eqv? address 0)
            (reverse found)
            (loop (+ i 1) (cons (c-string->string address) found)))))))
