# Research: Valgrind on Chez and libsqlite3, before the gate

Date: 2026-11-13 (M0 slice 3), in the pinned container (`b532aa7`). It is the first step of the
harness plan's slice 3: Valgrind on Chez, loading libsqlite3 and opening and closing databases
through bare FFI, with no suppression.

## Command

From the repository root, on the host:

```
scripts/guix-env sh -c 'make deps && sh .plans/research/memory-gate/measure.sh'
```

`measure.sh` runs `open-close.sps` without Valgrind, then under the gate's own command
(ADR-0005): `valgrind -v --command-line-only=yes --log-file=… --error-exitcode=9
--leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $CHEZ --libdirs
src:tests:build/scheme-libs --program …`. Then it runs each suite in `tests/` the same way.

`open-close.sps` binds `sqlite3_open_v2`, `sqlite3_prepare_v2`, `sqlite3_step`,
`sqlite3_finalize` and `sqlite3_close_v2` directly, and checks every return code:

- **plain:** a file database in WAL mode (create, insert, select), then `:memory:`, then an open
  that fails with `SQLITE_CANTOPEN` and still returns a handle, which it closes. Every
  out-parameter block is freed.
- **forget, hold, wrap:** one `:memory:` database, never closed. Its handle is kept as an
  integer and dropped (forget), as an integer in a top-level variable that is live at exit
  (hold), or in an ftype pointer that is dropped (wrap). Each runs a full collection before it
  exits.

## Output

```
valgrind: valgrind-3.27.0
chez: /gnu/store/5v2iykmw4z9r6wvq5kqbh2yx1zz1ncan-profile/bin/scheme -> /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme
lib: /gnu/store/5v2iykmw4z9r6wvq5kqbh2yx1zz1ncan-profile/lib/libsqlite3.so.0 -> /gnu/store/vi2anm0x47773lg48rh77dz9myhcbgmh-sqlite-3.53.1/lib/libsqlite3.so.3.53.1
```

| Case | Plain run | Under the gate | Definitely lost | Indirectly lost | Still reachable |
|---|---|---|---|---|---|
| plain | exit 0, every code as expected | exit 0, 3 s | 0 | 0 | 1,752 bytes in 5 blocks |
| forget | exit 0 | exit 9, 3 s | 840 bytes in 1 block | 75,168 bytes in 122 blocks | 1,752 bytes in 5 blocks |
| hold | exit 0 | exit 9, 3 s | 840 bytes in 1 block | 75,168 bytes in 122 blocks | 1,752 bytes in 5 blocks |
| wrap | exit 0 | exit 0, 3 s | 0 | 0 | 64,904 bytes in 125 blocks |

Every run, under the gate:

```
ERROR SUMMARY: … (suppressed: 0 from 0)
suppressions: /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libexec/valgrind/default.supp
first syms: /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme
```

The suites, under the gate:

| Suite | Passes | Exit | Time | Definitely lost |
|---|---|---|---|---|
| `test-check-floors` | 164 | 0 | 8 s | 0 |
| `test-chez-sqlite3-testing` | 60 | 0 | 11 s | 0 |
| `test-counters` | 14 | 0 | 7 s | 0 |
| `test-manifest` | 79 | 0 | 7 s | 0 |
| `test-require-threaded` | 50 | 0 | 8 s | 0 |

## What it settles

- **No suppression.** Loading libsqlite3, a WAL file database, `:memory:` and a failed open lose
  nothing, and Valgrind suppressed nothing, not even from its own `default.supp`. chez-curl's
  one suppression was for a block p11-kit's constructor loses under Guix's glibc; libsqlite3
  loads no p11-kit. So the gate passes no suppression file (ADR-0005, decision 2), and the
  harness plan's "sabotage group c", which held chez-curl's file to its one entry, has nothing
  to hold.
- **Valgrind sees a forgotten handle only when Chez holds it as an integer.** A handle kept as
  an integer is definitely lost, even while a live variable holds it: a fixnum holds an address
  shifted, so Valgrind finds no pointer to the block. In an ftype pointer, the same handle is
  still reachable and the run passes. chez-curl measured the same for a foreign block in an
  ftype pointer (chez-curl ADR-0014, amended 2026-10-16). So whether the gate's Valgrind half
  sees a connection left open depends on how M1 holds handles; the counters see it either way.
- **The gate is fast enough for every run.** The five suites take 7 to 11 s each under it, about
  43 s through `make test-memory`.
