# Traps: the full accounts

AGENTS.md carries each trap's one-line rule; this file keeps the incident behind it. Each account
names the repository it happened in. The traps the family hit before this repository existed are
told in chez-curl's `.plans/traps.md`.

## Chez and the FFI

- **Chez fixes no order for a call's arguments, and a probe follows the same rules as a test.**
  M0 slice 0's value probe called
  `(printf "…" (bind-double st 1 1.5) (step st) (col-type st 0))` in a `--script` program.
  `bind` returned `SQLITE_MISUSE` because `step` had already run. The control case exposed it:
  binding 1.5 can't fail, yet it failed exactly as NaN did. Rewritten with `let*`, the probe
  bound 1.5 cleanly and showed that NaN stores NULL.

  Measuring why showed that the rule AGENTS.md inherited was wrong on this Chez in both halves.
  Compiled code ran the arguments left to right, and `interpret` right to left. A probe like
  this one goes neither way: `--script` and `load` hand each simple top-level form to the
  interpreter (`compile-interpret-simple`), and that path ran them `cab` or `bca`. The first
  account blamed compiled code for those orders; M0 slice 1's review found the parameter, and
  turning it off gave `abc` at every site. The probe and its outputs are in
  [research/evaluation-order/](research/evaluation-order/). (chez-sqlite3)

## SQLite

- **The `sqlite3` command can carry its own SQLite; Guix's does.** The brief's first evidence read
  `pragma compile_options` from the Guix home's `sqlite3` command, and recorded its `DQS=0` as the
  library's. A test rule in the brief, §7, was built on it. The command links no `libsqlite3`. In
  M0 slice 1, the library beside it, read through the FFI, reported no `DQS`, `RTREE` or
  `STMTVTAB` option ([research/guix-pin/](research/guix-pin/)). (chez-sqlite3)

## Checks and environment

- **A check passes whenever something else produces what it looks for.** M0 slice 1's review
  found three self-test assertions that read a symptom instead of the property:
  - `loopback-only` read "no route to 192.0.2.1". A container with a network also gives that
    when the host has no default route, as when it is offline. Reproduced: with `--network`, in a
    user network namespace holding `lo` and a dummy interface and no default route, every
    assertion passed. `interfaces` now reads `/proc/net/dev`.
  - `sqlite-header` read a version string from whichever `sqlite3.h` the compiler found first.
    Reproduced: a fake 3.37.2 header put first on `C_INCLUDE_PATH` passed. `header-matches-library`
    now compares the header's number with the library's.
  - `chez-variable` read "under the profile". Reproduced: `CHEZ=$GUIX_ENVIRONMENT/bin/petite`
    passed, and petite has no compiler. It now requires the profile's `scheme` itself.

  All three came from chez-curl's self-test, which shares them. (chez-sqlite3)
- **A switch tested as non-empty is on at 0.** `scripts/guix-env` took any non-empty
  `GUIX_ENV_DRY_RUN` as a dry run. Reproduced: with `GUIX_ENV_DRY_RUN=0`, `make check-guix`
  printed the guix command and passed, with no container run. Only `1` is a dry run now, and T9
  checks that 0 runs guix. chez-curl's launcher shares the gap. (chez-sqlite3)

- **A pattern written against a tool's padding misses a line padded otherwise.** M0 slice 3's
  measurement matched Valgrind's leak summary as `==N==` and four spaces before each kind.
  Valgrind right-aligns the kinds, so "possibly lost" has six, and the first table had no
  possibly-lost column. The slice's review found 12,856 bytes there in one case. The pattern now
  matches the words after any run of spaces. (chez-sqlite3)

## Editing the records

- **A global replace also hits the sentence that defines what it replaces.** In M0 slice 0,
  `sed 's/ \*(provisional)\*//g'` over `global-constraints.md` removed every rule's marker. It also
  removed the marker from the preamble, the sentence that says what the marker means: "is marked
  *(provisional)* until" became "is marked until". A `grep -c` afterwards answered 0, where 1 was
  due. (chez-sqlite3)
- **A sibling's record cited by its number alone reads as one of ours.** Four citations in M0 slice 0's records named a sibling's
  record by its number alone, after a line break or the word "its". The slice's check of cited
  record numbers flagged the one with no record here; the other three needed a read. (chez-sqlite3)
