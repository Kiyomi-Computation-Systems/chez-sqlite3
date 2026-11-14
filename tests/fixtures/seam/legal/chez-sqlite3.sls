#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal tree. Every import is on a list.
(library (chez-sqlite3)
  (export lib-version)
  (import (chez-sqlite3 private require-threaded) (rnrs) (rnrs io ports) (only (chezscheme) threaded? with-mutex) (chez-sqlite3 private thing))
  (define lib-version thing))
