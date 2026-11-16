# M3 slice 4's groundwork: the probes

These probes are read-only research. The M2 session ran them on 2026-11-16 while slice 3 was being
built, to map every case slice 4 cites on both libraries and to close the gaps. The case list
they back fed slice 4's brief. [ADR-0017](../../../decisions/0017-with-transaction-and-savepoints.md)'s
slice 3 amendment cites `levels.c` and `failed-active.c`.

- **`levels.c`:** every error case inside `BEGIN IMMEDIATE`, and nested inside
  `SAVEPOINT chez_sqlite3_1`, each followed by ADR-0017's exit. Its O7 nested case, at
  `out/levels-*.txt:658`, is the failed commit whose rollback fails, which "Once" settles.
- **`failed-active.c`:** which `failed` statements SQLite still holds active (F1 to F6). An
  interrupted statement on its own is halted (F3 to F5).
- **`peer-view.c`:** a second connection's read beside a writer, after a NOMEM with the hard heap
  limit lifted alone (`:296`), and with the soft limit lifted too (`:310`). This is the C4 trap.
- **`p7-cached.c`:** the cached `COMMIT`, `ROLLBACK`, `RELEASE` and `ROLLBACK TO` under a sticky
  interrupt.
- **`nomem-rig.sps`:** the NOMEM rig, a step or a column read under the limit alone, through the
  library. Where the memory count is off, it marks every row `UNAVAILABLE`.
- **`interrupt-rig.sps`:** an interrupted write through the library, from a watchdog thread.
- **`reentry.sps`:** the re-entry shapes on Chez 10.4.0 (H1, K, L).

`out/` holds each probe's output on Guix's 3.53.1 and the floor, 3.45.1. The Chez rigs also ran
on the floor built with `SQLITE_DEFAULT_MEMSTATUS=0`. Only the `time:` lines differ between runs.

**How these files were kept.** The probes first lived in a git-ignored scratch directory of the M2
session's worktree, and were lost when that worktree was removed after #23 merged. They were
recovered from the groundwork agent's transcript, by replaying its writes and edits in order, then
run again. The outputs here are that rerun. The lines the records cite read the same, at the same
line numbers.

## Running them

From the repository's root, on the host, set up once:

```
mkdir -p build/groundwork/tree/build build/groundwork/scratch
tar --exclude=./build --exclude=./.git -cf - . | tar -xf - -C build/groundwork/tree
ln -s ../../../m3-floor build/groundwork/tree/build/m3-floor
ln -s ../../../scheme-libs build/groundwork/tree/build/scheme-libs
```

`build/m3-floor` is the floor library and its header, as CI's `floor` lane builds them.

The C probes, on both libraries:

```
scripts/guix-env sh -c 'cd build/groundwork/tree && d=$(mktemp -d ../scratch/run.XXXXXX) && \
  sh .plans/research/m3-slice-4/groundwork/run.sh "$d" ../out levels peer-view p7-cached failed-active'
```

For the Chez rigs, first build the memory-count-off floor from the floor's amalgamation in
`build/m3-floor-dl/sqlite-autoconf-3450100`:

```
scripts/guix-env sh -c 'cd build/groundwork/tree && P=../floor-memstatus-off; \
  S=../../m3-floor-dl/sqlite-autoconf-3450100; mkdir -p $P/lib $P/include && \
  $CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_DEFAULT_MEMSTATUS=0 -Wl,-z,defs \
    -o $P/lib/libsqlite3.so.0 $S/sqlite3.c -lpthread -lm && cp $S/sqlite3.h $S/sqlite3ext.h $P/include/'
scripts/guix-env sh -c 'cd build/groundwork/tree && d=$(mktemp -d ../scratch/run.XXXXXX) && \
  sh .plans/research/m3-slice-4/groundwork/run-chez.sh "$d" ../out nomem-rig interrupt-rig'
scripts/guix-env sh -c 'cd build/groundwork/tree && \
  $CHEZ --program .plans/research/m3-slice-4/groundwork/reentry.sps'
```

The scripts' own usage comments name the scratch layout they were written in, where the probes sat
beside the tree as `../probes`. The commands above replace those.
