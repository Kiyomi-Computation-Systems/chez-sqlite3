#!r6rs
;;; Fixture for tests/test-check-seam.sps: (chez-sqlite3 private extra), a second library in this file. Rule (h) reads it as defined under the directory, but Chez looks for it at chez-sqlite3/private/extra.sls.
(library (chez-sqlite3 private a)
  (export a)
  (import (rnrs))
  (define a 1))
(library (chez-sqlite3 private extra) (export extra) (import (rnrs)) (define extra 1))
