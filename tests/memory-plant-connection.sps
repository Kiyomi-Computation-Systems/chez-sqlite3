#!r6rs
;;; tests/memory-plant-connection.sps: a PLANTED connection leak, through the
;;; real constructor. Not a suite.
;;;
;;; `make check-memory-gate` runs it through `make test-memory` and requires
;;; the gate to FAIL on it, with Valgrind's own loss record in the log
;;; (ADR-0005, ADR-0012; the M1 plan, §3.1).
;;;
;;; It opens :memory: through (chez-sqlite3)'s open-database and drops the
;;; record, never closed. The record holds the sqlite3* as an integer, which a
;;; Chez fixnum holds shifted, so Valgrind finds no pointer to the connection:
;;; it is definitely lost, one block, and what it points to indirectly lost.
;;; Measured in M1 slice 4: 840 bytes direct and 61,288 indirect on Guix's
;;; 3.53.1, 792 and 56,640 on 3.45.1, the same with the record dropped, held
;;; by a top-level variable, or collected first. A plain run exits 0:
;;; check-memory-gate requires that first, so a red gate can only mean
;;; Valgrind saw the leak. It never reaches suite-exit-status, which would
;;; name the connection too: check-test-fails' leaks plant holds that.
;;;
;;; It is not named tests/test-*.sps, so neither make test nor make
;;; test-memory runs it unasked.
(import (rnrs)
        (chez-sqlite3))

(open-database ":memory:")

(display "memory-plant-connection: opened :memory: through open-database and dropped the record, never closed")
(newline)
(exit 0)
