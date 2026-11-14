# ADR-0002: Find libsqlite3 at runtime: an override, else one candidate list per world, loaded once by absolute path

- **Status:** Accepted (the maintainer, 2026-11-13). Proposed in the brief, §3b. Amended
  2026-11-14: `not-threadsafe`, and what the Mac showed
  ([amendment](#amendment-2026-11-14-not-threadsafe-and-what-the-mac-showed-m1s-plan)).
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
- **What is bound, in order** (proposed in M1 slice 0, for acceptance with its PR):
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

