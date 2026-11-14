# Research: brief D7, a Mac's SQLite

Written and run 2026-11-13 (M1 slice 0), by the maintainer, on their one Mac: macOS 26.7.1
(25G241), arm64, Homebrew's Chez 10.4.1 (`tarm64osx`, threaded). The output, whole:
[mac-d7.txt](mac-d7.txt). The files were checked by sha256 on the Mac before the run. macOS 14
and 15 stay unmeasured (the M1 plan, §2).

## What it answers

For Apple's `/usr/lib/libsqlite3.dylib`, and for each Homebrew SQLite present, each in a Chez
process of its own:

- **Whether Chez loads it by absolute path,** and whether a file is there. Apple's lives in the
  dyld shared cache, with no file on disk (ADR-0002).
- **Its version,** version number, source id and threadsafe setting. Below 3.45.1 it is refused as
  `below-floor`, and with threadsafe 0 as `not-threadsafe`.
- **Every compile option it reports,** read through the FFI, never from a `sqlite3` command.
- **Which of the 45 entry points v1 binds are missing** (brief §4).
- **SQLite's memory count** before an open, while open and after the close. A build with
  `DEFAULT_MEMSTATUS=0` answers 0 while open, and the gate's check needs a positive control
  (the plan, §3.6).
- **JSON, JSONB and FTS5,** each run as SQL.
- **Extension loading, as v1 does it** (brief §2.5): `sqlite3_db_config`'s
  `ENABLE_LOAD_EXTENSION`, bound with `(__varargs_after 2)`, read, turned on and read again; then
  `sqlite3_load_extension` on a path that doesn't exist, whose message says whether a load was
  tried; and SQL's `load_extension()`, which must stay refused.

## How to run it

On the Mac, with `probe.sps` and `run.sh` side by side in one directory:

```
sh run.sh > mac-d7.txt
```

`run.sh` finds Chez as `$CHEZ`, then `scheme`, then `chez` on `PATH`, or takes its path as the
first argument: `sh run.sh /opt/homebrew/bin/chez > mac-d7.txt`. It writes nothing but its
output. Send back `mac-d7.txt` whole.

## The control: Guix's SQLite 3.53.1, in the container

[control-guix.txt](control-guix.txt), whole. It shows what a library that can load extensions
prints:

- `db_config` turns on the C call alone: the setting reads 0, then 1.
- `sqlite3_load_extension` then tries the load: `dlopen`'s "cannot open shared object file".
- SQL's `load_extension()` stays refused: `not authorized`.
- The memory count is 0 before the open, 61,360 while open, and 0 again after the close.

`run.sh` was run there too. With no dylib, the first probe printed the loader's message and
exited 1, and both Homebrew paths were reported absent.

## What the Mac showed

**Apple's `/usr/lib/libsqlite3.dylib`:**

- **It loads by absolute path, with no file on disk:** `file-on-disk` is `#f`, and `loaded` is
  `#t`. ADR-0002 decides existence by loading, not by `stat`, and here that is what works.
- **3.51.0 (3051000), above the floor.** On this macOS, discovery's one candidate is enough, so
  ADR-0002's "M1 revisits whether macOS should get more candidates" isn't triggered. Its source id
  ends `…dcaapl`: its last characters aren't hex, so Apple has changed it.
- **`THREADSAFE=2`,** multi-thread: it has mutexes, so `not-threadsafe` doesn't refuse it. By
  SQLite's documentation, a connection's default here is multi-thread mode, so `SQLITE_OPEN_FULLMUTEX` (brief D2) changes
  what this library does. Whether a connection opened with it is serialized isn't measured yet:
  `sqlite3_db_mutex` answers NULL for a connection that isn't.
- **`DEFAULT_MEMSTATUS=0`:** the memory count is 0 before the open, 0 while a database is open,
  and 0 after. A check that the count returns to its baseline passes here without testing
  anything. That is the plan's §3.6, measured.
- **`OMIT_LOAD_EXTENSION`:** `sqlite3_load_extension` and `sqlite3_enable_load_extension` are
  missing, the only two of the 45 entry points v1 binds. `sqlite3_db_config`'s
  `ENABLE_LOAD_EXTENSION` answers 21, `SQLITE_MISUSE`, and leaves the setting's cell untouched
  (-7, the probe's sentinel). SQL answers `no such function: load_extension`. So brief §2.5's
  belief is measured: Apple's SQLite is a library built without extension loading.
- **JSON, JSONB and FTS5 all work.** It also has `DQS=3` (double-quoted strings on),
  `ENABLE_API_ARMOR`, `USE_URI`, `MAX_VARIABLE_NUMBER=500000`, Apple's codec (`CODEC=see-cccrypt`)
  and `MUTEX_UNFAIR`.

**Homebrew's `/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib`:**

- **3.54.1 (3054001), source id dated 2026-10-16,** `THREADSAFE=1`, and no `DEFAULT_MEMSTATUS`.
  The memory count is 0, then 66,848 while open, then 0 after the close.
- **Extension loading works as v1 does it,** as in the Guix control: the setting reads 0, then 1;
  `sqlite3_load_extension` tries the load (`dlopen(…): tried: … (no such file)`); SQL's
  `load_extension()` stays `not authorized`.
- **All 45 entry points are present.**

`/usr/local/opt/sqlite` is absent. Whether Homebrew links its
SQLite into `/opt/homebrew/lib` wasn't checked. Nothing reads that directory: the override
reaches Homebrew's.

## What it settles, and what it leaves

- **Brief D7, for current macOS:** Apple's SQLite is above the floor, loads from the dyld cache by
  path, and has no extension loading.
- **For M1's slice 4:** on a library with `DEFAULT_MEMSTATUS=0`, the memory check can't vouch
  for anything. The maintainer chose on 2026-11-14: a suite reports the check unavailable, by
  name, and passes on its other checks, never silently (ADR-0005, amended). The Mac's hand runs
  reach it by default, through discovery.
- **For M1's slice 4, on the Mac:** whether `SQLITE_OPEN_FULLMUTEX` makes a connection to Apple's
  `THREADSAFE=2` library serialized, read through `sqlite3_db_mutex`.
- **For M4:** extension loading's opt-in checks for `sqlite3_load_extension` before it calls
  `sqlite3_db_config`, whose answer on Apple's library is `SQLITE_MISUSE`, not a refusal it names.
- **For M1's slice 5:** Homebrew's 3.54.1, dated 2026-10-16, is a candidate for the `current`
  lane's pin, to be checked against sqlite.org when the slice starts.
