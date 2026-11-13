# ADR-0002: Find libsqlite3 at runtime: an override, else one candidate list per world, loaded once by absolute path

- **Status:** Accepted (the maintainer, 2026-11-13). Proposed in the brief, §3b.
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
   `invalid-override`, `not-found`, `load-failed`, `below-floor` or `missing-api`. `not-found`
   lists every candidate it checked.

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
  whether macOS should get more candidates.
- **The reason symbols are the contract.** Tests assert the reason, never the remedy text.
