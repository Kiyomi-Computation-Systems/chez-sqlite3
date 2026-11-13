# ADR-0001: Bind libsqlite3 directly, with no C shim; the Chez floor is 10.4.0

- **Status:** Accepted (the maintainer, 2026-11-13). Proposed in the brief, §3a. Amended
  2026-11-13: a threaded Chez is required ([amendment](#amendment-2026-11-13-a-threaded-chez-is-required)).
- **Date:** 2026-11-13
- **Scope:** chez-sqlite3 v1: every binding to libsqlite3
- **Settles:** brief §3a
- **Related:** chez-curl ADR-0001, which this follows · chez-libuv ADR-0002 and chez-libuv ADR-0005, its
  constants-only shim · [ADR-0002](0002-runtime-libsqlite3-discovery.md) (loading) ·
  [ADR-0003](0003-sqlite-floor-3-45-1.md) (the SQLite floor) ·
  [ADR-0008](0008-floors-have-one-source.md) (where floors live)

## Context

- **SQLite's C API is plain functions** over ints, 64-bit ints, doubles, pointers, and byte
  strings with lengths. Of the calls v1 needs, only `sqlite3_db_config` is variadic. v1 reads no
  C struct from Scheme.
- **The siblings chose three ways.** chez-cmark-gfm wraps every call in a C shim. chez-libuv
  keeps a shim for constants alone, because libuv's constants and struct layouts vary by
  platform (chez-libuv ADR-0005). chez-curl compiles nothing: Chez 10's `(__varargs_after n)` binds
  variadic calls, and constants are Scheme definitions that a C program checks at test time.
- **SQLite's constants don't vary.** Result codes, open flags, type codes and
  `SQLITE_DBCONFIG_*` keep their values across releases and platforms; SQLite keeps its C
  interface backwards compatible.
- **`SQLITE_TRANSIENT` is not a function.** It is `((sqlite3_destructor_type)-1)`, a
  pointer-width −1. `SQLITE_STATIC` is 0.
- **Thunderchez transcribed constants and signatures by hand,** and three of its signatures were
  wrong: it declared `sqlite3_last_insert_rowid`, `sqlite3_memory_used` and
  `sqlite3_memory_highwater` as returning `int` (the assessment).
- **The development host's Guix Chez is 10.4.0** (measured 2026-11-13). chez-curl's floor is the
  same.

## Decision

1. **No C shim.** Nothing is compiled at install. Every binding is a `foreign-procedure` in a
   `(chez-sqlite3 private …)` library, evaluated after libsqlite3 loads (ADR-0002).
2. **`sqlite3_db_config` is bound with `(__varargs_after 2)`,** once per argument shape it is
   called with. `sqlite3_config` is not bound (brief §2.8).
3. **Constants are Scheme definitions, checked against `sqlite3.h`.** A C program, compiled at
   test time, checks each constant's value. The same program checks each binding's declared
   signature: it assigns the function to a pointer of the C type the binding declares, under
   `-Werror`. So a wrong return type like Thunderchez's fails to compile. A missing header or
   compiler fails the suite, never skips it. The compiler is a test oracle, never an install
   dependency. The container and CI provide one (ADR-0006).
4. **`SQLITE_TRANSIENT` and `SQLITE_STATIC` are passed as pointer-width integers,** −1 and 0,
   never as Scheme procedures.
5. **Chez ≥ 10.4.0, threaded** ([amendment](#amendment-2026-11-13-a-threaded-chez-is-required)).

### Rejected

- **A constants-only shim, as chez-libuv has.** libuv needed one because its values vary by
  platform. SQLite's don't, and a checked transcription catches a wrong one.
- **Transcribing constants and signatures unchecked,** as Thunderchez did. Its wrong `int`
  declarations show the cost.
- **Linking a vendored amalgamation** (chez-libuv ADR-0001's hybrid acquisition). That needs a
  compiler at install time. The system's SQLite and ADR-0002's override cover an
  application-bundled build. CI compiles the amalgamation only as a test subject.

## Consequences

- **The FFI layer is the one place C types are declared,** and the test-time program holds each
  declaration to the header.
- **Apple arm64 passes variadic arguments on the stack.** A `db_config` binding written without
  `__varargs_after` works on x86_64 and Linux arm64, and fails only on Apple arm64; chez-curl
  measured this for `curl_easy_setopt`. There is no macOS CI (AGENTS.md), so the binding is run
  on the maintainer's Mac whenever it changes (M4).
- **Changing the Chez floor** follows ADR-0008.

## Amendment, 2026-11-13: a threaded Chez is required

- **Settles:** brief D1. The maintainer chose on 2026-11-13, when M0 slice 2 needed the answer.
- **Why then:** the counters (ADR-0005) guard their counts with a mutex. chez-libuv measured that
  on a `--nothreads` Chez, a library importing `make-mutex` dies at import with a bare "missing
  import". Each connection's owning thread (brief §3c) needs `get-thread-id` too.
- **Decision:** `(chez-sqlite3 private require-threaded)`, copied from chez-curl, refuses a
  non-threaded Chez, and one older than 10.4.0, by name, while it is being expanded. Every
  library under `src/` imports it first. `tests/test-require-threaded.sps` expands copies in which
  `(threaded?)` and the version answer otherwise, with rows built from `packaging/floors.sexp`
  (ADR-0008), and holds the import order.
- **Rejected:** supporting both builds, with counters built on `ftype-locked-incr!` over foreign
  memory. It would cost a second design and a second CI lane, and the common Chez builds,
  Guix's and Homebrew's among them, are threaded.
- **Consequence:** CI gains a lane on a `--nothreads` Chez in M0 slice 4, which runs a
  `check-nothreads` target, as chez-curl's does.
