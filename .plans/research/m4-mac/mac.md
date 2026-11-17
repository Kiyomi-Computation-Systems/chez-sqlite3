# M4's extension loading on the Mac

These steps answer one question the M4 plan leaves open for a Mac (its §7): how Homebrew's SQLite
loads an extension built by the Mac's `cc`. They run the plan's two load probes against
Homebrew's SQLite twice, once with the extension files named `.dylib` and once `.so`. Apple's
library has no `sqlite3_load_extension` (the pre-work's census), so it isn't run.

Everything below is for zsh, in your chez-sqlite3 clone. The commands carry no comments. They
write only under `build/m4-mac/`, which git ignores. The run takes under a minute.

## 1. Get the probes

They're on `main`. Start from a clean tree: `git status --short` should print nothing.

```
git status --short
git switch main
git pull --ff-only
```

## 2. Name things

```
CHEZ=$(command -v chez || command -v scheme)
BREW=$(brew --prefix sqlite)
echo $CHEZ $BREW
ls $BREW/lib/libsqlite3.dylib $BREW/include/sqlite3.h $BREW/include/sqlite3ext.h
```

The `echo` should print a Chez path and Homebrew's SQLite folder, and the `ls` three files.

## 3. Run the probes

```
CHEZ=$CHEZ sh .plans/research/m4-mac/run-mac.sh $BREW/lib/libsqlite3.dylib $BREW/include build/m4-mac
```

It ends with `run-mac.sh: done`. A probe that fails or crashes is a result too: its file keeps
its exit status. If it says `build/m4-mac exists`, run `rm -rf build/m4-mac`, then step 3 again.

## 4. Send back

```
tar czf m4-mac.tgz build/m4-mac/*.txt
```

Send `m4-mac.tgz`. In it, your home folder is written `~`, and the probes' folders `DIR` and
`SCRATCH`.

## What we will read

- **`l1-dylib.txt`** against Linux's
  [l1-load-extension-current-3.54.1.txt](../m4-plan/out/l1-load-extension-current-3.54.1.txt),
  line by line:
  - `DIR/ext, no suffix`: whether SQLite's retry adds `.dylib`. It should load here, and fail
    in `l1-so.txt`;
  - `ext.dylib, a bare name, cwd DIR`: Linux refused it, and macOS's dlopen(3) documents a search
    of the working directory. Q16 refuses a bare name before the call either way;
  - each failure's message, which slice 4's rows assert whole, and its code;
  - L6, whether the load waits on a FIFO, as it did on Linux;
  - L4 and L8, the init counts and the held row.
- **`l1-so.txt`:** whether a `.so` built by `-dynamiclib` loads on the Mac, so whether a suite
  needs a suffix of its own there.
- **`x1-*-dylib.txt`:** the load through Chez's FFI on Apple arm64, `__collect_safe`, with its
  message read and freed by `sqlite3_free`. `gate` and `gate-none` should end at
  `memory-used-after 0`, and `gate-leak` above it.
- **`compile.txt`:** whether `-dynamiclib` builds `ext.c` and `noentry.c` cleanly.
