# What M3 slice 5 measured

Three probes, run 2026-11-16 in the Guix container on Chez 10.4.0, from the repository's root:
`busy-probe.sps` and `locks.sps` on Guix's libsqlite3 3.53.1 and at the floor, 3.45.1;
`number-twice.sps`, which loads no SQLite, once. Their output is in [output.txt](output.txt), each
run after the command that made it. Part A's two probes ran first from the worktree's git-ignored
`build/probe/`, and are kept here; `busy-probe.sps` now makes its database in `build/` and removes
it itself, by `delete-file` and `delete-directory`, and closes every connection it opens.
`locks.sps` is part B's, and does the same.

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-5/busy-probe.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-5/locks.sps'
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-5/number-twice.sps'
```

At the floor, each SQLite probe runs with the floor's library and headers, as a local floor run
must ([traps.md](../../traps.md)):

```
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-5/busy-probe.sps'
```

## Part A's probes

### `number->string`, resumed twice ([number-twice.sps](number-twice.sps))

`(string-append "PRAGMA busy_timeout = " (number->string 1234))` as an engine, at every fuel until
it completes unexpired, 41; at each fuel that expires, its remainder resumed to its end twice.
**At fuels 22, 23, 31 and 32 the second resume answered `"PRAGMA busy_timeout = "`,** where the
first answered the whole string: `number->string` writes through a string port whose buffer the
first resume had drained, state the continuation does not hold. `string-append` alone, the
control, answered alike at every fuel to its 9. So a remainder of the open's checks, resumed a
second time, computes other SQL than the first; `test-open-engines` found it, at fuels 130, 131,
139 and 140 of the open, as "incomplete input" from SQLite. The open's flag, its first
expression, refuses such a resume at the open's section (ADR-0018, amended in M3 slice 5).

### A failed open's descriptor ([busy-probe.sps](busy-probe.sps))

A holder in `BEGIN EXCLUSIVE` with a write, then opens with settings beside it. Alike on both
libraries:

- **`busy-timeout` runs first:** listed last, at 1500 ms, `synchronous` waited 1501 to 1502 ms at
  its prepare, then raised `&sqlite-busy`, `"PRAGMA synchronous = 2"`, with no offset. With no
  `busy-timeout` it answered at once, through both verbs, `call-with-database`'s procedure never
  called. `journal-mode wal` after a 200 ms `busy-timeout` waited 201 ms. `foreign-keys` opened at
  once. Each failed open left only the holder counted, its three statements.
- **SQLite's unix VFS keeps a closed connection's descriptor while another connection of the
  process holds a POSIX lock on the file.** The holder held 2 descriptors, the file and its
  journal. After the first failed open the process held 3, and still 3 after four more, each
  open reusing the one kept. Once the holder rolled back, 1, its file alone; once it closed, 0. So
  a row that counts descriptors reads them only once the holder has let go, as
  `test-open-settings` and `test-open-locks` do.

## Part B's probe: each setting beside each lock ([locks.sps](locks.sps))

Each setting, with `(busy-timeout . 1500)` before it, opened fresh beside a holder of a lock,
timed. Alike on both libraries, every wait 1501 to 1503 ms, every other answer under 6 ms.

- **Rollback journal, under another's exclusive lock:** every `journal-mode` and every
  `synchronous` waited out the timeout, then raised `&sqlite-busy` naming the setting's SQL;
  `foreign-keys`, `temp-store` and `trusted-schema` opened at once. Slice 0's P2 measured
  `journal_mode = wal` and the read form; the other three values wait too.
- **Under a read,** only `journal-mode wal` waited; `delete`, `truncate`, `persist` and
  `synchronous` opened. **Under a reserved lock,** `journal-mode wal` was refused at once, and
  everything else opened.
- **On a WAL file, leaving WAL, `delete`, `truncate` or `persist`, was refused at once beside a
  holder that had read the file,** idle after a `select`, a `pragma journal_mode` or a write, or
  holding a read, a reserved or an exclusive lock. **Beside a holder opened and never used, it
  opened:** SQLite opens a file lazily, so a connection that has read nothing holds nothing of
  it. Slice 0's P2 wrote "even an idle one" of a holder that had made the file and written it.
  Once the holder had closed, each opened. `journal-mode wal` and `synchronous` opened beside
  every holder.

`tests/test-open-locks.sps` asserts the cases the M3 plan names, and the unused holder.

## Part C's probes: the review's fixes

Three probes, run 2026-11-16 in the Guix container on Chez 10.4.0; none loads SQLite. Their
output is at the end of [output.txt](output.txt).

```
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-5/number-interleaved.sps'
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-5/gc-ticks.sps'
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-5/section-end.sps'
```

- **`number->string`, one remainder resumed while an earlier resume of it is pending**
  ([number-interleaved.sps](number-interleaved.sps)): R taken at F, resumed at G until it expires
  as R1, then R to its end, then R1. At F 4, G 27, R answered
  `"PRAGMA busy_timeout = 12341234"`, the digits twice, and R1 `"PRAGMA busy_timeout = "`; at F
  22, G 2, both answered `""`. Part A's `number-twice.sps`, resumed one after the other, found
  only `""`. A run that overtakes the first reaches the open first, so no claim of the call's can
  refuse what it computed: `test-open-interleave` found `busy_timeout = 12341234` sent to SQLite
  through `call-with-database` at fuel 83, read back as a mismatch. The open verbs now run their
  checks in one critical section, where no remainder is taken.
- **A collect request costs a run ticks** ([gc-ticks.sps](gc-ticks.sps)): an engine of 300
  allocating calls first completes at fuel 5238 with no collection pending, and at 5253 with one
  every 4 KiB, whatever the collect-request handler does, even nothing. So two runs of one call at
  one fuel can stop a tick or more apart: `test-open-interleave` found a trial two ticks before
  its control. A row that judges a run by another run at the same fuel collects first, with
  `collect-trip-bytes` raised above what the runs allocate; or judges each run by its own
  observation.
- **Where an interrupt that came pending inside a critical section is handled**
  ([section-end.sps](section-end.sps)): a keyboard interrupt, SIGINT raised from C inside the
  section, is handled as the section ends, before the next expression. A timer spends no ticks
  inside a section, 9 of 10 left after 1000 calls there, and an engine of fuel 10 around such a
  section completes with 3 left. So the instructions just after a section are out of an engine's
  and a timer's reach, but not of a signal's: `call-with-database` records its connection inside
  the open's section, and `test-open-interleave` raises SIGINT inside each section to hold it.
  The probe loads glibc's `libc.so.6` by name, so it runs on Linux.
