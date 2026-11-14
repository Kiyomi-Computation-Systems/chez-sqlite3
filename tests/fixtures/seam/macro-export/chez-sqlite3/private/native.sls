#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library that imports library-only names exports macros it binds with define-syntax: plain, renamed, and inside begin; plain is no macro and is not named.
(library (chez-sqlite3 private native)
  (export call (rename (call2 call-two)) call3 plain)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-ref))
  (define-syntax call (syntax-rules () ((_ x) (foreign-procedure x))))
  (define-syntax call2 (syntax-rules () ((_ x) (foreign-ref x))))
  (begin (define-syntax call3 (syntax-rules () ((_ x) (foreign-ref x)))))
  (define plain 1))
