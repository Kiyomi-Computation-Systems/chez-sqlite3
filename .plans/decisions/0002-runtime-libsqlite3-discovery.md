# ADR-0002: Find libsqlite3 at runtime: an override, else one candidate list per world, loaded once by absolute path

- **Status:** Accepted (the maintainer, 2026-11-13). Proposed in the brief, §3b. Amended
  2026-11-14: `not-threadsafe`, and what the Mac showed
  ([amendment](#amendment-2026-11-14-not-threadsafe-and-what-the-mac-showed-m1s-plan)). Amended
  2026-11-14: M2's required entry points
  ([amendment](#amendment-2026-11-14-m2s-required-entry-points-m2s-plan)). Amended 2026-11-15, and
  accepted by the maintainer that day: M3's required entry points (M3's plan,
  [amendment](#amendment-2026-11-15-m3s-required-entry-points-m3s-plan)).
  Amended 2026-11-17 in M4's plan, and accepted by the maintainer that day: M4's entry points, and where extension loading's guarantee lives
  ([amendment](#amendment-2026-11-17-m4s-entry-points-and-where-extension-loadings-guarantee-lives-m4s-plan)).
  Amended 2026-11-17 in M4 slice 2, and accepted by the maintainer that day ("Accept all"): the optional entry point's prototype
  ([amendment](#amendment-2026-11-17-the-optional-entry-points-prototype-m4-slice-2)).
  Amended 2026-11-18 in M4's closing review, proposed: an absolute path and macOS's `DYLD_*`
  ([amendment](#amendment-2026-11-18-an-absolute-path-and-macoss-dyld_-m4s-closing-review)).
- **Date:** 2026-11-13
- **Scope:** chez-sqlite3 v1, on Linux distributions, Guix environments and macOS
- **Settles:** brief §3b
- **Related:** chez-curl ADR-0002, which this follows ·
  [ADR-0001](0001-bind-libsqlite3-directly.md) (no build step) ·
  [ADR-0003](0003-sqlite-floor-3-45-1.md) (the floor) ·
  [ADR-0006](0006-pinned-guix-container.md) (the container's override)

## Context

ADR-0001 compiles nothing, so libsqlite3 must be found when `(chez-sqlite3)` is imported. These
facts were measured on the development host (Pop!_OS 22.04, a Guix home profile, Guix's Chez
10.4.0) on 2026-11-13, unless a line says otherwise.

- **A bare soname finds nothing under Guix's Chez.** `(load-shared-object "libsqlite3.so.0")`
  fails: "cannot open shared object file". The host's own `libsqlite3.so.0`, from the
  `libsqlite3-0` package, is in `/usr/lib/x86_64-linux-gnu`, where Guix's loader doesn't look.
  The assessment's loader names the soname alone, so it would fail here.
- **The host's library loads by absolute path, but it belongs to another world.** It links only
  the host's `libc.so.6` and `libm.so.6`, and it loaded. Guix's Chez has already mapped Guix's
  glibc 2.41, so the library runs against a glibc it wasn't built for. It is also 3.37.2, below
  the floor.
- **Guix's library is one symlink away.** `~/.guix-home/profile/lib/libsqlite3.so.0` resolves into
  `/gnu/store/…-sqlite-3.53.1/lib/`. `GUIX_PROFILE` names that profile. `GUIX_ENVIRONMENT` is set
  only inside `guix shell`.
- **Chez can tell its world in plain Scheme.** Its `/proc/self/maps` lists
  `/gnu/store/…-glibc-2.41/lib/libc.so.6`.
- **Filenames don't reliably carry the version.** The host's 3.37.2 is `libsqlite3.so.0.8.6`;
  Guix's 3.53.1 is `libsqlite3.so.3.53.1`. The version is known only after loading, from
  `sqlite3_libversion_number`.
- **Apple ships `/usr/lib/libsqlite3.dylib`.** Like every system dylib since macOS 11, it lives in
  the dyld shared cache with no file on disk. The assessment loaded it on the maintainer's Mac and
  it reported 3.51.0. Homebrew's `sqlite` is believed to be keg-only, so it is never linked into
  `/opt/homebrew/lib`. Not measured here.
- **Chez binds a name to the most recently loaded object** (measured in chez-curl, recorded in chez-curl ADR-0002).
  So a second load can silently redirect bindings evaluated after it.

## Decision

1. **The override.** If `CHEZ_SQLITE3_LIBRARY` is set, it must be an absolute path, and it is
   loaded as given, with no search and no fallback. A relative path, a bare name or an empty value
   is `invalid-override`. Existence is decided by loading, not by `stat`, so Apple's dyld-cache
   library can be named.
2. **Otherwise, one candidate list, chosen by world.** A pure function computes it. Its inputs are
   the machine type, the environment, the text of `/proc/self/maps` and an existence predicate.
   The first candidate that exists is chosen.
   - **Guix world (Linux).** The world is Guix when `/proc/self/maps` shows libc mapped from under
     `/gnu/store/`. The candidate is `lib/libsqlite3.so.0` under each of these, in order:
     `$GUIX_ENVIRONMENT`, `$GUIX_PROFILE`, `$HOME/.guix-home/profile`, `$HOME/.guix-profile`,
     `/run/current-system/profile`. A variable that is unset or not absolute contributes
     nothing. Standard directories are never candidates here.
   - **FHS Linux,** also used when `/proc` can't be read. The candidates are `libsqlite3.so.0` in
     `/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib64` and `/usr/lib`, in that order. The triple
     comes from the machine type: `ta6le` and `a6le` give `x86_64-linux-gnu`, and `tarm64le` and
     `arm64le` give `aarch64-linux-gnu`. An unknown machine type has no triple directory. Guix
     profiles are never candidates here.
   - **macOS.** The only candidate is `/usr/lib/libsqlite3.dylib`, decided by loading. Any other
     SQLite on a Mac is reached through the override.
   - **Any other platform** has no list, so only the override works.
3. **One load, then verify, never fall through.** The chosen path is loaded once.
   `sqlite3_libversion_number` is bound and checked against the floor (ADR-0003) first. Then every
   required entry point is bound eagerly in the same library body, each checked with
   `foreign-entry?` first. Optional entry points, such as extension loading (brief §2.5), are
   checked the same way. Their absence is reported where they are used, not at load. The first
   load failure is kept for the life of the process, as chez-curl's `load-state` keeps it.
4. **Every outcome names its paths.** A loaded library is reported with its path, its source (the
   override, a Guix location, a system directory), `sqlite3_libversion` and
   `sqlite3_sourceid`. A refusal is a `&sqlite-library-unavailable` carrying a reason symbol:
   `invalid-override`, `not-found`, `load-failed`, `below-floor` or `missing-api`, and
   `not-threadsafe` since the 2026-11-14 amendment. `not-found` lists every candidate it checked.

### Rejected

- **A bare soname through the platform loader.** It finds nothing under Guix (measured), its
  choice can't be unit-tested, it can't say which file loaded, and it lets `LD_LIBRARY_PATH` and
  `DYLD_*` decide silently.
- **One merged list for both Linux worlds.** With standard directories first, this host would load
  a library built for another glibc and below the floor. With Guix first, a Chez built for the
  host would load a library built against a newer glibc. The world is a fact, read rather than
  guessed from order.
- **Homebrew before Apple's.** Which SQLite loads would then depend on what else is installed on
  that Mac. The override reaches Homebrew's.
- **Choosing by version from the filename.** Filenames don't carry it reliably (measured).
- **Trying candidates until one verifies.** A refused library can't be unloaded, and a second load
  redirects later bindings.

### Open

- **Whether a `THREADSAFE=0` build is refused** is decided with the thread records (brief D1, D2),
  as an amendment. Both builds measured here report `THREADSAFE=1`.

  Closed 2026-11-14: it is refused, as `not-threadsafe` (ADR-0010, and the amendment below).

## Consequences

- **Nothing reads `LD_LIBRARY_PATH` or `DYLD_*` on chez-sqlite3's behalf.** A non-standard SQLite,
  whether from Nix, `/opt` or a hand build, is named with `CHEZ_SQLITE3_LIBRARY`.
- **Development never depends on the search.** The container exports the override (ADR-0006).
  Two kinds of test cover the search instead. The pure function's tests use synthetic inputs, one
  for each rule, each failing by name when its rule is relaxed. An install check runs with the
  override unset.
- **CI's `main` job runs in the FHS world** and finds the runner's packaged library. The `floor`
  and `current` lanes use the override.
- **Ubuntu 22.04 and Debian 12 find their library and refuse it** as `below-floor`, naming the
  path, the version and the override.
- **A Mac whose system SQLite is below the floor** gets `below-floor`, and its remedy is the
  override. macOS 14 and 15 may be such Macs (brief D7). If M1 measures that they are, M1 revisits
  whether macOS should get more candidates. M1 measured only macOS 26, which is above the floor
  (the amendment), so for 14 and 15 this stays open.
- **The reason symbols are the contract.** Tests assert the reason, never the remedy text.

## Amendment, 2026-11-14: `not-threadsafe`, and what the Mac showed (M1's plan)

- **A sixth reason, `not-threadsafe`.** A library whose `sqlite3_threadsafe()` answers 0 is
  refused (ADR-0010, decision 4; the maintainer, 2026-11-13). The refusal's detail is the
  answer, 0.
- **What is bound, in order** (proposed in M1 slice 0; accepted by the maintainer, 2026-11-14):
  1. **The report's three:** `sqlite3_libversion_number`, `sqlite3_libversion` and
     `sqlite3_sourceid`, which every SQLite 3 has. The report is built from them, with the path
     and the source: those five fields and no others. So every refusal from here on carries it.
  2. **The floor:** `below-floor`.
  3. **`sqlite3_threadsafe`:** `not-threadsafe`.
  4. **`sqlite3_initialize`,** called once (M1 slice 2). A build compiled with
     `SQLITE_OMIT_AUTOINIT` doesn't initialise itself at its first open, so the load does it. An
     answer other than `SQLITE_OK` is `load-failed`, its detail the code.
  5. **Every other required entry point,** each checked with `foreign-entry?` first, else
     `missing-api` naming it. M1's are `sqlite3_compileoption_used`,
     `sqlite3_compileoption_get`, `sqlite3_open_v2`, `sqlite3_close`, `sqlite3_errmsg`,
     `sqlite3_errstr`, `sqlite3_errcode`, `sqlite3_extended_errcode`, `sqlite3_next_stmt` and
     `sqlite3_memory_used`. Each later milestone adds its own, every one present at the floor.
  - **Optional:** `sqlite3_load_extension` (M4), which a build can omit, as Apple's does. Its
    absence is reported where extension loading is asked for, never at the load.
  - **Never bound:** `sqlite3_enable_load_extension`. SQLite's documentation says it turns on SQL's
    `load_extension()` as well as the C call, which brief §2.5 rules out. M4 turns on the C call
    alone, through `sqlite3_db_config`'s `ENABLE_LOAD_EXTENSION`.
  - **Compile options are read, not reported:** an application asks through the exported
    queries, which call `sqlite3_compileoption_used` (brief §2.6).
- **Apple's SQLite, measured on the maintainer's Mac** (macOS 26.7.1, arm64;
  [research/mac-d7/](../research/mac-d7/)):
  - **It loads by absolute path with no file on disk,** as decision 1 expects: a `stat` would
    have found nothing.
  - **It is 3.51.0, above the floor.** So on current macOS the one candidate is enough, and the
    consequence's "M1 revisits whether macOS should get more candidates" isn't triggered. macOS 14
    and 15 stay unmeasured.
  - **It answers `THREADSAFE=2`,** so `not-threadsafe` doesn't refuse it.
  - **It is built with `OMIT_LOAD_EXTENSION`:** `sqlite3_load_extension` and
    `sqlite3_enable_load_extension` are missing, the only two of the 45 entry points the probe
    checked. The first is optional and the second is never bound (above), so the load accepts
    it.
- **Homebrew's SQLite is at `/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib`,** 3.54.1 on that
  Mac. It loads by absolute path, as the override names it. Whether Homebrew also links it into
  `/opt/homebrew/lib` wasn't checked; nothing here reads that directory.
- **What slice 2 built and measured** (M1 slice 2):
  - **The load is seven steps,** each a definition inside `load-step`: choose, load, the report,
    the floor, threadsafe, `sqlite3_initialize`, the rest. Existence is `(rnrs)`'s `file-exists?`,
    as decision 2 says "exists": a directory there is chosen, and then refused `load-failed`.
  - **`load-failed`'s detail** is one of three: the loader's message; the C name of a report entry
    point that answered NULL, `"sqlite3_libversion"` or `"sqlite3_sourceid"`; or
    `sqlite3_initialize`'s code.
  - **A missing report entry point is `missing-api` with library `#f`,** since the report doesn't
    exist yet. A build with `SQLITE_OMIT_COMPILEOPTION_DIAGS` lacks `sqlite3_compileoption_used`,
    and is refused `missing-api`.
  - **`foreign-entry?` asks the whole process, not the chosen file** (slice 2's review). A probe
    loaded one object exporting `xfoo` and `xbar`, then another exporting `xfoo` alone:
    `(foreign-entry? "xbar")` answered `#t`, and the binding called the first object's. So in a
    process that already holds another SQLite, a `missing-api` check passes on that SQLite's
    entry, and native would bind from two libraries. chez-sqlite3 assumes it is the only SQLite
    a process loads. Slice 3 runs every decoy case in a fresh process.
- **The install check, and the refusals end to end** (M1 slice 3). CI's `main` job runs
  `make build` with `CHEZ_SQLITE3_LIBRARY` unset, its own step, "The install check, by discovery":
  it exits non-zero on any refusal, so the runner's library must be found and accepted. Which file
  it found is read from CI's log, not held. Every refusal reason is driven through the real load
  by a decoy libsqlite3 in a fresh process (`test-library-loading`). `not-found` runs end to end
  in a Guix world; in an FHS world, as on CI, its row asserts discovery's success instead, and its
  name says which world ran.

## Amendment, 2026-11-14: M2's required entry points (M2's plan)

Accepted by the maintainer on 2026-11-14, proposed in M2 slice 0
([the M2 plan](../2026-11-14-m2-plan.md), §4.7).

- **M2 adds 21 required entry points** to item 5 of the M1 amendment's "What is bound, in
  order", after M1's, in the same step, the seventh of native's load. Each is checked with
  `foreign-entry?` before it is bound, else `missing-api` naming it: `sqlite3_prepare_v3`,
  `sqlite3_finalize`, `sqlite3_step`, `sqlite3_reset`, `sqlite3_clear_bindings`,
  `sqlite3_bind_parameter_count`, `sqlite3_bind_parameter_index`, `sqlite3_bind_null`,
  `sqlite3_bind_int64`, `sqlite3_bind_double`, `sqlite3_bind_text64`, `sqlite3_bind_blob64`,
  `sqlite3_column_count`, `sqlite3_column_name`, `sqlite3_column_type`, `sqlite3_column_int64`,
  `sqlite3_column_double`, `sqlite3_column_text`, `sqlite3_column_blob`, `sqlite3_column_bytes`
  and `sqlite3_error_offset`.
- **All 21 are in the floor's build.** `nm -D --defined-only` on a 3.45.1 built from the
  amalgamation found each ([research/m2-plan/](../research/m2-plan/)).
- **None is optional:** each is part of SQLite's statement API, which M2's verbs can't do without.
- **Each gets a decoy switch and a `missing-api` row in `test-library-loading`,** as M1's do (M1
  slice 3). ADR-0005's amendment of the same day gives what that costs the gate.

## Amendment, 2026-11-15: M3's required entry points (M3's plan)

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 0
([the M3 plan](../2026-11-15-m3-plan.md), §4.7).

- **M3 adds five required entry points** to item 5 of the M1 amendment's "What is bound, in
  order", after M2's, in the same step, the seventh of native's load. Each is checked with
  `foreign-entry?` before it is bound, else `missing-api` naming it: `sqlite3_changes64`,
  `sqlite3_total_changes64`, `sqlite3_last_insert_rowid`, `sqlite3_get_autocommit` and
  `sqlite3_interrupt`.
- **All five are in the floor's build** (M3's research, single, `entry-points.sps`).
- **None is optional:** the counters, `with-transaction`'s read of autocommit and the interrupt
  can't do without them.
- **Each gets a decoy switch and a `missing-api` row,** continuing the alternation of entry
  points between `test-library-loading-decoys` and `test-library-loading-real`, the halves M2
  split the suite into in PR #19 (ADR-0005, amended). Since M3 slice 2, a pattern of five deals
  them to three suites instead ([ADR-0005](0005-memory-gate.md), amended 2026-11-16).

## Amendment, 2026-11-17: M4's entry points, and where extension loading's guarantee lives (M4's plan)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 0 ([the M4 plan](../2026-11-17-m4-plan.md), §4.3, §4.4 and §4.6;
[ADR-0021](0021-db-config-options-and-extension-loading.md)).

- **M4 adds two required entry points** to item 5 of the M1 amendment's "What is bound, in
  order", after M3's, in the same step: `sqlite3_db_config` and `sqlite3_free`. Each is checked
  with `foreign-entry?` before it is bound, else `missing-api` naming it. Both are in the floor's
  build.
- **The optional one, `sqlite3_load_extension`,** follows them in the same step: bound only when
  `foreign-entry?` finds it, its absence recorded, never refused. It is reported where extension
  loading is asked for, as the M1 amendment says: an open whose settings opt in raises
  `&sqlite-extensions-unavailable` before anything opens (ADR-0021, decision 5).
- **The M1 amendment's "M4 turns on the C call alone" holds, and isn't the guarantee.** Ubuntu's
  library, CI's `main` lane's, is built `ENABLE_LOAD_EXTENSION`, and opens every connection with
  the C call already on (M4's pre-work). What keeps a connection that didn't opt in from loading
  is the verb's refusal in Scheme, before any C call (the maintainer's Q3, "Refuse in Scheme").
  `sqlite3_enable_load_extension` stays never bound, so SQL's `load_extension()` stays refused
  on every library, as measured with the C call on.
- **A library without extension loading is told by `foreign-entry?`,** never by `db_config`'s
  answer: upstream's `OMIT_LOAD_EXTENSION` build answers 0 to the op, and Apple's answers 21
  (M4's pre-work, question 4).
- **Each gets a decoy switch,** `DECOY_LACKS_<entry>`.
  - The two required ones are dealt by the pattern of five ([ADR-0005](0005-memory-gate.md),
    amended 2026-11-16), each a `missing-api` row.
  - **The optional one stays out of the pattern:** the list it deals holds required entry points
    alone, and a list of optional ones follows it, the two held together to the convention
    table. Dealt at its place, 43, it would have gone to `test-library-loading-real` with a
    `missing-api` row, for a library that must load.
  - Its rows, named in `test-library-loading-real`: the build without it loads, and native records
    it absent; an open with the opt-in raises the named condition with no `sqlite3_open_v2` in the
    call log (the maintainer's Q4, "The decoy"). The decoy's open always fails, so the log can
    never show a `sqlite3_db_config` call: what a row sees is whether the open was tried.

## Amendment, 2026-11-17: the optional entry point's prototype (M4 slice 2)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 2 ([its mutation log](../m4-slice-2-mutation-log.md)), from the slice and its review (Opus).

- **`test-constants` asks `sqlite3_load_extension`'s prototype in a compile of its own,** and the
  one compile asks the 43 required entry points alone. A header may mark the optional entry point
  unavailable, as Apple's SDK is believed to: the review's stand-in header, redeclaring it
  `__attribute__((unavailable))`, failed the whole compile and nine header rows with it. The
  stand-in is [research/m4-slice-2/stand-in/sqlite3.h](../research/m4-slice-2/stand-in/sqlite3.h),
  used with `C_INCLUDE_PATH` naming its folder, then the real header's.
- **The rule:** where that compile fails and native records the entry point absent
  (`load-extension-available?` `#f`), the row prints UNAVAILABLE and asserts both facts. Where it
  fails and the library has the entry point, the row fails. With the stand-in header on Guix's
  library, exactly that one row failed. The Mac step reports which the SDK's header gives.
- **This narrows two rules, for this one entry point:** ADR-0001's decision 3, a missing header
  or compiler fails the suite, never skips it; and the global constraints' "Constants and
  signatures are checked against `sqlite3.h`". Where a header refuses the optional entry point's
  prototype and the library lacks the entry point, its check is named UNAVAILABLE with both facts
  asserted, not failed. Every required entry point's check, a missing header and a missing
  compiler still fail the suite. The global constraints now say so.

## Amendment, 2026-11-18: an absolute path and macOS's `DYLD_*` (M4's closing review)

Proposed in M4's closing review, from the maintainer's Mac run after slice 5
([research/m4-mac/](../research/m4-mac/README.md), "Slices 3 to 5's Mac run", `run-dyld.sh` and
`out/slices-3-5/dyld.txt`). The rule is the maintainer's: "Document it" (2026-11-18).

- **"Loaded as given, with no search and no fallback" holds on Linux, not on macOS.**
  - On the Mac, `DYLD_LIBRARY_PATH`, set on Chez's own command line, redirects an absolute path by
    its leaf name. Naming Homebrew's folder, it made discovery's `/usr/lib/libsqlite3.dylib` load
    Homebrew's 3.54.1, while `sqlite-library-path` still answered `/usr/lib/libsqlite3.dylib`
    (case L1).
  - `DYLD_FALLBACK_LIBRARY_PATH` didn't redirect a path that names an existing file (E2).
  - On Linux, `LD_LIBRARY_PATH` redirected neither the override's path nor discovery's.
- **So decision 4's "a loaded library is reported with its path" reports the path asked for.** On
  the Mac, under `DYLD_LIBRARY_PATH`, that may not be the file loaded. `sqlite3_libversion` and
  `sqlite3_sourceid`, read from the library, are the loaded file's own.
- **No code changes for it.** Whoever can set `DYLD_*` in the process's environment can also
  inject code with `DYLD_INSERT_LIBRARIES`, so the environment is the caller's to control, inside
  the process's own trust boundary. The reference says so, under "Which SQLite"; this decision's
  Rejected bullet on a bare soname still holds, since a bare name is searched on every platform.
- **The same holds for an extension's absolute path** ([ADR-0021](0021-db-config-options-and-extension-loading.md),
  amended 2026-11-18).
