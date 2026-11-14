# Research: two facts the M1 plan rests on

Date: 2026-11-13 (M1 slice 0), in the Guix container: SQLite 3.53.1, Chez 10.4.0, through bare FFI
([probe.sps](probe.sps)). Run from the git-ignored `build/`, since the container sees only the
project tree:

```
mkdir -p build
scripts/guix-env sh -c 'd=$(mktemp -d build/m1-probe.XXXXXX) && $CHEZ --program .plans/research/m1-plan/probe.sps "$d"'
```

Each run needs a fresh directory: in a used one, the file exists before the open.

Output, whole (Guix's locale warning filtered):

```
before open, exists: #f
open rc 0; after open, before any statement, exists: #t, size 0
close rc 0
prepare rc 0; step rc 100 (100 is ROW); journal_mode answers "memory"
finalize rc 0; close rc 0
```

- **`sqlite3_open_v2` creates the file at open,** before any statement runs. So the open reaches
  the file system, and can block on it like `sqlite3_close` (the plan's §3.2).
- **`PRAGMA journal_mode=wal` on a `:memory:` database answers `memory`,** with every return code
  0. A setting is checked only by reading its row back, which needs M2's statements, so the
  settings list moves to M3 (the plan's §2).

Not measured at the floor, 3.45.1; slice 5's `floor` lane is the first place to run it there.
