#!r6rs
;;; tests/fixtures/raising/chez-sqlite3/private/native.sls: a stand-in
;;; (chez-sqlite3 private native) whose loaded-libsqlite3 raises a plain
;;; error, not a refusal, for tests/test-library-loading.sps only. Run with
;;; --libdirs tests/fixtures/raising:src, it shadows src/'s native, so the
;;; refusal probe and the preflight meet a raise that is a bug, and must
;;; report it as one: never as a refusal.
;;;
;;; It loads nothing and binds no foreign procedure. Its exports are the
;;; two the probe and the preflight reference.
(library (chez-sqlite3 private native)
  (export loaded-libsqlite3 loaded-threadsafe)
  (import (rnrs))

  ;; loaded-libsqlite3 : -> Nothing
  (define (loaded-libsqlite3)
    (error 'loaded-libsqlite3 "the raising fixture raises a plain error, not a refusal"))

  ;; loaded-threadsafe : -> Nothing
  (define (loaded-threadsafe)
    (error 'loaded-threadsafe "the raising fixture never loads a libsqlite3")))
