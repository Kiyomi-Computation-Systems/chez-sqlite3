;;; (chez-sqlite3 private constants): the SQLite constants chez-sqlite3 needs,
;;; each copied from sqlite3.h as of SQLite 3.45.1, the floor (ADR-0001,
;;; ADR-0003). SQLite never renumbers a result code or a flag. A later
;;; release may add some: a code this table lacks stays an integer
;;; (ADR-0013, decision 3).
;;;
;;; tests/test-constants.sps holds every value here to the sqlite3.h the
;;; compiler finds, with a C program compiled at test time (ADR-0001).
;;;
;;;   sqlite-open-*             the open flags v1 uses (ADR-0012, decision 3)
;;;   sqlite-result-codes       every primary and extended result code in
;;;                             3.45.1's sqlite3.h, in the header's order
;;;   sqlite-result-code-name   a code's name, or the integer
;;;   sqlite-primary-code-name  the name of a code's primary code
;;;
;;; A code's name is its C name with SQLITE_ dropped, lower-cased, _ turned
;;; to -: SQLITE_IOERR_SHORT_READ is ioerr-short-read.
(library (chez-sqlite3 private constants)
  (export sqlite-open-readonly sqlite-open-readwrite sqlite-open-create
          sqlite-open-uri sqlite-open-memory sqlite-open-nomutex
          sqlite-open-fullmutex sqlite-open-nofollow sqlite-open-exrescode
          sqlite-result-codes sqlite-result-code-name sqlite-primary-code-name)
  (import (chez-sqlite3 private require-threaded)
          (rnrs))

  ;; sqlite-open-readonly : Natural     SQLITE_OPEN_READONLY
  (define sqlite-open-readonly #x00000001)
  ;; sqlite-open-readwrite : Natural    SQLITE_OPEN_READWRITE
  (define sqlite-open-readwrite #x00000002)
  ;; sqlite-open-create : Natural       SQLITE_OPEN_CREATE
  (define sqlite-open-create #x00000004)
  ;; sqlite-open-uri : Natural          SQLITE_OPEN_URI
  (define sqlite-open-uri #x00000040)
  ;; sqlite-open-memory : Natural       SQLITE_OPEN_MEMORY
  (define sqlite-open-memory #x00000080)
  ;; sqlite-open-nomutex : Natural      SQLITE_OPEN_NOMUTEX
  (define sqlite-open-nomutex #x00008000)
  ;; sqlite-open-fullmutex : Natural    SQLITE_OPEN_FULLMUTEX
  (define sqlite-open-fullmutex #x00010000)
  ;; sqlite-open-nofollow : Natural     SQLITE_OPEN_NOFOLLOW
  (define sqlite-open-nofollow #x01000000)
  ;; sqlite-open-exrescode : Natural    SQLITE_OPEN_EXRESCODE
  (define sqlite-open-exrescode #x02000000)

  ;; sqlite-result-codes : (Listof (Pairof Symbol Natural))
  ;; Every primary and extended result code of 3.45.1's sqlite3.h (108), in
  ;; the header's order. A primary code is below 256. An extended code's low
  ;; byte is its primary code.
  (define sqlite-result-codes
    '(
     (ok . 0) (error . 1) (internal . 2) (perm . 3) (abort . 4) (busy . 5) (locked . 6)
       (nomem . 7) (readonly . 8) (interrupt . 9) (ioerr . 10) (corrupt . 11) (notfound . 12)
       (full . 13) (cantopen . 14) (protocol . 15) (empty . 16) (schema . 17) (toobig . 18)
       (constraint . 19) (mismatch . 20) (misuse . 21) (nolfs . 22) (auth . 23) (format . 24)
       (range . 25) (notadb . 26) (notice . 27) (warning . 28) (row . 100) (done . 101)
       (error-missing-collseq . 257) (error-retry . 513) (error-snapshot . 769)
       (ioerr-read . 266) (ioerr-short-read . 522) (ioerr-write . 778) (ioerr-fsync . 1034)
       (ioerr-dir-fsync . 1290) (ioerr-truncate . 1546) (ioerr-fstat . 1802)
       (ioerr-unlock . 2058) (ioerr-rdlock . 2314) (ioerr-delete . 2570) (ioerr-blocked . 2826)
       (ioerr-nomem . 3082) (ioerr-access . 3338) (ioerr-checkreservedlock . 3594)
       (ioerr-lock . 3850) (ioerr-close . 4106) (ioerr-dir-close . 4362) (ioerr-shmopen . 4618)
       (ioerr-shmsize . 4874) (ioerr-shmlock . 5130) (ioerr-shmmap . 5386) (ioerr-seek . 5642)
       (ioerr-delete-noent . 5898) (ioerr-mmap . 6154) (ioerr-gettemppath . 6410)
       (ioerr-convpath . 6666) (ioerr-vnode . 6922) (ioerr-auth . 7178)
       (ioerr-begin-atomic . 7434) (ioerr-commit-atomic . 7690) (ioerr-rollback-atomic . 7946)
       (ioerr-data . 8202) (ioerr-corruptfs . 8458) (ioerr-in-page . 8714)
       (locked-sharedcache . 262) (locked-vtab . 518) (busy-recovery . 261) (busy-snapshot . 517)
       (busy-timeout . 773) (cantopen-notempdir . 270) (cantopen-isdir . 526)
       (cantopen-fullpath . 782) (cantopen-convpath . 1038) (cantopen-dirtywal . 1294)
       (cantopen-symlink . 1550) (corrupt-vtab . 267) (corrupt-sequence . 523)
       (corrupt-index . 779) (readonly-recovery . 264) (readonly-cantlock . 520)
       (readonly-rollback . 776) (readonly-dbmoved . 1032) (readonly-cantinit . 1288)
       (readonly-directory . 1544) (abort-rollback . 516) (constraint-check . 275)
       (constraint-commithook . 531) (constraint-foreignkey . 787) (constraint-function . 1043)
       (constraint-notnull . 1299) (constraint-primarykey . 1555) (constraint-trigger . 1811)
       (constraint-unique . 2067) (constraint-vtab . 2323) (constraint-rowid . 2579)
       (constraint-pinned . 2835) (constraint-datatype . 3091) (notice-recover-wal . 283)
       (notice-recover-rollback . 539) (notice-rbu . 795) (warning-autoindex . 284)
       (auth-user . 279) (ok-load-permanently . 256) (ok-symlink . 512)))

  ;; sqlite-result-code-name : Integer -> (U Symbol Integer)
  ;; CODE's name in the table, or CODE itself when the table has no row.
  (define (sqlite-result-code-name code)
    (let ((row (find-code code)))
      (if row (car row) code)))

  ;; sqlite-primary-code-name : Integer -> (U Symbol Integer)
  ;; (a Symbol for every low byte the header names)
  ;; The name of CODE's primary code, its low byte. Every primary code is in
  ;; the table, so a code the header names has a name here.
  (define (sqlite-primary-code-name code)
    (sqlite-result-code-name (bitwise-and code 255)))

  ;; find-code : Integer -> (U (Pairof Symbol Natural) #f)
  (define (find-code code)
    (let loop ((rows sqlite-result-codes))
      (cond ((null? rows) #f)
            ((eqv? (cdar rows) code) (car rows))
            (else (loop (cdr rows))))))
)
