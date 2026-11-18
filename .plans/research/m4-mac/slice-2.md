# M4 slice 2's Mac step

Slice 2's close-out in the ledger owes a Mac step (ADR-0001's consequence): `make test` and
`make check-variadic`, with Apple's library and with Homebrew's, on `main` once PR #37 has
merged. These are its commands, for zsh, in your chez-sqlite3 clone. They carry no comments,
and they write only under `build/m4s2-mac/`, which git ignores. Each `make test` runs every
suite, and there are two of them, so this takes a while.

It ran on 2026-11-18 and passed on both libraries: [README.md](README.md), "Slice 2's Mac
step", and the files in [out/slice-2/](out/slice-2/).

## 1. Get `main`, with slice 2 in it

Start from a clean tree: `git status --short` should print nothing that git tracks. The
`git log` command should print one line, slice 2's merge, ending `(#37)`.

```
git status --short
git switch main
git pull --ff-only
git log --oneline --grep='(#37)'
mkdir -p build/m4s2-mac
```

## 2. Apple's library

Discovery finds Apple's 3.51.0, and the compiler finds the SDK's `sqlite3.h`.

```
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
make test 2>&1 | tee build/m4s2-mac/apple-test.txt
make check-variadic 2>&1 | tee build/m4s2-mac/apple-variadic.txt
```

## 3. Homebrew's library

```
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
make test 2>&1 | tee build/m4s2-mac/brew-test.txt
make check-variadic 2>&1 | tee build/m4s2-mac/brew-variadic.txt
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
```

## 4. Send back

```
tar czf m4s2-mac.tgz build/m4s2-mac/*.txt
```

Send `m4s2-mac.tgz`. A step that fails is a result too: carry on to the next one.

## What we will read

From the ledger's Mac step:
- **With Apple's library:**
  - `test-native` names the load rows unavailable, since Apple's library has no
    `sqlite3_load_extension`;
  - `test-constants`' optional prototype row reports what the SDK's header declares;
  - `check-variadic` ends "all 7 steps ok, on tarm64osx".
- **With Homebrew's library:**
  - `test-native`'s load FIFO row runs on macOS for the first time. It should pass, released by
    the collector. dyld opens a FIFO twice ([README.md](README.md), run 2), and the row now
    releases the FIFO until the load answers;
  - `check-variadic` ends as with Apple's.
- **With both:** each `make test` ends with its `test: ran N, passed N` line.
