# M4's Mac run after slice 5

The M4 plan's §5 owes a Mac run for slices 3 to 5, before M4's closing review, with Apple's
library and with Homebrew's. It covers Apple's `defensive` start; the opt-in refused there, for
real, by the named condition; the load rows unavailable on Apple's and run on Homebrew's, with
the extension compiled by the Mac's `cc` as a `.dylib`; and FTS5 and JSON on both. Slice 4's check
(PR #45) added the questions only a Mac can answer, listed under "What we will read".

These are its commands, for zsh, in your chez-sqlite3 clone, on `main` once PR #45 has merged.
They carry no comments, and they write only under `build/m4s35-mac/`, which git ignores. Each
`make test` runs every suite, so this takes a while.

It ran on 2026-11-18: Homebrew's library passed everything, Apple's all but one row, a fault in
the suite since fixed, and `DYLD_LIBRARY_PATH` redirected both absolute paths. The results are in
[README.md](README.md), "Slices 3 to 5's Mac run", and the files in
[out/slices-3-5/](out/slices-3-5/).

## 1. Get `main`, with slice 4 in it

Start from a clean tree: `git status --short` should print nothing that git tracks. The
`git log` command should print one line, slice 4's merge, ending `(#45)`.

```
git status --short
git switch main
git pull --ff-only
git log --oneline --grep='(#45)'
mkdir -p build/m4s35-mac
```

## 2. Apple's library

```
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
make test 2>&1 | tee build/m4s35-mac/apple-test.txt
```

## 3. Homebrew's library

```
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
make test 2>&1 | tee build/m4s35-mac/brew-test.txt
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
```

## 4. Whether the environment can redirect an absolute path

```
CHEZ=$(command -v chez || command -v scheme)
BREW=$(brew --prefix sqlite)
CHEZ=$CHEZ sh .plans/research/m4-mac/run-dyld.sh $BREW/lib/libsqlite3.dylib $BREW/include $BREW/lib build/m4s35-mac/dyld
```

It ends with `run-dyld.sh: done`, in under a minute. If it says `build/m4s35-mac/dyld exists`,
run `rm -rf build/m4s35-mac/dyld`, then step 4 again.

## 5. Send back

```
tar czf m4s35-mac.tgz build/m4s35-mac/*.txt build/m4s35-mac/dyld/dyld.txt
```

Send `m4s35-mac.tgz`. A step that fails is a result too: carry on to the next one. In
`dyld.txt`, your home folder is written `~`.

## What we will read

- **With both:** each `make test` ends with its `test: ran N, passed N` line.
- **With Apple's library** (the plan's §5):
  - `test-open-db-config`'s starts, `defensive` on at start, as slice 3's docs say;
  - `(enable-load-extension . #t)` refused by `&sqlite-extensions-unavailable`, before anything
    opens;
  - `test-load-extension` and its engines suite naming every load row unavailable, with
    `tests/extension.c` not built (ADR-0001, amended in slice 4). These branches have never
    run on a library without `sqlite3_load_extension`;
  - `test-fts5` and `test-json` on Apple's 3.51.0.
- **With Homebrew's library** (slice 4's check):
  - `tests/extension.c` compiled by Apple clang with `-Wall -Werror -dynamiclib` against
    Homebrew's `sqlite3ext.h`, which `C_INCLUDE_PATH` finds;
  - `test-load-extension`'s failures row ("each failure raises &sqlite-error from
    load-extension! …"), which compares the verb's message with a raw load's on another
    connection. That holds only if dyld words a missing file, an empty file, a directory and a
    file that is no Mach-O the same across two loads;
  - its relative-path row ("on a connection that opted in, a relative path, a bare name …"),
    whose raw load climbs from the clone to the temporary folder, `/var` on a Mac, a link to
    `/private/var`;
  - the engine suites under the Mac's temporary folder, whose path is about 49 characters: their
    fuels move with its length (ADR-0021's engine table);
  - `test-fts5` and `test-json`.
- **`dyld.txt`:** dlopen(3) documents that macOS searches `DYLD_LIBRARY_PATH` by a path's leaf
  name before the path itself, and `DYLD_FALLBACK_LIBRARY_PATH` after it fails, even for a path
  holding a slash. On Linux, `LD_LIBRARY_PATH` redirected neither (the script's control run).
  - `L0` and `L1`: the library discovery finds, with `DYLD_LIBRARY_PATH` naming Homebrew's
    folder in `L1`. If `L1` reports 3.54.1 where `L0` reports 3.51.0, the environment redirected
    the absolute path ADR-0002 loads "as given";
  - `E1`: `b`'s absolute path with `DYLD_LIBRARY_PATH` naming `a`. If it answers `E3`'s refusal
    ("chez_failing refused") rather than `E0`'s `(loaded 1.5)`, Q16's reason, that the
    environment can't redirect an absolute path, doesn't hold on the Mac;
  - `E2`: a path where no file stands, with `DYLD_FALLBACK_LIBRARY_PATH` naming `b`. `(loaded
    1.5)` means the fallback search found `b`'s file by its leaf name;
  - each line's `(seen …)` shows the variables as Chez saw them. macOS strips `DYLD_*` when it
    launches a protected binary, so the script sets them on Chez's own command line. A `#f`
    where the case sets one means the variable never reached Chez, and the line settles
    nothing.
