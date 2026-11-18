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
;;; explicitly: no collection closes one (ADR-0010, ADR-0012). A statement
;;; belongs to its connection and its thread, and closing the connection
;;; finalizes it (ADR-0014). Its values are bound and read by
;;; (chez-sqlite3 private statement-values) (ADR-0015). The conveniences run
;;; one statement each, through the connection's statement cache, and finish
;;; it on every path; the counters are SQLite's, read as it keeps them
;;; (ADR-0016, ADR-0020). with-transaction reads autocommit to nest, and again
;;; to learn whether its transaction survived its body (ADR-0017). The open
;;; verbs take a settings list, applied at open and read back (ADR-0018),
;;; db_config's four among it, each one call held by its own answer, and an
;;; open that opts in to extension loading on a library without it refused
;;; by sqlite-extensions-unavailable?'s condition (ADR-0021).
;;; interrupt-database! is the one verb any thread may call, and the close
;;; shuts it out before it finalizes anything (ADR-0019).
(library (chez-sqlite3)
  (export
   ;; --- connections (chez-sqlite3 private open, chez-sqlite3 private connection) ---
   ;; open-database : String (U Symbol Settings) ... -> Database
   ;;   options: read-only | read-write | create | uri | memory | no-follow | no-mutex
   open-database
   ;; close-database! : Database -> Void
   close-database!
   ;; call-with-database : String (U Symbol Settings) ... (Database -> A ...) -> A ...
   call-with-database
   ;;   Settings = (Listof (Pairof Symbol Any))
   ;; database? : Any -> Boolean
   database?
   ;; interrupt-database! : Database -> Void
   interrupt-database!

   ;; --- the conveniences (chez-sqlite3 private conveniences) ---
   ;; execute! : Database String Value ... -> Void
   execute!
   ;; execute-script! : Database String -> Void
   execute-script!
   ;; query : Database String Value ... -> (Listof Row)
   query
   ;; query-row : Database String Value ... -> (U Row #f)
   query-row
   ;; query-fold : Database String (A Row -> A) A Value ... -> A
   query-fold
   ;;   Row = (Vectorof Value)

   ;; --- the counters (chez-sqlite3 private connection) ---
   ;; changes : Database -> Natural
   changes
   ;; total-changes : Database -> Natural
   total-changes
   ;; last-insert-rowid : Database -> Integer
   last-insert-rowid
   ;; in-transaction? : Database -> Boolean
   in-transaction?

   ;; --- transactions (chez-sqlite3 private transaction) ---
   ;; with-transaction : (case-> (Database (-> A ...) -> A ...) (Database Mode (-> A ...) -> A ...))
   with-transaction
   ;;   Mode = (U 'deferred 'immediate 'exclusive)
   ;; sqlite-transaction-ended? : Any -> Boolean
   sqlite-transaction-ended?

   ;; --- statements (chez-sqlite3 private statement) ---
   ;; prepare-statement : Database String -> Statement
   prepare-statement
   ;; finalize-statement! : Statement -> Void
   finalize-statement!
   ;; call-with-statement : Database String (Statement -> A ...) -> A ...
   call-with-statement
   ;; statement? : Any -> Boolean
   statement?
   ;; statement-sql : Statement -> String
   statement-sql
   ;; parameter-count : Statement -> Natural
   parameter-count
   ;; step! : Statement -> Boolean
   step!
   ;; reset! : Statement -> Void
   reset!
   ;; column-count : Statement -> Natural
   column-count

   ;; --- values (chez-sqlite3 private statement-values, chez-sqlite3 private values) ---
   ;; bind! : Statement (U Positive-Integer String) Value -> Void
   bind!
   ;; bind-all! : Statement Value ... -> Void
   bind-all!
   ;; clear-bindings! : Statement -> Void
   clear-bindings!
   ;; column-value : Statement Natural -> Value
   column-value
   ;; column-bytevector : Statement Natural -> (U Bytevector SqlNull)
   column-bytevector
   ;; column-name : Statement Natural -> String
   column-name
   ;; sql-null : SqlNull
   sql-null
   ;; sql-null? : Any -> Boolean
   sql-null?

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
   sqlite-closed?
   ;; sqlite-busy? : Any -> Boolean
   sqlite-busy?
   ;; sqlite-constraint? : Any -> Boolean
   sqlite-constraint?
   ;; sqlite-read-only? : Any -> Boolean
   sqlite-read-only?
   ;; sqlite-interrupt? : Any -> Boolean
   sqlite-interrupt?
   ;; sqlite-invalid-text? : Any -> Boolean
   sqlite-invalid-text?
   ;; sqlite-invalid-text-column : SqliteInvalidText -> Natural
   sqlite-invalid-text-column
   ;; sqlite-invalid-text-offset : SqliteInvalidText -> Natural
   sqlite-invalid-text-offset
   ;; sqlite-setting-mismatch? : Any -> Boolean
   sqlite-setting-mismatch?
   ;; sqlite-setting-mismatch-setting : SqliteSettingMismatch -> Symbol
   sqlite-setting-mismatch-setting
   ;; sqlite-setting-mismatch-expected : SqliteSettingMismatch -> Any
   sqlite-setting-mismatch-expected
   ;; sqlite-setting-mismatch-actual : SqliteSettingMismatch -> Any
   sqlite-setting-mismatch-actual
   ;; sqlite-extensions-unavailable? : Any -> Boolean
   sqlite-extensions-unavailable?)
  (import (chez-sqlite3 private require-threaded)
          (only (chez-sqlite3 private open) open-database call-with-database)
          (only (chez-sqlite3 private connection)
                close-database! database? interrupt-database!
                changes total-changes last-insert-rowid in-transaction?)
          (only (chez-sqlite3 private conveniences)
                execute! execute-script! query query-row query-fold)
          (only (chez-sqlite3 private transaction) with-transaction)
          (only (chez-sqlite3 private conditions) sqlite-transaction-ended?)
          (only (chez-sqlite3 private statement)
                prepare-statement finalize-statement! call-with-statement statement?
                statement-sql parameter-count step! reset! column-count)
          (only (chez-sqlite3 private statement-values)
                bind! bind-all! clear-bindings! column-value column-bytevector column-name)
          (only (chez-sqlite3 private values) sql-null sql-null?)
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
                sqlite-closed? sqlite-busy? sqlite-constraint? sqlite-read-only?
                sqlite-interrupt? sqlite-invalid-text? sqlite-invalid-text-column sqlite-invalid-text-offset
                sqlite-setting-mismatch? sqlite-setting-mismatch-setting
                sqlite-setting-mismatch-expected sqlite-setting-mismatch-actual
                sqlite-extensions-unavailable?)))
