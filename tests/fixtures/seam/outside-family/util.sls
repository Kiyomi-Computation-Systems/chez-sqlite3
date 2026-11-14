#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (util)
  (export u)
  (import (rnrs))
  (define u 1))
