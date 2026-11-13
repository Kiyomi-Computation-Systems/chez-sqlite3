# Research: what chez-curl's Guix pin gives

Date: 2026-11-13 (M0 slice 1), on the development host. It settles ADR-0006's decision 2.

## Commands

All of these run on the host, from a directory holding chez-curl's `channels.scm`
(`b532aa7d0bb345aafabf6b63cbfbda45abbec091`) and the scripts beside this file.

```
guix time-machine -C channels.scm -- shell chez-scheme sqlite gcc-toolchain valgrind coreutils bash sed --container -- sh measure.sh
guix time-machine -C channels.scm -- shell chez-scheme sqlite --container -- scheme -q --script features.ss
```

Two more measurements ran inline, in containers with `sqlite`, `chez-scheme`, `gcc-toolchain`,
`coreutils`, `bash` and `grep`:

- `ldd "$(readlink -f "$GUIX_ENVIRONMENT/bin/sqlite3")"`, the command's links;
- `sqlite3 :memory: "pragma compile_options"`, the command's options, beside the library's own
  read through `sqlite3_compileoption_get` from Chez.

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
load_extension entry: #t
```

`features.ss`:

```
open 0 fts5-create 0 prepare 0 step 100 jsonb-type blob json_valid 1 finalize 0 close 0
```

The library's compile options, all 46, through the FFI:

```
ATOMIC_INTRINSICS=1 COMPILER=gcc-14.3.0 DEFAULT_AUTOVACUUM DEFAULT_CACHE_SIZE=-2000
DEFAULT_FILE_FORMAT=4 DEFAULT_JOURNAL_SIZE_LIMIT=-1 DEFAULT_MMAP_SIZE=0 DEFAULT_PAGE_SIZE=4096
DEFAULT_PCACHE_INITSZ=20 DEFAULT_RECURSIVE_TRIGGERS DEFAULT_SECTOR_SIZE=4096
DEFAULT_SYNCHRONOUS=2 DEFAULT_WAL_AUTOCHECKPOINT=1000 DEFAULT_WAL_SYNCHRONOUS=2
DEFAULT_WORKER_THREADS=0 DIRECT_OVERFLOW_READ ENABLE_COLUMN_METADATA ENABLE_DBSTAT_VTAB
ENABLE_FTS3 ENABLE_FTS4 ENABLE_FTS5 ENABLE_MATH_FUNCTIONS ENABLE_PERCENTILE
ENABLE_UNLOCK_NOTIFY MALLOC_SOFT_LIMIT=1024 MAX_ATTACHED=10 MAX_COLUMN=2000
MAX_COMPOUND_SELECT=500 MAX_DEFAULT_PAGE_SIZE=8192 MAX_EXPR_DEPTH=1000 MAX_FUNCTION_ARG=1000
MAX_LENGTH=1000000000 MAX_LIKE_PATTERN_LENGTH=50000 MAX_MMAP_SIZE=0x7fff0000
MAX_PAGE_COUNT=0xfffffffe MAX_PAGE_SIZE=65536 MAX_SQL_LENGTH=1000000000 MAX_TRIGGER_DEPTH=1000
MAX_VARIABLE_NUMBER=32766 MAX_VDBE_OP=250000000 MAX_WORKER_THREADS=8 MUTEX_PTHREADS
SECURE_DELETE SYSTEM_MALLOC TEMP_STORE=1 THREADSAFE=1
```

## The command is not the library

`ldd` on the command:

```
linux-vdso.so.1
libm.so.6 => /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/libm.so.6
libreadline.so.8 => /gnu/store/vpankxryi0sjfv5rggm38f71cqnwdczh-readline-8.2.13/lib/../lib/libreadline.so.8
libncursesw.so.6 => /gnu/store/63jzg3l26jcqydx5j2rizfwd85gp293h-ncurses-6.2.20210619/lib/../lib/libncursesw.so.6
libgcc_s.so.1 => /gnu/store/7iwcvd0gjrfq6bj7zvf3r59baw6vib5a-gcc-14.3.0-lib/lib/libgcc_s.so.1
libc.so.6 => /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/libc.so.6
/gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/ld-linux-x86-64.so.2
```

It links no `libsqlite3`, so it carries its own copy of SQLite. That copy reports 55 compile
options, which are the library's 46 plus nine more:

```
DQS=0 ENABLE_BYTECODE_VTAB ENABLE_DBPAGE_VTAB ENABLE_EXPLAIN_COMMENTS ENABLE_OFFSET_SQL_FUNC
ENABLE_RTREE ENABLE_STMTVTAB ENABLE_UNKNOWN_SQL_FUNCTION STRICT_SUBTYPE
```

This holds for Guix's build. A distribution may link its command to `libsqlite3.so.0` instead;
the host has no system `sqlite3` command to check.

## Verdict

| Need | At the pin |
|---|---|
| Chez ≥ 10.4.0 | 10.4.0, threaded, `ta6le` |
| SQLite ≥ 3.45.1, with its header | 3.53.1, `sqlite3.h` in the profile |
| a C compiler | gcc 16.2.0 |
| Valgrind | 3.27.0 |
| FTS5 and JSONB through the library | both work |

The pin is kept.
