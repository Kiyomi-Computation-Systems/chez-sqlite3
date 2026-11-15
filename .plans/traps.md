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

- **Chez's `utf8->string` drops one leading U+FEFF.** On 10.4.0,
  `(utf8->string #vu8(#xef #xbb #xbf #x69 #x64))` is `"id"`, and a UTF-8 transcoder decodes it
  the same way. Of two leading U+FEFF only the first goes, and one that isn't leading stays. M2
  slice 1's strict decoder answered `utf8->string`'s string once the bytes were well-formed, so a
  TEXT value starting with U+FEFF read back changed, which D6 exists to prevent. Its round trips
  sampled every 257th scalar value and skipped U+FEFF; the Opus review found it. The brief had
  called `utf8->string` exact, and the builder inherited that. The decoder now restores the
  U+FEFF, and a row round-trips every scalar value alone (ADR-0015, amended). M1's
  `c-string->string` read the same way. M2 slice 1 held that it decoded only SQLite's own text, and
  M2 slice 3 found otherwise: an error message can be the user's, and a trigger's
  `RAISE(ABORT, '\xFEFF;boom')` reached the raised condition as `"boom"`. `c-string->string` now
  keeps a leading U+FEFF too. Column values and names go through `strict-utf8->string`. (M2 slices
  1 and 3, chez-sqlite3)

- **An R6RS `\x` escape ends at its own semicolon.** `"a;\xFEFF;b"` holds four characters, `a`,
  `;`, U+FEFF and `b`, and `"\xFEFF "` is a reader error. So `"select 1;\xFEFF;"` has one
  semicolon, not two. M2 slice 3's tail suite hit it in its first draft. (M2 slice 3,
  chez-sqlite3)

- **Chez's `make-time` refuses a nanosecond field of 10⁹:** "invalid nanosecond 1000000000".
  Carry whole seconds into the seconds field. (M2 slice 3, chez-sqlite3)

- **A condition type's name is syntax, not a record type.** `(record-type-parent &sqlite-busy)`
  is "invalid syntax" when it expands, so a row written so kills its suite before any test runs.
  `(record-type-descriptor &sqlite-busy)` gives the record type. (M2 slice 1, chez-sqlite3)

- **Chez shares its empty bytevector.** `(eq? (make-bytevector 0) (bytevector-copy #vu8()))` is
  `#t`, so no row can tell a fresh empty result from a shared one. Assert an empty bytevector by
  its contents only. (M2 slice 1, chez-sqlite3)

- **Chez's `int` isn't C's, and `uptr` takes −1.** `int` takes −2³¹ to 2³²−1, and hands 2³¹ and
  above to C as negative numbers: `abs` bound `(int) int` answered −2147483648 for 2147483648.
  Beyond that it raises from the binding, inside whatever critical section made the call.
  `uptr` takes −1 as all ones, the same as 2⁶⁴−1. So M2 slice 2's brief was wrong to say an `int`
  binding of `sqlite3_bind_int64` gives a wrong value at the boundaries: at three it raises, and
  2³¹ reaches a 64-bit callee unchanged. And `SQLITE_TRANSIENT` written as −1 would bind
  correctly, seen only by a row holding it to the header. Every value a verb passes is checked to
  fit its C type before the section (ADR-0011, amended). (M2 slice 2's review, chez-sqlite3)

## SQLite

- **The `sqlite3` command can carry its own SQLite; Guix's does.** The brief's first evidence read
  `pragma compile_options` from the Guix home's `sqlite3` command, and recorded its `DQS=0` as the
  library's. A test rule in the brief, §7, was built on it. The command links no `libsqlite3`. In
  M0 slice 1, the library beside it, read through the FFI, reported no `DQS`, `RTREE` or
  `STMTVTAB` option ([research/guix-pin/](research/guix-pin/)). (chez-sqlite3)

- **SQLite's whitespace run continues on `\v`, and U+FEFF is whitespace wherever it stands.** A
  run starts on space, `\t`, `\n`, `\f` or `\r`, then runs on any of those or `\v`
  (`sqlite3Isspace`); `\v` can't start one. `EF BB BF` is a whitespace token of its own
  (`CC_BOM`). ADR-0014's tail scan, as accepted, held neither, and disagreed with SQLite's prepare
  on 56,425 inputs of 2 to 6 bytes. M2 slice 1 found it by preparing every short SQL on 3.53.1 and
  the floor, before any code was built on the model; the maintainer chose to match SQLite
  (ADR-0014, amended; [research/m2-slice-1/](research/m2-slice-1/)). (M2 slice 1, chez-sqlite3)

- **A REAL's text differs by version.** `cast(4.9406564584124654e-324 as text)` is that on 3.53.1,
  and `4.94065645841247e-324` on 3.45.1. So a row that reads a REAL as text writes no expected
  value, and compares two readings of the same library instead. (M2 slice 2, chez-sqlite3)

- **An interrupt doesn't end a wait in the busy handler.** `begin immediate` under another
  connection's exclusive lock, with a 600 ms busy timeout and `sqlite3_interrupt` at 100 ms, waited
  601 ms and answered BUSY, its interrupt flag left set. A long computation, interrupted the same
  way, stopped at 100 ms with 9. So a row that blocks a call can't end the wait early; only the
  timeout does. The M1 session found it in M3's research, and M2 slice 3 reproduced it
  ([research/m2-slice-3/](research/m2-slice-3/)). (M2 slice 3, chez-sqlite3)

- **Some BUSY no wait fixes.** COMMIT answers `SQLITE_BUSY`, "cannot commit transaction - SQL
  statements in progress", while the connection's own statement is mid-row. So `sqlite-busy?` isn't
  always "retry later": reset or finalize the statement first. (M3's research, reproduced in M2
  slice 3, chez-sqlite3)

- **A statement's column count changes at its next step, after an `ALTER TABLE` on its own
  connection too,** not only another's: a held `select *` read 2, then 2 after the ALTER, then 3
  after its step. So a count read before a step can be stale, and a column read checks the count
  in its own section. (M3's research, reproduced in M2 slice 3, chez-sqlite3)

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

- **A reason to drop a copied rule is checked against every rule the copy keeps.** M0 slice 4
  dropped chez-curl's explicit-key, alias, non-ASCII and tab rules from `check-floors`, reasoning
  that they protected rules about keys and this project had none. `check-action-pins.sh`, kept in
  the same slice, reads a key: `uses`. Reproduced: `- ? uses` then `: some-owner/some-action@main`
  passed the pin check, which counted the 9 pinned lines and saw no tenth. The review found it;
  the rules now live in `tests/check-ci.sh`. It is slice 2's lesson again, that a dropped piece
  takes its protection with it, and a reason written down is no check of it. (chez-sqlite3)

- **`env -i` in a test drops the variable that names a tool, and the default may only work
  here.** The launcher's T11b ran `make test` under `env -i`, so `CHEZ` fell back to the
  Makefile's default, `scheme` on `PATH`. The host and the container have one; CI's runner keeps
  Chez in `$RUNNER_TEMP`, on no `PATH`. On CI's second run, `make test` stopped at its
  prerequisites, and T11b's four "says why" checks failed: 79 passed, 4 failed. Reproduced in the
  container with a `PATH` of every tool but `scheme`: the same 79 and 4, then 83 with `CHEZ`
  passed through. (chez-sqlite3)

- **A value has more than one spelling, and a check of its text sees one.** `check-floors`
  refused any workflow line holding `3.45.1`. SQLite writes the same floor as `3045001`
  (`SQLITE_VERSION_NUMBER`) and as `3450100` (`sqlite-amalgamation-3450100.zip`). M0's closing
  review planted both in the `main` job, and `check-floors` and `check-ci` passed. Before
  checking a value by its text, list every form its users write it in. (chez-sqlite3)

- **A rule a record states is a rule only once a check holds it.** AGENTS.md and ADR-0005 said
  `make test` runs `check-ci`. Nothing failed when the prerequisite went: `check-help`,
  `check-test-fails` and `make test` all passed, and no `check-ci:` line appeared. The
  prerequisites `check-suites` and `check-floors` each had a plant in `check-test-fails`;
  `check-ci`, added a slice later, had none. Each new prerequisite comes with its plant. (M0's
  closing review, chez-sqlite3)

- **A scanner of forms that walks list tails finds forms that aren't there.** `test-native`'s
  first scanner counted a 16th `foreign-procedure` form in `native.sls`: `(syntax
  foreign-procedure)` in the binder's fender ends in a `(foreign-procedure)` tail, and so does
  the import clause's `(only (chezscheme) … foreign-procedure …)`. Read list elements, never
  tails. (M1 slice 2, chez-sqlite3)

- **A probe that blocks a plain foreign call can't release itself.** A collection requested by
  another thread waits for every thread, the blocked one too, so no thread of that process runs
  until the call returns. Only another process can release it: `test-native`'s FIFO row opens
  the FIFO from a shell. (M1 slice 2, chez-sqlite3)

- **`--trace-children` with a skip list sees nothing below what it skips.** Chez's `system` runs
  a static bash, which, traced, reports about 300 uninitialised-value errors and exits 9 for every
  child. Skipping the shell untraced every child it started, so a planted child leak passed. The
  gate runs each child under its own Valgrind instead (ADR-0005, M1 slice 3, chez-sqlite3).

- **GNU `env` reads `-u` only before its first assignment.** `env A=1 -u HOME sh` runs a command
  named `-u`: "env: '-u': No such file or directory". Unset first, then assign. (M1 slice 3,
  chez-sqlite3)

- **A row that finds its anchor by counting occurrences breaks when the file gains one.** A
  `test-check-ci` row named the 6th `CHEZ:` line of the workflow; slice 3's new step made it the
  7th, and the row broke on an edit it wasn't about. Anchor on a line's content. (M1 slice 3,
  chez-sqlite3)

- **A test that reads the name of the file `CHEZ` names assumes a layout.** CI's and the
  container's Chez is `…/bin/scheme`; Homebrew's on a Mac is `/opt/homebrew/bin/chez`.
  `test-check-floors`' `check-chez.sh` rows took the prefix from `CHEZ`'s path and failed 6 rows
  on the maintainer's Mac. They now build a `bin/scheme` that execs it when the name differs.
  (M1, the Mac's first hand run, chez-sqlite3)

- **macOS has no `/proc`.** Children that read `/proc/self/maps` to say whether they run under
  Valgrind printed `(valgrind . no-maps)` there, and rows that expected `no` failed; one child
  read it unguarded and died. A row's expectation says what its own process can see. (M1, the
  Mac's first hand run, chez-sqlite3)

- **One failure can answer differently by build.** `sqlite3_open_v2` on a FIFO answers
  `SQLITE_IOERR` on Guix's 3.53.1 and Homebrew's 3.54.1, and `SQLITE_CANTOPEN` on Apple's 3.51.0.
  Where the code isn't what a row is about, it names the codes it accepts, each measured. (M1,
  the Mac's first hand run, chez-sqlite3)

- **`cc -E` puts a system header's macro on a line of its own.** After `#include <sqlite3.h>`,
  `chez_v SQLITE_VERSION` came out as `chez_v `, and the value came on the next line, after a
  `# 2 "<stdin>" 3` marker. Read macros with `-dM -E`, or keep lines whole with `-P`. (M1
  slice 5, chez-sqlite3)

- **A compile option at its default may be unlisted.** SQLite lists `DEFAULT_MEMSTATUS` only when
  it isn't 1, so `-DSQLITE_DEFAULT_MEMSTATUS=1` is invisible to `sqlite3_compileoption_get`. Only
  the whole list can hold a rule about it. (M1 slice 5, chez-sqlite3)

- **A row that runs a script with `sh` can't see its execute bit.** Both of slice 5's new CI
  scripts were first written without one, and every row passed. The workflow runs them by path.
  `test-ci-sqlite` holds both bits. (M1 slice 5, chez-sqlite3)

- **A red run against a check that refuses the whole input proves no row.** Slice 5's new
  workflow, run against the old `check-ci`, failed every new row, because the old script refused
  the unedited file. Three rules' rows were logged as watched failing on that evidence. Turn each
  rule off in the new check instead. (M1 slice 5, chez-sqlite3)

- **A row that narrows `PATH` must hand each tool it names over by its path.** `test-ci-sqlite`'s
  build rows run with only their shims on `PATH`, and passed `CHEZ` on as given. In CI and the
  container that is an absolute path. On the maintainer's Mac the Makefile's default is the bare
  name `chez`, and both rows failed: "chez: command not found". (M1, the Mac's run on `497d45b`,
  chez-sqlite3)

- **An engine spends no ticks inside a critical section.** A 100,000-step loop given 10 ticks a
  slice took 10,001 slices outside a section, and 1 inside one. So a row that expects an expiry at
  every fuel fails once the work moves into a section. Assert the outcome at every fuel instead.
  (M1's closing review, chez-sqlite3)

- **`diff -r` follows symbolic links.** Two trees holding the same dangling link made it exit 2,
  "No such file or directory"; with `--no-dereference` it exits 0. The seam's fixtures hold such
  links. (M1's closing review, chez-sqlite3)

- **`false &&` before an `||` chain disables only its first test.** `false && A || B` runs `B`.
  A mutant meant to skip a whole check, written so, failed 1 row, not 5. Mutate the refusal
  instead: `true || fail …`. (M1 slice 5, chez-sqlite3)

- **A value is cut where its readers cut it.** `CHEZ_SQLITE3_GATE_CHILD` holds an absolute log
  path, and its readers cut it at whitespace, so a checkout path holding a space split it, and
  nothing refused one; `test-memory` now does. A plant for such a path is a real directory:
  `CURDIR` is the physical path, and a symlink's name never reaches it. (M1's owed fixes,
  chez-sqlite3)

- **A planted library must sit in a whole copy of the tree.** `test-library-loading` starts its
  children with `--libdirs src`, so a planted `native.sls` on a library path ahead of `src/` never
  reaches them, and a mutant there passes unseen. M2 slice 2's builder and reviewer ran every
  mutant from inside a copy. (M2 slice 2, chez-sqlite3)

- **A list that makes rows makes no row for what it drops.** `test-library-loading` builds a
  decoy and a `missing-api` row for each entry point in a written list. With one entry deleted the
  suite passed 90 of 90, and with four reordered 91 of 91. A row now holds the list to the
  convention table, which `test-conventions` holds to native. (M2 slice 2's review, chez-sqlite3)

- **A flag set by a blocked thread can't show that its call returned before a collection.** The
  blocked thread joins the collection before it runs its `set!`, so the flag read "still blocked"
  under every plain binding of M2 slice 3's four blocking calls, and only the time bound failed.
  Bound the collection's time against the call's, and read the time, not a flag. (M2 slice 3,
  chez-sqlite3)

- **At the floor, Valgrind can't tell a leaked statement from its connection.** The statement
  plant's loss record at 3.45.1 is byte-identical to the connection plant's: 57,432 bytes in one
  block. At 3.53.1 the statement adds 5,152 bytes in 19 blocks. So the plant's own counts line,
  `(statement . 1)`, is what holds that the counters saw the statement. (M2 slice 3, chez-sqlite3)

## Editing the records

- **A global replace also hits the sentence that defines what it replaces.** In M0 slice 0,
  `sed 's/ \*(provisional)\*//g'` over `global-constraints.md` removed every rule's marker. It also
  removed the marker from the preamble, the sentence that says what the marker means: "is marked
  *(provisional)* until" became "is marked until". A `grep -c` afterwards answered 0, where 1 was
  due. (chez-sqlite3)
- **A sibling's record cited by its number alone reads as one of ours.** Four citations in M0 slice 0's records named a sibling's
  record by its number alone, after a line break or the word "its". The slice's check of cited
  record numbers flagged the one with no record here; the other three needed a read. (chez-sqlite3)
