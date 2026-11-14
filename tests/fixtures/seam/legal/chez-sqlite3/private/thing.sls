#!r6rs
;;; Fixture for tests/test-check-seam.sps: every import-set wrapper over an (rnrs ...) library, a version reference, and the (library ...) form.
(library (chez-sqlite3 private thing)
  (export thing)
  (import (chez-sqlite3 private require-threaded) (only (rnrs) define) (except (rnrs lists) fold-left) (prefix (rnrs sorting) s:) (rename (rnrs control) (when whenever)) (for (rnrs base) expand) (library (rnrs unicode)) (rnrs arithmetic bitwise) (rnrs (6)) (only (chezscheme) critical-section make-mutex scheme-version scheme-version-number))
  (define thing 1))
