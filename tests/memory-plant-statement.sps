#!r6rs
;;; tests/memory-plant-statement.sps: a PLANTED statement leak, through the
;;; real constructor. Not a suite.
;;;
;;; `make check-memory-gate` runs it through `make test-memory` and requires
;;; the gate to FAIL on it, with Valgrind's own loss record in the log
;;; (ADR-0005, amended for M2; ADR-0014, consequences).
;;;
;;; It opens :memory: through open-database, prepares select 1 through
;;; prepare-statement, and drops both records, the statement never finalized
;;; and the connection never closed. SQLite links every statement from its
;;; connection, so the statement is reachable through the connection, and
;;; Valgrind sees it only through the connection's loss: one block definitely
;;; lost, holding the statement among the blocks it points to. The counters
;;; see the statement alone, and the plant prints them, read before it exits,
;;; so check-memory-gate's case a holds that they count it. A plain run exits
;;; 0: check-memory-gate requires that first, so a red gate can only mean
;;; Valgrind saw the leak. It never reaches suite-exit-status, which would
;;; name both.
;;;
;;; It is not named tests/test-*.sps, so neither make test nor make
;;; test-memory runs it unasked.
(import (rnrs)
        (chez-sqlite3)
        (only (chez-sqlite3 private statement) prepare-statement)
        (only (chez-sqlite3 private counters) native-counts))

(prepare-statement (open-database ":memory:") "select 1")

(display "memory-plant-statement: prepared select 1 on :memory: through prepare-statement and dropped both, never finalized or closed; counts ")
(write (native-counts))
(newline)
(exit 0)
