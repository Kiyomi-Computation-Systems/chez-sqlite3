# M4's pre-work on the Mac

ADR-0001 says a `db_config` binding without `__varargs_after` fails only on Apple arm64, which
has no CI. These steps run both probes on Apple's `/usr/lib/libsqlite3.dylib` and on Homebrew's
SQLite, so we can read what each binding does there. On Linux both bindings agree
([README.md](README.md)).

Everything below is for zsh, in your chez-sqlite3 clone. The commands carry no comments. They
write only under `build/m4pre-mac/`, which git ignores.

## 1. Fetch the probes

Start from a clean tree: `git status --short` should print nothing.

```
git status --short
git fetch origin
git switch --detach origin/m4-prework
```

## 2. Name things

```
CHEZ=$(command -v chez || command -v scheme)
P=.plans/research/m4-prework
O=build/m4pre-mac
APPLE=/usr/lib/libsqlite3.dylib
BREW=$(brew --prefix sqlite)/lib/libsqlite3.dylib
mkdir -p $O
echo $CHEZ $BREW
```

The `echo` should print a Chez path and a dylib path. If `CHEZ` is empty, set it to your Chez
binary by hand.

## 3. Record the machine

```
{ sw_vers; uname -m; echo $CHEZ; "$CHEZ" --version; git rev-parse HEAD; shasum -a 256 $P/varargs.sps $P/census.sps $P/varargs.c $P/constants.c; ls -l $BREW; } > $O/system.txt 2>&1
```

## 4. Run the probes

Each run is its own process. The `plain` runs pass C whatever is on the stack, so they may print
nonsense or crash. A crash is a result: keep the file as it is.

```
"$CHEZ" --program $P/census.sps $APPLE > $O/census-apple.txt 2>&1; echo "(exit $?)" >> $O/census-apple.txt
"$CHEZ" --program $P/varargs.sps $APPLE varargs > $O/varargs-apple.txt 2>&1; echo "(exit $?)" >> $O/varargs-apple.txt
"$CHEZ" --program $P/varargs.sps $APPLE plain > $O/plain-apple.txt 2>&1; echo "(exit $?)" >> $O/plain-apple.txt
"$CHEZ" --program $P/census.sps $BREW > $O/census-brew.txt 2>&1; echo "(exit $?)" >> $O/census-brew.txt
"$CHEZ" --program $P/varargs.sps $BREW varargs > $O/varargs-brew.txt 2>&1; echo "(exit $?)" >> $O/varargs-brew.txt
"$CHEZ" --program $P/varargs.sps $BREW plain > $O/plain-brew.txt 2>&1; echo "(exit $?)" >> $O/plain-brew.txt
```

## 5. The C oracle, if you have `cc`

Skip this if `cc --version` fails (no Xcode Command Line Tools). The oracle makes the same calls
in C, where the compiler knows the call is variadic. The Apple build uses the SDK's `sqlite3.h`.

```
cc -Wall -I$(brew --prefix sqlite)/include -o $O/oracle-brew $P/varargs.c $BREW
$O/oracle-brew > $O/oracle-brew.txt 2>&1; echo "(exit $?)" >> $O/oracle-brew.txt
cc -Wall -o $O/oracle-apple $P/varargs.c -lsqlite3
$O/oracle-apple > $O/oracle-apple.txt 2>&1; echo "(exit $?)" >> $O/oracle-apple.txt
cc -Wall -I$(brew --prefix sqlite)/include -o $O/constants-brew $P/constants.c
$O/constants-brew < $O/varargs-brew.txt > $O/constants-brew.txt 2>&1; echo "(exit $?)" >> $O/constants-brew.txt
```

## 6. Send back, then go back

```
tar czf m4pre-mac.tgz $O/*.txt
git switch -
```

Send `m4pre-mac.tgz`. It holds every `.txt` file in `build/m4pre-mac/`: `system.txt`, the three
runs for each library, and the oracle's files if you ran step 5.

## What we will read

- **`varargs-*.txt`:** whether each `(varargs verdict …)` line says `ok`, and every return code.
  On Apple's, M1 saw `ENABLE_LOAD_EXTENSION` answer 21 (`SQLITE_MISUSE`). This run shows whether
  `DEFENSIVE` and the DQS ops answer 0 there.
- **`plain-*.txt`:** what the plain binding does on Apple arm64: wrong values, `untouched` cells,
  a crash (`(exit 139)` or similar), or nothing wrong at all.
- **`oracle-*.txt`:** the oracle's `(c …)` lines, compared with the probe's `(varargs …)` lines.
- **`census-*.txt`:** each library's options, FTS5, JSON, DQS, and each op's starting value.
