#!r6rs
;;; (chez-sqlite3 private open-options): open-database's options as the flags
;;; sqlite3_open_v2 gets, and which filenames are URIs (ADR-0012, decision
;;; 3). Pure: data in, data out. (chez-sqlite3 private connection) turns a
;;; refusal into an assertion violation; nothing here raises on a list.
;;;
;;; The options are symbols, each given once, in any order:
;;;
;;;   mode options given          flags
;;;   none                        READWRITE | CREATE
;;;   create                      READWRITE | CREATE
;;;   read-write                  READWRITE
;;;   read-write create           READWRITE | CREATE
;;;   read-only                   READONLY
;;;   read-only, with read-write
;;;   or create, or both          refused: a contradiction
;;;
;;;   uri        adds URI            memory     adds MEMORY
;;;   no-follow  adds NOFOLLOW       no-mutex   NOMUTEX in place of FULLMUTEX
;;;
;;; and EXRESCODE always (ADR-0010, decision 3). So the flags SQLite gets
;;; hold exactly one of its three legal modes, and v1 never passes a
;;; shared-cache flag.
;;;
;;; It never loads libsqlite3.
(library (chez-sqlite3 private open-options)
  (export open-option-names parse-open-options uri-filename?)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private constants)
          (only (chez-sqlite3 private conditions) shown-value))

  ;; open-option-names : (Listof Symbol)
  ;; Every option open-database takes, in ADR-0012's order.
  (define open-option-names '(read-only read-write create uri memory no-follow no-mutex))

  ;; mode-rows : (Listof (Pairof (Listof Symbol) Natural))
  ;; ADR-0012's mode table: each set of mode options given, in
  ;; open-option-names' order, with its flags. A set no row holds is a
  ;; contradiction.
  (define mode-rows
    (list (cons '() (bitwise-ior sqlite-open-readwrite sqlite-open-create))
          (cons '(create) (bitwise-ior sqlite-open-readwrite sqlite-open-create))
          (cons '(read-write) sqlite-open-readwrite)
          (cons '(read-write create) (bitwise-ior sqlite-open-readwrite sqlite-open-create))
          (cons '(read-only) sqlite-open-readonly)))

  ;; extra-rows : (Listof (Pairof Symbol Natural))
  ;; The options that each add one flag.
  (define extra-rows
    (list (cons 'uri sqlite-open-uri)
          (cons 'memory sqlite-open-memory)
          (cons 'no-follow sqlite-open-nofollow)))

  ;; parse-open-options : (Listof Any) -> (U (Pairof 'flags Natural)
  ;;                                         (List 'unknown Any) (List 'twice Symbol)
  ;;                                         (Pairof 'contradiction (Listof Symbol)))
  ;; GIVEN's flags, or why they are refused. One pass, left to right, reads
  ;; each element once: the first that is not an option is (unknown X), X by
  ;; shown-value, and the first given again is (twice X). Only a list of
  ;; options each given once reaches the mode table, where a set with no row
  ;; is (contradiction M ...), its mode options in open-option-names' order.
  ;; GIVEN is never changed.
  (define (parse-open-options given)
    (let loop ((rest given) (seen '()))
      (if (null? rest)
          (flags-of seen)
          (let ((option (car rest)))
            (cond ((not (and (symbol? option) (memq option open-option-names)))
                   (list 'unknown (shown-value option)))
                  ((memq option seen) (list 'twice option))
                  (else (loop (cdr rest) (cons option seen))))))))

  ;; flags-of : (Listof Symbol) -> (U (Pairof 'flags Natural) (Pairof 'contradiction (Listof Symbol)))
  ;; The flags of OPTIONS, each an option given once.
  (define (flags-of options)
    (let* ((modes (filter (lambda (o) (memq o options)) '(read-only read-write create)))
           (row (assoc modes mode-rows)))
      (if (not row)
          (cons 'contradiction modes)
          (cons 'flags
                (fold-left bitwise-ior
                           (bitwise-ior (cdr row)
                                        (if (memq 'no-mutex options)
                                            sqlite-open-nomutex
                                            sqlite-open-fullmutex)
                                        sqlite-open-exrescode)
                           (map (lambda (extra) (if (memq (car extra) options) (cdr extra) 0))
                                extra-rows))))))

  ;; uri-filename? : String -> Boolean
  ;; Whether S starts with the five characters file:, as SQLite tests a
  ;; filename for a URI: byte for byte, so FILE: is no URI (measured on
  ;; 3.53.1).
  (define (uri-filename? s)
    (and (>= (string-length s) 5)
         (string=? (substring s 0 5) "file:"))))
