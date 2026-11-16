#!r6rs
;;; (chez-sqlite3 private script): where execute-script!'s error points
;;; (ADR-0016, decision 7; ADR-0013, amended for M3). The script runs as a
;;; loop of prepares over one block holding the whole script's UTF-8, each
;;; prepare passed the address of its statement's start; so SQLite counts a
;;; prepare's error offset from where that prepare started, never from the
;;; script's start (M3's research, single script X5). The error carries the
;;; whole script as its sql, and its offset counts characters of it, as
;;; every &sqlite-error's offset does (ADR-0013, amended for M2):
;;;
;;;   script-prepare-offset  a prepare's error: the character SQLite points
;;;                          at, START + OFFSET as bytes; SQLite's -1 points
;;;                          at none, so it answers the failing statement's
;;;                          first token, as script-step-offset does from
;;;                          START (ADR-0016, decision 7, amended)
;;;   script-step-offset     a step's error, which SQLite gives no offset:
;;;                          the failing statement's first token, past the
;;;                          whitespace, U+FEFF, comments and semicolons
;;;                          before it, by ADR-0014's scan. A statement's
;;;                          text begins at the tail of the one before it, and
;;;                          leading semicolons and comments belong to it
;;;                          (M3 slice 0's research, P11)
;;;
;;; Both are total and raise nothing, for any arguments: slice 3 calls them
;;; inside the section that answers a prepare's or a step's outcome, where
;;; nothing may raise. Each byte offset is read as a character by
;;; utf8-offset->index, and each first token found by sql-tail-statement,
;;; the scan that agrees with SQLite's tokenizer on every short input.
(library (chez-sqlite3 private script)
  (export script-prepare-offset script-step-offset)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private utf8) utf8-offset->index)
          (only (chez-sqlite3 private sql-tail) sql-tail-statement))

  ;; exact-integer? : Any -> Boolean
  (define (exact-integer? x) (and (integer? x) (exact? x)))

  ;; start-within? : Any Any -> Boolean
  ;; Whether BYTES is a bytevector and START an exact integer from 0 to its
  ;; length.
  (define (start-within? bytes start)
    (and (bytevector? bytes) (exact-integer? start) (<= 0 start (bytevector-length bytes))))

  ;; script-prepare-offset : Bytevector Natural Integer -> (U Natural #f)
  ;; A failed prepare's offset into the script whose UTF-8 is BYTES, as a
  ;; character index into the script's string: the prepare started at byte
  ;; START, and SQLite answered OFFSET, a byte offset from START, or -1. A
  ;; byte at a character's start, or the end, is that character's index, and
  ;; a continuation byte the index of the character it continues
  ;; (utf8-offset->index). For -1, which points at no token, SQLite answers
  ;; it for an error at the end of the SQL, and for a missing table, a
  ;; missing collation and a busy prepare (ADR-0013, amended for M2; single
  ;; script X6, X8): the failing statement's first token, exactly what
  ;; (script-step-offset BYTES START) answers (ADR-0016, decision 7,
  ;; amended: the maintainer, 2026-11-15, "Point at the statement"), #f when
  ;; the statement has none. #f for anything else outside the script: a START
  ;; below 0 or past the end, an OFFSET below -1 or past the end, or an
  ;; argument of another type.
  (define (script-prepare-offset bytes start offset)
    (and (start-within? bytes start)
         (exact-integer? offset)
         (cond ((= offset -1) (script-step-offset bytes start))
               ((and (>= offset 0) (<= (+ start offset) (bytevector-length bytes)))
                (utf8-offset->index bytes (+ start offset)))
               (else #f))))

  ;; script-step-offset : Bytevector Natural -> (U Natural #f)
  ;; A failed step's offset into the script whose UTF-8 is BYTES, as a
  ;; character index: the first byte, scanned from START as a fresh token,
  ;; that is no whitespace, U+FEFF, comment or semicolon, which is the
  ;; failing statement's first token when START is where its prepare
  ;; started. #f when there is none, and for a START below 0 or past the
  ;; end, or an argument of another type.
  (define (script-step-offset bytes start)
    (let ((token (and (start-within? bytes start) (sql-tail-statement bytes start))))
      (and token (utf8-offset->index bytes token)))))
