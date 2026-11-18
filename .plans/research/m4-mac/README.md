# Research: M4's extension loading on the Mac

Written 2026-11-17, for the M4 plan's open item "The Mac's load" (§7 of
[the plan](../../2026-11-17-m4-plan.md)). The plan's load probes ran on Linux alone
([research/m4-plan/](../m4-plan/README.md)). Slice 4's rows assert whole messages, and macOS's
dlopen words its failures its own way, SQLite retries a path there with `.dylib`, and a bare
name's search of the working directory is documented, not measured. This step reads those on a
Mac before slice 4 is written, where the plan left them to the hand run after slice 5.

## The files

| File | What it is |
|---|---|
| [mac.md](mac.md) | The maintainer's steps on the Mac, for zsh |
| [slice-2.md](slice-2.md) | Slice 2's own Mac step, `make test` and `make check-variadic` with both libraries, once PR #37 has merged |
| [run-mac.sh](run-mac.sh) | Builds the plan's extensions with the Mac's flags, and runs `l1-load-extension.c`, `x1-ffi-load.sps` and `fifo.c` against one library |
| [fifo.c](fifo.c) | `dlopen` and the load on a FIFO, each in a child process and bounded, with no writer and with one; and `dlopen`'s own reasons for a directory and an empty file. Added after run 1 |
| [out/run-1/](out/run-1/), [out/run-2/](out/run-2/) | Each run's files, as `run-mac.sh` wrote them |

The probes are the plan's own, [l1-load-extension.c](../m4-plan/l1-load-extension.c) and
[x1-ffi-load.sps](../m4-plan/x1-ffi-load.sps), with [ext.c](../m4-plan/ext.c) and
[noentry.c](../m4-plan/noentry.c). Each now takes an optional last argument, the files' suffix in
place of `so`. Only a file's name and its label change; the probes' directory is never rewritten.

After run 1, `l1-load-extension.c` line-buffers both its outputs, and L6's writer opens the FIFO
without blocking, every 10 ms from 500 ms until the load returns. It writes how many of those opens
found a reader to the timing file. A load that never opens the FIFO, or opens it twice, can no
longer hang the probe.

## The check on Linux

Run 2026-11-17 in the Guix container: Chez 10.4.0 (`ta6le`), gcc 16.2.0, x86_64.

- **Without the suffix, nothing changed:** `run.sh`'s `l1-load-extension` on Guix's 3.53.1, the
  floor and 3.54.1, and `run-x1.sh`'s three gate modes on 3.53.1, matched
  [out/](../m4-plan/out/) byte for byte. The FIFO modes differed in their times alone, by 8 ms.
- **`run-mac.sh` on Guix's 3.53.1, with `so`:** its `l1-so.txt`, less its exit line, matched the
  plan's `l1-load-extension-guix-3.53.1.txt` byte for byte, and `x1-gate-so.txt` and
  `x1-gate-none-so.txt` matched the plan's, less the exit lines.
  - `x1-gate-leak-so.txt` differed in one line: without Valgrind, `memory-used-after` read 440,
    where under it the plan read 432. Both show the leak the plant makes; not read further.
- **With `SUFFIXES="dylib so"`:** both runs completed, and the `so` run matched the one before.
  In the `dylib` run, every row named `.dylib`, and on Linux `DIR/ext, no suffix` failed:
  SQLite's retry there adds `.so`, `"DIR/ext.so: cannot open shared object file"`.

### After run 1

- **Its output on Linux is unchanged:** `run.sh`'s `l1-load-extension` on Guix's 3.53.1, the
  floor and 3.54.1 matched [out/](../m4-plan/out/) byte for byte. The FIFO load took 500.3 to
  500.4 ms. The timing files have one line more, the writer's opens that found a reader: 1 each.
- **Run 1's symptom, reproduced:** L6's load pointed at a missing file, so it opens no FIFO.
  The old probe exited 142 after 20 s, its output cut off mid-line, like the Mac's. The new one
  ended at once: "the load returned before the writer opened it", with 0 opens.
- **`fifo.c` on Guix's 3.53.1:** with no writer, `dlopen` and the load were still waiting after
  3000 ms; the release's first open let them go, "file too short". With one writer, both
  returned at 500 ms. With every call made to hang, a mutant, each case was killed after its
  bounds and printed "(no answer)".
- **`run-mac.sh` on Guix's 3.53.1:** done in 8 s; `l1-so.txt` reached L7 and `(exit 0)`.

## Results

### Run 1, 2026-11-17

macOS 26.7.1 (25G241), Darwin 25.6.0, arm64; Chez 10.4.1, `tarm64osx`; Apple clang 21.0.0;
Homebrew's SQLite 3.54.1; commit `d1792e4`. The files are [out/run-1/](out/run-1/).

- **It stopped in L6.** Both l1 runs exited 142, SIGALRM: the alarm is set around L6 alone. The
  output was fully buffered, so the kill lost all but its first 4 KB, from partway through L3 on,
  and both timing files. Either the load never opened the FIFO, and the writer's blocking open
  waited for a reader that never came, or the load opened it again once the writer let go. The
  first reproduces the run's symptom on Linux (above); run 2 found the second.
- **The compiles:** `-dynamiclib` built `ext.c` and `noentry.c`, and the probe built, without a
  message.
- **The `.dylib` retry:** `DIR/ext`, with no suffix, loaded in the `dylib` run and failed in the
  `so` run. SQLite retries a path with `.dylib` appended.
- **A bare name:** `ext.dylib`, with the working directory `DIR`, loaded (0), where Linux refused
  `ext.so` (1). Q16 refuses a bare name before the call either way.
- **`.so` files load:** built by `-dynamiclib` and named `.so`, every file given by its whole
  path loaded or failed as its `.dylib` twin did. Only the no-suffix row differs.
- **Every other code matched Linux's,** row by row. The messages differ, but for the init's own:
  - a missing file, an empty file and a directory all read `dlopen(P.dylib, 0x000A): tried:
    'P.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OSP.dylib' (no such file), …`,
    P the path given: the message is the retry's, as on Linux;
  - an entry point the file lacks reads `dlsym(0x75580a40, sqlite3_noentry_init): symbol not
    found`. It names a handle, not the file;
  - an init that fails reads "error during initialization: chez_failing refused", as on Linux.
- **SQLite cuts the message short.** Its buffer is the path's length plus 300 bytes
  (`sqlite3LoadExtension`, 3.54.1), so the message keeps its first path-length + 298 bytes.
  dyld's lists ran past that, and every one was cut there.
- **L3's first rows match Linux's:** after a failed load, errcode 0, "not an error".
- **The FFI load on arm64,** `__collect_safe`, its message read and freed by `sqlite3_free`: in
  both runs `gate` and `gate-none` ended at `memory-used-after 0`, and `gate-leak` at 448, where
  Linux, also without Valgrind, read 440.

### Run 2, 2026-11-17

The same Mac, library and tools, at commit `a4eb12e`, this branch's first. The files are
[out/run-2/](out/run-2/). Every probe exited 0, and `fifo.c` compiled without a message.

- **dyld opens a FIFO twice, and each open waits for a writer** (`fifo.txt`):
  - with no writer, `dlopen` and the load were still waiting after 3000 ms. Two of the
    release's opens found a reader, and they returned at 3021 and 3016 ms;
  - with one writer at 500 ms, which found a reader, both were still waiting 3000 ms later. One
    more open let them go, at 3506 and 3505 ms;
  - `dlopen`'s own message marks the FIFO "(not a file)" twice, as it does a directory, which
    returned at once: `tried: 'DIR/fifo.dylib' (not a file),
    '/System/Volumes/Preboot/Cryptexes/OSDIR/fifo.dylib' (no such file), 'DIR/fifo.dylib' (not a
    file)`. An empty file's reason is empty: `'DIR/empty.dylib' ()`;
  - the load's message is its retry's, `fifo.dylib.dylib` (no such file), a path that isn't
    there, so the retry waits for nothing.
- **L6:** the writer, which no longer blocks, found a reader twice. The load returned after
  513.6 ms (`dylib`) and 517.0 ms (`so`), answering 1: "the load returned after the writer
  opened it", as on Linux, where it took 500.3 ms and one open.
- **L3 to L8 match Linux's row for row,** with the messages masked, but for run 1's two rows and
  one count that follows from them: after `./ext.dylib`, `chez_inits()` counted 2, the bare name
  having loaded too:
  - L3: after a failed load, errcode 0, "not an error", with a slot and with NULL;
  - L4: each load ran the init again, counting 1, 2, 3, and a close unloaded it, a third
    connection counting 1;
  - L5: another thread's load answered 0;
  - L8: beside a held row, the second load answered 1, extended 5, "error during
    initialization: ", and the PERSISTENT select re-prepared only after the third load, with
    nothing held;
  - L7: SQL's `load_extension()` answered "not authorized".
- **A file's first load took 135 to 278 ms,** five files in each run (135.0 to 138.8 ms in the
  `dylib` run, 141.1 to 277.9 ms in the `so` run), and every later load under 3 ms. Linux's
  first loads took under 1 ms.
- **x1:** every file the same as run 1's.

### What it means for the slices

- **Slice 2, `test-native`'s load FIFO row:** the load waits on a FIFO on the Mac too, so the
  row can measure `__collect_safe` there. By its code, though, it would fail there. Its collector
  opens the FIFO for writing once (`exec 3<>`), and dyld's second open waits until the
  watchdog's, at 30 s: `released-by-the-watchdog`. The row has to release until its loader
  returns, twice on this Mac. That is a prediction, made from fifo.txt rather than measured;
  slice 2's Mac step runs the row.
- **Slice 4's failure messages:** macOS's text and Linux's differ, and SQLite cuts the Mac's at
  the path's length plus 298 bytes (run 1). Only the init's own message, "error during
  initialization: …", reads the same on both.
- **A bare name loads from the working directory on the Mac,** so Q16's refusal before the call
  is the only thing that keeps the same rule on both systems.
