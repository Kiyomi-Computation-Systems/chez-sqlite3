# What M2 slice 0's review measured

M2 slice 0's adversarial review (Opus, read-only) wrote these probes, through bare FFI, and they
were rerun on 2026-11-14 in the Guix container before any record used them. Two libraries were
used: Guix's 3.53.1 ([guix.txt](guix.txt)), and the floor, 3.45.1, built as
[research/m2-plan/](../m2-plan/) records ([floor.txt](floor.txt)). Run each from the repository
root. The probes that need a file write their scratch databases under the git-ignored
`build/review/`. In the Valgrind logs of the floor's runs, the checkout's absolute path is
shortened to `./`; nothing else in the logs is edited.

```
scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-review/probe5.sps'
```

The two outputs agree, apart from the version line, in all but three places, and each of the
three is named below: E and J, where 3.53.1 clamps a length limit, and probe 10's bytes read
after a free.

## What they show

1. **A reset or finalize can answer a new failure, and the data is lost** (probes 5 and 6). An
   autocommit `insert … returning` that is stepped once answers a row, but its commit runs at the
   reset or finalize. With a second connection holding a read, `sqlite3_reset` and
   `sqlite3_finalize` each answered 5 (BUSY), and the table kept 1 row instead of 3; with no
   reader they answered 0 and the insert stood. SQLite's documentation for `sqlite3_reset` warns
   of this case. After a finalize that answered 5 or 2067, no statement was left on the
   connection and `sqlite3_close` answered 0: finalize frees the statement whatever it answers.
2. **A reset or finalize can wait in the busy handler** (probe 4). With
   `pragma busy_timeout = 1500` and a reader, the reset and the finalize of the same `insert …
   returning` each took 1502 ms on both libraries before answering 5.
3. **`sqlite3_clear_bindings` while a row is ready answers `SQLITE_OK` and frees what the row
   still reads** (probes 8 to 10). After a bind, a step and a clear, a 200-byte BLOB read back
   `0 0 0 0` (probe 9), and a 5,000-byte BLOB read freed memory. Under Valgrind, probe 10 reports
   `Invalid read of size 1 … inside a block of size 5,008 free'd` on both libraries
   ([probe10-valgrind-guix.txt](probe10-valgrind-guix.txt),
   [probe10-valgrind-floor.txt](probe10-valgrind-floor.txt)). A 200-byte value sits in SQLite's
   lookaside, where Valgrind sees no free.
4. **A bind SQLite refuses leaves its parameter NULL** (probe 3, J). With `SQLITE_LIMIT_LENGTH`
   lowered, binding 100 bytes over a bound `'old'` answered 18 (TOOBIG), and the step read NULL,
   not `'old'`. 3.53.1 clamps the limit to at least 30 (`limit was, is` reads 30 after setting
   10); the floor keeps 10, so probe 2's E, at 29 bytes, is refused only there.
5. **Preparing a PRAGMA changes the connection, unstepped** (probe 7): `cache_size` from −2000 to
   7, `encoding` from UTF-8 to UTF-16le, and `case_sensitive_like` on.
6. **A tail of semicolons prepares to a NULL statement** (probe 2, A): `;`, `;;`, and the tail of
   `select 1;;`. `" ; select 2"` prepares `select 2`.
7. **An empty TEXT answers a NULL pointer through `sqlite3_column_blob`** (probe 2, B), with 0
   bytes; `'ab'` answers a pointer. After a step that answered a row, `sqlite3_errcode` is 100.
8. **Chez's `integer-64` wraps** (probe 2, C): 2⁶³ bound as −2⁶³ and 2⁶⁴−1 as −1, both answering
   `SQLITE_OK`. 2⁶⁴ and −2⁶³−1 raise Chez's own "invalid foreign-procedure argument".
9. **Every NaN is `eqv?` to `+nan.0`** (probe 2, D; probe 3, I), whatever its bits, and SQLite
   stores `(fl/ 0.0 0.0)` as NULL too.
10. **An error at the end of the SQL has no offset** (probe 2, F): `select (`, `select 1 +` and
    `select é,` answered −1; `selectx` answered 0.
11. **In a UTF-16 database, `sqlite3_column_text` converts** (probe 2, G; probe 3, H): a lone
    surrogate comes out as `ED A0 80`, and `D800` then `A` as `F0 90 81 81`, valid UTF-8 for
    another character. `sqlite3_column_blob` called first gives the stored UTF-16 bytes, `233 0`
    for `é`, and the UTF-8 bytes once `sqlite3_column_text` has converted them.
12. **A `with-exception-handler` handler of a raise inside `critical-section` runs with
    interrupts still disabled** (probe 3, L): the disable count read 2 there, against 1 outside. A
    `guard` clause runs after unwinding, so it isn't affected.
13. **A statement's column count changes when another connection changes the table** (probe 3,
    M; probe 4, N): 1 to 2 after a column was added, 2 to 1 after one was dropped, each read after
    the statement's next step.

## Round two: the review of the fixes

The review of slice 0's revised records wrote five more probes, rerun the same way on both
libraries before any record used them ([round2-guix.txt](round2-guix.txt),
[round2-floor.txt](round2-floor.txt)); they differ only in the version and timings of 1 ms.
`round2-cwd.sps` imports the project's libraries: run it with `--libdirs src`.

14. **A behaviour row must catch the collection while the call is still blocked**
    (`round2-plain.sps`). With `sqlite3_reset` bound plain, under a reader and
    `busy_timeout = 1500`, another thread's `collect-rendezvous` took 1402 ms and finished after
    the reset had returned. Bound `__collect_safe`, it took 0 ms, while the reset was still
    blocked. A plain binding blocks the collection only until the busy timeout ends, so a row that
    waits 12 s for the collection, as `test-native`'s FIFO row does, passes either way.
15. **Only a fresh connection's prepare blocks on a lock** (`round2-r1.sps`, R1): a connection
    whose busy timeout was set by pragma, preparing under another's `begin exclusive`, waited
    1502 ms and answered 5. One that had read the schema first answered 0 at once (R1b).
16. **After a reset answers a failure of its own, a second reset and the finalize answer 0** (R2).
17. **The tail scanner's edges** (R3), each prepared alone:
    - SQLite's whitespace is space, `\t`, `\n`, `\f` and `\r`. `\v`, U+0085 and U+00A0 each
      answered 1 (ERROR); `\f` answered 0 with a NULL statement.
    - `--` alone answered 0; `-` alone answered 1.
    - `/*` as the last two bytes answered 1. `/* ` and `/*x`, unterminated, answered 0 with a NULL
      statement.
18. **A refused statement's first statement has still been prepared** (R4):
    `pragma cache_size = 7; select 1` prepared with its tail at byte 22, and `cache_size` had gone
    from −2000 to 7.
19. **Two statements stepped once under a reader: only the last finalize commits**
    (`round2-two.sps`). Two `insert … returning` statements, each stepped once: the first finalize
    answered 0 and the second 5, under a reader; with no reader, both answered 0.
20. **A raise inside M1's critical sections reaches a `with-exception-handler` handler with
    interrupts disabled**
    (`round2-cwd.sps`): `call-with-open-handle` on a closed database, and `call-with-database`'s
    failed open, each gave the handler a disable count of 2 against 1 outside. `open-database`'s
    failed open, and a raise from `call-with-database`'s body, gave 1.
21. **Lookaside is why the 200-byte case is invisible to Valgrind**
    (`round2-p9-nolookaside.sps`). Probe 9 under Valgrind reports no error on either library
    ([probe9-valgrind-guix.txt](probe9-valgrind-guix.txt),
    [probe9-valgrind-floor.txt](probe9-valgrind-floor.txt)). The same case with lookaside turned
    off reports an invalid read inside a freed 208-byte block on both
    ([round2-p9-nolookaside-valgrind-guix.txt](round2-p9-nolookaside-valgrind-guix.txt),
    [round2-p9-nolookaside-valgrind-floor.txt](round2-p9-nolookaside-valgrind-floor.txt)).
22. **`sqlite3_column_name` answers NULL on a failed allocation without setting an error code.**
    At the floor, SQLite's `columnName` (`sqlite3.c` lines 91335 to 91341 of the 3.45.1
    amalgamation) clears its out-of-memory flag and returns NULL.

