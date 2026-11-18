# ADR-0001: Bind libsqlite3 directly, with no C shim; the Chez floor is 10.4.0

- **Status:** Accepted (the maintainer, 2026-11-13). Proposed in the brief, §3a. Amended
  2026-11-13: a threaded Chez is required ([amendment](#amendment-2026-11-13-a-threaded-chez-is-required)).
  Amended 2026-11-17 in M4's plan, and accepted by the maintainer that day: the variadic binding, measured, and its check
  ([amendment](#amendment-2026-11-17-the-variadic-binding-measured-and-its-check-m4s-plan)).
  Amended 2026-11-17 in M4 slice 2, and accepted by the maintainer that day ("Accept all"): `check-variadic` as built
  ([amendment](#amendment-2026-11-17-check-variadic-as-built-m4-slice-2)).
  Amended 2026-11-18 in M4 slice 4, proposed: the extension's build where loading is unavailable
  ([amendment](#amendment-2026-11-18-the-extensions-build-where-loading-is-unavailable-m4-slice-4)).
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
  memory. It would cost a second design, and a CI lane running every suite on a `--nothreads`
  Chez rather than one checking a refusal. The common Chez builds, Guix's and Homebrew's among
  them, are threaded.
- **Consequence:** CI gains a lane on a `--nothreads` Chez in M0 slice 4, which runs a
  `check-nothreads` target, as chez-curl's does.
- **Built in M0 slice 4:** `make check-nothreads` imports every library under `src/` and
  requires each import to be refused by name. That is every library, private ones too, where
  chez-curl's checks only public ones and fails when it finds none: M0 has no public library, and
  every library under `src/` imports `require-threaded` first, so every one must be refused. CI's
  `nothreads` job runs it on Chez built `--nothreads` from the release tarball. On a threaded Chez
  it fails, naming each library: that is its red run, and why `make test` doesn't run it.
  `tests/test-check-nothreads.sps` holds each rule on fixture trees.

## Amendment, 2026-11-17: the variadic binding, measured, and its check (M4's plan)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 0 ([the M4 plan](../2026-11-17-m4-plan.md), §4.2;
[ADR-0021](0021-db-config-options-and-extension-loading.md), decision 4).

- **The consequence is measured** (M4's pre-work,
  [research/m4-prework/](../research/m4-prework/README.md)):
  - bound with `(__varargs_after 2)` in the shape `(db op int int*)`, `sqlite3_db_config`
    round-tripped five ops on five x86_64 libraries, and on Apple arm64 with Apple's 3.51.0 and
    Homebrew's 3.54.1, every line identical to a C oracle's;
  - bound plain, it round-tripped every op on x86_64 too, so no Linux behaviour row can tell the
    two apart. On Apple arm64 it crashed, "invalid memory reference", with both libraries;
  - Linux arm64 wasn't measured: the consequence's "works on x86_64 and Linux arm64" stays
    chez-curl's measurement.
- **Decision 2's "once per argument shape it is called with" is one shape in v1,**
  `(uptr int int uptr) int`. `LOOKASIDE`'s, `(db op void* int int)`, delivered its arguments
  too, and isn't bound (brief §2.8).
- **On Linux only a check of the form can hold it** (the maintainer's Q9, "Check plus
  check-variadic"):
  - the convention table gains a convention, `variadic`, for exactly `(__varargs_after 2)`, and
    `test-conventions` holds the binding's form to its row;
  - `test-constants` holds the row's prototype, `int (*)(sqlite3*, int, ...)`, to the header,
    and the count of its named parameters to the convention's 2;
  - `make check-variadic` removes the convention in a copy of the tree and watches
    `test-conventions` fail, naming that binding alone. On Apple arm64 it runs `test-native` on
    the copy too, which must fail; elsewhere it reports that run, never fails it. CI's `main` job
    runs it as a step of its own, and `make test` doesn't, as chez-curl's ci.yml runs its own; the
    Mac's hand run runs it by hand. chez-curl's `check-variadic` is the design; none of its code
    is copied.
- **The consequence's Mac run** is M4 slice 2's, and each later change's.

## Amendment, 2026-11-17: `check-variadic` as built (M4 slice 2)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 2 ([its mutation log](../m4-slice-2-mutation-log.md)), from the slice and its review (Opus).

- **Written fresh.** The review found 82 of the first script's 150 distinct code lines verbatim in
  chez-curl's `tests/check-variadic.sh`, against this record's "None of its code is copied". The
  script was rewritten from the M4 plan's four steps without reopening chez-curl's: six lines are
  shared now, `}`, `done`, `else`, `esac`, `exit 1` and `fi`.
- **Its list of expected failures is held to the tree.** On the mutant, `test-conventions`' row
  "src: no violation" and its nine sweeps of the real `src/` fail, ten tests, and the script names
  them. `test-check-variadic`, in
  `make test`, holds that list to `test-conventions.sps`' own tests, in order, and holds
  `native.sls` to exactly one line carrying `(__varargs_after 2)`, comments included: a renamed
  sweep, or the form written in a comment, fails `make test`, not CI's step alone.
- **The arm64 step needs the binding's own failure:** on `arm64osx` or `tarm64osx`, by Chez's
  `(machine-type)`, `test-native` on the mutant must fail a test whose name holds
  `sqlite3_db_config`, or die. A failure of another test alone fails the step.
- **Its cost:** 10 to 11 s in the container, and about 11 s in CI's `main` job, from its copy to
  "all 7 steps ok" (run 44189788123).
- **One line matches chez-curl's word for word:** the Makefile's recipe,
  `@TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' TEST_TIMEOUT='$(TEST_TIMEOUT)' sh tests/check-variadic.sh`.
  It is this repository's own pattern for a script target, as `check-test-fails`' is, and is kept.

## Amendment, 2026-11-18: the extension's build where loading is unavailable (M4 slice 4)

Proposed in M4 slice 4 ([its mutation log](../m4-slice-4-mutation-log.md)). The rule is the
maintainer's, "Build named unavailable there" (2026-11-18).

- **Decision 3's "a missing header or compiler fails the suite" is narrowed for one case.** Where
  native records no `sqlite3_load_extension`, as on Apple's library, the suites' extension,
  `tests/extension.c`, is not built:
  - the build rows print UNAVAILABLE;
  - the suites assert the opt-in's refusal in their place.

  The SDK's `sqlite3.h` declares no `sqlite3_load_extension` (M4 slice 2's Mac step), and its
  `sqlite3ext.h` has never been compiled against.
- **Everywhere else, a missing compiler or header still fails the suite.** A row holds both
  branches:
  - a plant that skips the build everywhere fails on Linux's lanes;
  - one that builds everywhere fails the row too.
- **This mirrors [ADR-0002](0002-runtime-libsqlite3-discovery.md)'s amendment** for the optional
  prototype. The Mac run with Apple's library is the first to take the branch.
