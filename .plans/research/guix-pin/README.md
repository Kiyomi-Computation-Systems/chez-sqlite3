# Research: what chez-curl's Guix pin gives

Date: 2026-11-13 (M0 slice 1), on the development host. It settles ADR-0006's decision 2.

## Commands

Both run on the host, from a directory holding chez-curl's `channels.scm`
(`b532aa7d0bb345aafabf6b63cbfbda45abbec091`) and these scripts:

```
guix time-machine -C channels.scm -- shell chez-scheme sqlite gcc-toolchain valgrind coreutils bash sed --container -- sh measure.sh
guix time-machine -C channels.scm -- shell chez-scheme sqlite --container -- scheme -q --script features.ss
```

## Output

`measure.sh`:

```
scheme: 10.4.0
gcc: gcc (GCC) 16.2.0
valgrind: valgrind-3.27.0
sqlite3 cli: 3.53.1
lib -> /gnu/store/vi2anm0x47773lg48rh77dz9myhcbgmh-sqlite-3.53.1/lib/libsqlite3.so.0
/gnu/store/d6rzh2skgjh735j2igd1lvr8xr3rgwvi-profile/include/sqlite3.h
libversion 3.53.1 number 3053001 threadsafe 1 threaded? #t machine ta6le
compile options: ATOMIC_INTRINSICS=1 COMPILER=gcc-14.3.0 … ENABLE_COLUMN_METADATA ENABLE_DBSTAT_VTAB ENABLE_FTS3 ENABLE_FTS4 ENABLE_FTS5 ENABLE_MATH_FUNCTIONS ENABLE_PERCENTILE ENABLE_UNLOCK_NOTIFY … MUTEX_PTHREADS SECURE_DELETE SYSTEM_MALLOC TEMP_STORE=1 THREADSAFE=1
load_extension entry: #t
```

`features.ss`:

```
open 0 fts5-create 0 prepare 0 step 100 jsonb-type blob json_valid 1 finalize 0 close 0
```

## The command is not the library

The `sqlite3` command in the same store item links no `libsqlite3`; `ldd` lists none. It carries
its own copy of SQLite, compiled with options the library lacks. Run from the host's Guix home,
`pragma compile_options` lists `DQS=0`, `ENABLE_RTREE`, `ENABLE_STMTVTAB`,
`ENABLE_BYTECODE_VTAB`, `ENABLE_DBPAGE_VTAB` and others. The library reports none of them.

## Verdict

| Need | At the pin |
|---|---|
| Chez ≥ 10.4.0 | 10.4.0, threaded, `ta6le` |
| SQLite ≥ 3.45.1, with its header | 3.53.1, `sqlite3.h` in the profile |
| a C compiler | gcc 16.2.0 |
| Valgrind | 3.27.0 |
| FTS5 and JSONB through the library | both work |

The pin is kept.
