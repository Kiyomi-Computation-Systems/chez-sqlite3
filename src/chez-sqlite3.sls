#!r6rs
;;; (chez-sqlite3): SQLite for Chez Scheme. The public library.
;;;
;;; It defines nothing: every name is re-exported from the private library
;;; that defines it (ADR-0009). So a reference runs that library alone, and a
;;; condition's predicate or accessor loads no libsqlite3: a program can test
;;; for &sqlite-library-unavailable around an eval of the first name that
;;; loads. Every name that reaches libsqlite3 runs the load at its first
;;; reference, once per process (ADR-0002).
;;;
;;; A connection belongs to the thread that opened it, and is closed
;;; explicitly: no collection closes one (ADR-0010, ADR-0012).
(library (chez-sqlite3)
  (export
   ;; --- connections (chez-sqlite3 private connection) ---
   ;; open-database : String Symbol ... -> Database
   ;;   options: read-only | read-write | create | uri | memory | no-follow | no-mutex
   open-database
   ;; close-database! : Database -> Void
   close-database!
   ;; call-with-database : String Symbol ... (Database -> A ...) -> A ...
   call-with-database
   ;; database? : Any -> Boolean
   database?

   ;; --- the library (chez-sqlite3 private report) ---
   ;; sqlite-version : -> String
   sqlite-version
   ;; sqlite-version-number : -> Natural
   sqlite-version-number
   ;; sqlite-source-id : -> String
   sqlite-source-id
   ;; sqlite-library-path : -> String
   sqlite-library-path
   ;; sqlite-library-source : -> Symbol
   sqlite-library-source
   ;; sqlite-compile-option? : String -> Boolean
   sqlite-compile-option?
   ;; sqlite-compile-options : -> (Listof String)
   sqlite-compile-options

   ;; --- conditions (chez-sqlite3 private conditions) ---
   ;; chez-sqlite3-error? : Any -> Boolean
   chez-sqlite3-error?
   ;; sqlite-error? : Any -> Boolean
   sqlite-error?
   ;; sqlite-error-code : SqliteError -> (U Symbol Integer)
   sqlite-error-code
   ;; sqlite-error-extended-code : SqliteError -> (U Symbol Integer)
   sqlite-error-extended-code
   ;; sqlite-error-message : SqliteError -> String
   sqlite-error-message
   ;; sqlite-error-sql : SqliteError -> (U String #f)
   sqlite-error-sql
   ;; sqlite-error-offset : SqliteError -> (U Natural #f)
   sqlite-error-offset
   ;; sqlite-library-unavailable? : Any -> Boolean
   sqlite-library-unavailable?
   ;; sqlite-library-unavailable-reason : SqliteLibraryUnavailable -> Symbol
   sqlite-library-unavailable-reason
   ;; sqlite-library-unavailable-path : SqliteLibraryUnavailable -> (U String #f)
   sqlite-library-unavailable-path
   ;; sqlite-library-unavailable-source : SqliteLibraryUnavailable -> (U Symbol #f)
   sqlite-library-unavailable-source
   ;; sqlite-library-unavailable-detail : SqliteLibraryUnavailable -> Any
   sqlite-library-unavailable-detail
   ;; sqlite-library-unavailable-candidates : SqliteLibraryUnavailable -> (Listof String)
   sqlite-library-unavailable-candidates
   ;; sqlite-wrong-thread? : Any -> Boolean
   sqlite-wrong-thread?
   ;; sqlite-wrong-thread-owner : SqliteWrongThread -> Natural
   sqlite-wrong-thread-owner
   ;; sqlite-wrong-thread-caller : SqliteWrongThread -> Natural
   sqlite-wrong-thread-caller
   ;; sqlite-closed? : Any -> Boolean
   sqlite-closed?)
  (import (chez-sqlite3 private require-threaded)
          (only (chez-sqlite3 private connection)
                open-database close-database! call-with-database database?)
          (only (chez-sqlite3 private report)
                sqlite-version sqlite-version-number sqlite-source-id sqlite-library-path
                sqlite-library-source sqlite-compile-option? sqlite-compile-options)
          (only (chez-sqlite3 private conditions)
                chez-sqlite3-error?
                sqlite-error? sqlite-error-code sqlite-error-extended-code sqlite-error-message
                sqlite-error-sql sqlite-error-offset
                sqlite-library-unavailable? sqlite-library-unavailable-reason
                sqlite-library-unavailable-path sqlite-library-unavailable-source
                sqlite-library-unavailable-detail sqlite-library-unavailable-candidates
                sqlite-wrong-thread? sqlite-wrong-thread-owner sqlite-wrong-thread-caller
                sqlite-closed?)))
