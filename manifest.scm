;;; Development toolchain for chez-sqlite3 (ADR-0006).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and runs
;;; this manifest in a container with no network. Plain
;;; `guix shell -m manifest.scm` also loads this file, but against whatever
;;; Guix you have pulled.

(specifications->manifest
 '(;; Chez, and libsqlite3 bound with no C shim (ADR-0001). "sqlite" brings
   ;; libsqlite3.so.0 and sqlite3.h (ADR-0003); gcc-toolchain compiles the
   ;; test-time program that checks constants and signatures against that
   ;; header.
   "chez-scheme" "sqlite" "gcc-toolchain"
   ;; The memory gate (ADR-0005).
   "valgrind"
   ;; What the Makefile and scripts shell out to. bash also gives the
   ;; self-test its network probe, /dev/tcp. The container has nothing else.
   "bash" "coreutils" "make" "grep" "sed" "gawk" "findutils" "diffutils"))
