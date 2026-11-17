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
| [run-mac.sh](run-mac.sh) | Builds the plan's extensions with the Mac's flags, and runs `l1-load-extension.c` and `x1-ffi-load.sps` against one library |

The probes are the plan's own, [l1-load-extension.c](../m4-plan/l1-load-extension.c) and
[x1-ffi-load.sps](../m4-plan/x1-ffi-load.sps), with [ext.c](../m4-plan/ext.c) and
[noentry.c](../m4-plan/noentry.c). Each now takes an optional last argument, the files' suffix in
place of `so`. Only a file's name and its label change; the probes' directory is never rewritten.

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

## Results

None yet: the maintainer runs [mac.md](mac.md) when the Mac is free.
