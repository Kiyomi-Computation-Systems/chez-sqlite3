#!r6rs
;;; Fixture for tests/test-check-seam.sps: an except over an only over (chezscheme), exporting the name it leaves.
(library (chez-sqlite3 private e)
  (export threaded?)
  (import (rnrs) (except (only (chezscheme) threaded? with-mutex) with-mutex)))
