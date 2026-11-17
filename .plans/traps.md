# Traps: the full accounts

AGENTS.md carries the one-line rule of each trap that binds every task, and this file keeps the
incident behind every trap, those too. Each account
names the repository it happened in. The traps the family hit before this repository existed are
told in chez-curl's `.plans/traps.md`.

## Chez and the FFI

- **Chez fixes no order for a call's arguments, and a probe follows the same rules as a test.**
  M0 slice 0's value probe called
  `(printf "…" (bind-double st 1 1.5) (step st) (col-type st 0))` in a `--script` program.
  `bind` returned `SQLITE_MISUSE` because `step` had already run. The control case exposed it:
  binding 1.5 can't fail, yet it failed exactly as NaN did. Rewritten with `let*`, the probe
  bound 1.5 cleanly and showed that NaN stores NULL.

  Measuring why showed that the rule AGENTS.md inherited was wrong on this Chez in both halves.
  Compiled code ran the arguments left to right, and `interpret` right to left. A probe like
  this one goes neither way: `--script` and `load` hand each simple top-level form to the
  interpreter (`compile-interpret-simple`), and that path ran them `cab` or `bca`. The first
  account blamed compiled code for those orders; M0 slice 1's review found the parameter, and
  turning it off gave `abc` at every site. The probe and its outputs are in
  [research/evaluation-order/](research/evaluation-order/). (chez-sqlite3)

- **Chez's `utf8->string` drops one leading U+FEFF.** On 10.4.0,
  `(utf8->string #vu8(#xef #xbb #xbf #x69 #x64))` is `"id"`, and a UTF-8 transcoder decodes it
  the same way. Of two leading U+FEFF only the first goes, and one that isn't leading stays. M2
  slice 1's strict decoder answered `utf8->string`'s string once the bytes were well-formed, so a
  TEXT value starting with U+FEFF read back changed, which D6 exists to prevent. Its round trips
  sampled every 257th scalar value and skipped U+FEFF; the Opus review found it. The brief had
  called `utf8->string` exact, and the builder inherited that. The decoder now restores the
  U+FEFF, and a row round-trips every scalar value alone (ADR-0015, amended). M1's
  `c-string->string` read the same way. M2 slice 1 held that it decoded only SQLite's own text, and
  M2 slice 3 found otherwise: an error message can be the user's, and a trigger's
  `RAISE(ABORT, '\xFEFF;boom')` reached the raised condition as `"boom"`. `c-string->string` now
  keeps a leading U+FEFF too. Column values and names go through `strict-utf8->string`. (M2 slices
  1 and 3, chez-sqlite3)

- **An R6RS `\x` escape ends at its own semicolon.** `"a;\xFEFF;b"` holds four characters, `a`,
  `;`, U+FEFF and `b`, and `"\xFEFF "` is a reader error. So `"select 1;\xFEFF;"` has one
  semicolon, not two. M2 slice 3's tail suite hit it in its first draft. (M2 slice 3,
  chez-sqlite3)

- **Chez's `make-time` refuses a nanosecond field of 10⁹:** "invalid nanosecond 1000000000".
  Carry whole seconds into the seconds field. (M2 slice 3, chez-sqlite3)

- **Chez turns a read of address 0 into a condition,** "invalid memory reference", not a crash.
  So a planted read of NULL fails its row by name, and the suite goes on. (M2 slice 4,
  chez-sqlite3)

- **A condition type's name is syntax, not a record type.** `(record-type-parent &sqlite-busy)`
  is "invalid syntax" when it expands, so a row written so kills its suite before any test runs.
  `(record-type-descriptor &sqlite-busy)` gives the record type. (M2 slice 1, chez-sqlite3)

- **Chez shares its empty bytevector.** `(eq? (make-bytevector 0) (bytevector-copy #vu8()))` is
  `#t`, so no row can tell a fresh empty result from a shared one. Assert an empty bytevector by
  its contents only. (M2 slice 1, chez-sqlite3)

- **Chez's `int` isn't C's, and `uptr` takes −1.** `int` takes −2³¹ to 2³²−1, and hands 2³¹ and
  above to C as negative numbers: `abs` bound `(int) int` answered −2147483648 for 2147483648.
  Beyond that it raises from the binding, inside whatever critical section made the call.
  `uptr` takes −1 as all ones, the same as 2⁶⁴−1. So M2 slice 2's brief was wrong to say an `int`
  binding of `sqlite3_bind_int64` gives a wrong value at the boundaries: at three it raises, and
  2³¹ reaches a 64-bit callee unchanged. And `SQLITE_TRANSIENT` written as −1 would bind
  correctly, seen only by a row holding it to the header. Every value a verb passes is checked to
  fit its C type before the section (ADR-0011, amended). (M2 slice 2's review, chez-sqlite3)

- **A guard whose clauses don't match re-enters the raise's extent.** It raises again in the
  raise's own dynamic environment, so a `dynamic-wind` before thunk runs a second time, and one
  that refuses a re-entry replaces the caller's condition: the outer guard caught `re-entered`,
  and `call-with-c-string` gave its refusal. M2's `call-with-statement` and `call-with-database`,
  whose before thunks do nothing, gave the caller's condition (the plan's review, on Chez
  10.4.0). (M3's plan, chez-sqlite3)

- **An engine's expiry inside `with-mutex` lets the mutex go, and a check in one section can be
  undone before the act in the next.** On Chez 10.4.0 an expiry runs `dynamic-wind`'s after
  thunks, `with-mutex`'s release among them, and the resume runs the before thunks again: a probe
  found the mutex free from another thread while the engine was suspended. So `with-mutex` alone
  doesn't keep a flag's check and the call it guards together, and M3 slice 1's interrupt latch
  holds both inside one `critical-section` as well. The same split undid a plan: modelled over
  slice 1's transaction plan, an expiry between `with-transaction`'s autocommit read and its
  `COMMIT`'s step ran the after thunk's rollback, and the resumed body stepped the `COMMIT` it had
  planned. At a nested level, with another engine's savepoint at the same depth, the resumed
  `RELEASE` released that one, and the call answered as committed. The window was at fuels 138
  to 174, past the plan's sweep of 1 to 60. A flag that guards a step is read in that step's
  section, and an engine row sweeps fuel until the call completes without expiring (ADR-0017,
  amended; [research/m3-slice-1/](research/m3-slice-1/README.md)). (M3 slice 1 and its review,
  chez-sqlite3)

- **An engine's remainder runs twice when resumed twice, and the caller's handlers run between
  any two sections.** On Chez 10.4.0 an engine that expired after 9 of 2000 counts completed at
  2000 when its remainder was resumed, and at 3991 when the same remainder was resumed again
  ([research/m3-slice-3/](research/m3-slice-3/README.md), `engine-twice.sps`). A timer's,
  keyboard's or collect request's handler is the caller's code, and can capture a continuation
  wherever interrupts are on. M3 slice 3's review turned both into a statement handed out twice:
  a second resume of `query`'s remainder stepped and refiled a statement another engine had
  checked out since, and a finished `query-fold`, re-entered from its timer handler's
  continuations, left 31 statements tracked and in no cache. A flag guarding a call is read in
  every section that touches its resource (ADR-0016, amended in M3 slice 3). Two more for a row:
  a continuation taken before the call's first expression makes a whole new call, with a flag of
  its own; and one taken inside the caller's procedure finishes that call of the procedure when
  re-entered, so a counter at the procedure's entry counts it twice. (M3 slice 3's review and
  fixes, chez-sqlite3)

- **A remainder resumed again while an earlier resume of it is pending gets past a flag set
  once a call ends.** M3 slice 5's review took `open-database`'s remainder R before the open, at
  fuel 199, and resumed it at fuel 38 until it expired after the open, as R1. R resumed again to
  its end opened a second connection and returned it; R1 was then refused. Its connection stayed
  open, counted and unreachable. Past the open, the same schedule applied the settings twice.
  The briefs had modelled "resumed twice" only as one resume run to its end before the next.
  A claim each section compares with a position the run carries, and advances, holds
  (ADR-0018, amended in M3 slice 5). The M2 session's sweep of slice 4 then found the same in
  slice 3's `execute!`, `query` and `query-row`: R1 held a statement that R found out of the
  cache and prepared again, and two runs past the check-out shared one, `query` answering rows
  the other had stepped past (ADR-0016, amended in M3 slice 5's part D). (M3 slice 5's review,
  fixes and part D, chez-sqlite3)

- **Chez's `number->string`, resumed from inside, answers wrong.** On Chez 10.4.0,
  `(string-append "PRAGMA busy_timeout = " (number->string 1234))` under an engine, its
  remainder resumed to its end a second time, answered `"PRAGMA busy_timeout = "` at fuels 22,
  23, 31 and 32. Resumed while an earlier resume was pending, it answered the digits twice,
  `"12341234"`, or none ([research/m3-slice-5/](research/m3-slice-5/README.md),
  `number-twice.sps`, `number-interleaved.sps`). `string-append` alone never differed. Build
  such text in a critical section. (M3 slice 5 and its fixes, chez-sqlite3)

- **A collect request costs an engine's run ticks.** An engine of 300 allocating calls first
  completed unexpired at fuel 5238 with no collection pending, and at 5253 with one every 4 KiB,
  whatever the collect-request handler did, nothing included (`gc-ticks.sps`). So two runs of
  one call at one fuel can stop ticks apart. (M3 slice 5's fixes, chez-sqlite3)

- **An engine's fuel names no fixed point in the code.** Stepped one tick a slice,
  `execute-script!` completed in 123 slices, yet a remainder taken at fuel 1 and resumed at fuel
  127 had not begun the script: 432 of 527 sampled trials (F, G) stood elsewhere than the stepped
  run after F + G ticks ([research/m3-slice-5/](research/m3-slice-5/README.md), `ticks.sps`).
  Where a remainder lies depends on the code after it too: one first expression, followed by
  different code, put the last fuel whose remainder made a whole new call at 6 or at 7, and
  `execute!`'s is at 8 (`boundary.sps`). So sweep every (F, G), and bound a whole new call by the
  fuel at which the same call, refused at its first check, completes. (M3 slice 5's part D,
  chez-sqlite3)

- **A keyboard interrupt that comes pending inside a critical section is handled as the section
  ends,** before the next expression. A timer and an engine spend no ticks inside one: a timer
  of 10 had 9 left after 1000 calls in a section, and an engine of fuel 10 around such a
  section completed with 3 left (`section-end.sps`, Linux only). So the code just after a
  section is reached by a signal alone. (M3 slice 5's fixes, chez-sqlite3)

- **Exporting a new name from a library can break one that imports it whole.** Chez refuses the
  importer when it defines the name too: "multiple definitions for open-outcome in body". M3
  slice 5 exported `open-outcome` from `(chez-sqlite3 private connection)`, which
  `(chez-sqlite3 private statement)` imports whole and defines its own of, so the export became
  `connection-outcome`. (M3 slice 5, chez-sqlite3)

- **An unquoted vector literal is invalid syntax under `#!r6rs`.** Chez refused `(display #(1))`
  as "invalid syntax #(1)" at expansion, so the whole program failed before its first line ran;
  `'#(1)` read. Quote every vector literal in a suite or a probe. (M3 slice 6, chez-sqlite3)

- **Chez's `map` called its procedure from the end, in pairs.** On 10.4.0,
  `(map (lambda (i) (set! seen (cons i seen)) i) '(0 1 2 3 4 5))` in a program called it on 4,
  5, 2, 3, 0, 1, so over 0 to 31 the first call was on 30. A cache row that filled its table
  through `map` evicted `select 30` instead of `select 0`. AGENTS.md's rule already forbade the
  assumption; this is the order it measured. (M3 slice 1, chez-sqlite3)

- **An engine whose expiry runs an after thunk that raises is lost.** In M3 slice 4's sweeps,
  where an engine expired inside `with-transaction` and the rollback its after thunk issued
  failed, the engine's caller got an assertion violation from `raise`, "no engine active", and
  no remainder to resume. The statements that call had checked out and not yet given back stayed
  tracked, one of them `failed`, until `with-transaction` took, stepped and gave back each of its
  statements in one critical section. (M3 slice 4, chez-sqlite3)

- **Unlocking an object that isn't locked can unpin another.** In Chez 10.4.0, `Sunlock_object`
  (`c/gcwrapper.c`) decrements the segment's `must_mark` count whether or not the object was
  locked, and a locked object outside the new space stays put only through that count. So an
  extra `unlock-object` can let the collector move another locked object in the same segment.
  - The first build of PR #30's gate unlocked a refused registration's callbacks, and its
    builder's probe saw only that nothing raised.
  - The review read the source. No move was shown: in the probe's setup even an unlocked
    callable didn't move.
  - Unlock exactly what was locked, once. (M3's Mac run, PR #30's review, chez-sqlite3)

- **A jump back within one wind's extent crosses no winder.** A `dynamic-wind` before thunk runs
  only on a jump in from outside its extent. `execute-script!` relied on `call-with-block`'s before
  thunk to refuse a re-entry, and read its flag at the first prepare alone. A timer's handler that
  captured a continuation between two statements, and called it from a later fire of the same
  call, jumped back inside the block: the statements after it ran again, and the call returned
  normally, in 629 of 2804 trials of reviewer A's `script-reenter3.sps`. The fix claims each
  statement's byte offset inside its prepare's section. (M3's closing review, chez-sqlite3)
- **A sweep's bound on a whole new call can bound nothing.** Three ways it failed in M3:
  - **A refused call's fuel:** `with-transaction` refused at its first check completed at fuel
    65, and the whole call at 72, so a bound read from the refusal says nothing of where the call
    begins.
  - **A control run on the code under test** moves with the mutant: under reviewer B's N1, a
    claim of 0 taken again after the end, the pending sweeps' last whole new call went from fuel
    8 to 15, and all 73 suites passed.
  - **A caller's own count:** each procedure entry between the count and the callee's first
    expression costs a tick. In the transaction suite the count first lands at fuel 7, and whole
    new calls run through fuel 8 (`transaction/claim-window/window.sps`).

  A sweep now bounds it by a refusal it sees itself, of a remainder taken before the call's first
  section. (M3's closing review, chez-sqlite3)
- **A flag the first run sets can hide a misplaced check from every engine sweep.** Two mutants
  that took `with-transaction`'s claim just before the BEGIN's section, or in a section of its own,
  passed every engine row: under any schedule the second run met the shared `ended`, set by the
  first run's end or by its expiry's rollback. Only a timer's continuation called from inside the
  body told them apart. (M3's closing review, chez-sqlite3)
- **One connection across an engine row's fuels sweeps whatever path the last fuel left.**
  `test-conveniences-engines` reused a connection for every fuel, so after the first trial each
  ran warm, from the cache. A mutant whose cache hit handed its statement over after its section
  passed it; with a fresh connection per fuel, run cold then warm, it fails. (M3's closing review,
  chez-sqlite3)
- **A count of expiries can't tell one section per value from one section for all.** A row held
  that binding takes a section per value by counting expiries: "at least 49" for 50 values.
  Binding outside any per-value section cost 249 more, and passed it (reviewer B's
  `q15-binds.sps`). Rows now read what each section did: `sqlite3_expanded_sql` sees every bound
  count, from 0 to 50. (M3's closing review, chez-sqlite3)
- **A suite's own text moves its fuels.** Adding rows to `test-conveniences-engines`, with the
  library unchanged, moved P6's fuels from 43, 82 and 47 to 41, 80 and 45. A row may not assert a
  fuel as a constant, nor that two verbs' fuels are equal. (M3's closing review, chez-sqlite3)
- **A `list` of effectful checks is an order of effects too.** `test-statement-cache`'s
  near-spellings row checked out seven keys as the arguments of one `list`. Under `--program` they
  ran left to right, so the exact keys left the table before any near spelling was tried, and a
  cache that compared keys by their first 4096 characters passed all 73 suites. Its verdict also
  flipped between compiled code and `interpret`. Now `let*` (`suites/cache-order.sps`).
  (M3's closing review, chez-sqlite3)

## SQLite

- **The `sqlite3` command can carry its own SQLite; Guix's does.** The brief's first evidence read
  `pragma compile_options` from the Guix home's `sqlite3` command, and recorded its `DQS=0` as the
  library's. A test rule in the brief, §7, was built on it. The command links no `libsqlite3`. In
  M0 slice 1, the library beside it, read through the FFI, reported no `DQS`, `RTREE` or
  `STMTVTAB` option ([research/guix-pin/](research/guix-pin/)). (chez-sqlite3)

- **SQLite's whitespace run continues on `\v`, and U+FEFF is whitespace wherever it stands.** A
  run starts on space, `\t`, `\n`, `\f` or `\r`, then runs on any of those or `\v`
  (`sqlite3Isspace`); `\v` can't start one. `EF BB BF` is a whitespace token of its own
  (`CC_BOM`). ADR-0014's tail scan, as accepted, held neither, and disagreed with SQLite's prepare
  on 56,425 inputs of 2 to 6 bytes. M2 slice 1 found it by preparing every short SQL on 3.53.1 and
  the floor, before any code was built on the model; the maintainer chose to match SQLite
  (ADR-0014, amended; [research/m2-slice-1/](research/m2-slice-1/)). (M2 slice 1, chez-sqlite3)

- **A REAL's text differs by version.** `cast(4.9406564584124654e-324 as text)` is that on 3.53.1,
  and `4.94065645841247e-324` on 3.45.1. So a row that reads a REAL as text writes no expected
  value, and compares two readings of the same library instead. (M2 slice 2, chez-sqlite3)

- **An interrupt doesn't end a wait in the busy handler.** `begin immediate` under another
  connection's exclusive lock, with a 600 ms busy timeout and `sqlite3_interrupt` at 100 ms, waited
  601 ms and answered BUSY, its interrupt flag left set. A long computation, interrupted the same
  way, stopped at 100 ms with 9. So a row that blocks a call can't end the wait early; only the
  timeout does. The M1 session found it in M3's research, and M2 slice 3 reproduced it
  ([research/m2-slice-3/](research/m2-slice-3/)). (M2 slice 3, chez-sqlite3)

- **A NULL pointer reads the connection's last code, which can be another statement's.** An empty
  BLOB answers a NULL pointer and sets no code. So after another statement's NOMEM, a read or a
  bind, `sqlite3_extended_errcode` answers 7 for a healthy statement's empty BLOB, and slice 4's
  reader raised `nomem` and failed the statement. A real NOMEM turns its column's type to NULL, so
  the reader now reads the type too. Slice 4's review found it. (M2 slice 4, chez-sqlite3)

- **A read past a stale column count answers NULL, not an error.** After another connection's
  `alter table … drop column` and a step, `sqlite3_column_type` of the dropped index answers 5.
  So only a count read with the read refuses it. (M2 slice 4, chez-sqlite3)

- **In a UTF-16 database, `sqlite3_column_text` on a BLOB converts it as UTF-16 text and turns its
  type to TEXT:** `x'4100'` reads `41`. So the type is read first, and a BLOB through
  `sqlite3_column_blob`. (M2 slice 4, chez-sqlite3)

- **After a NOMEM column read, the column reads as NULL,** type 5, and the 7 stays on the statement
  until a reset. So a retried read gives `sql-null`, which is why a NOMEM read moves the
  statement to `failed` (ADR-0014, amended). (The M1 session's research for M2 slice 4,
  chez-sqlite3)

- **`SQLITE_LIMIT_LENGTH` limits column names at prepare,** not only bound values. At a limit of
  30, a 31-byte alias fails prepare with `SQLITE_TOOBIG`; at the floor's smallest, 1, even
  `select ?1` does. So a refused-bind row prepares before it lowers the limit. (The M1 session's
  research for M2 slice 4, chez-sqlite3)

- **`sqlite3_error_offset` can be stale.** After a refused bind, it still answers an earlier
  failed prepare's offset; a clean bind clears it. And on 3.53.1, `select ?0` gives −1 on a
  connection's first prepare and 7 after it. So an offset is read only straight after the prepare
  that failed. (The M1 session's research for M2 slice 4, chez-sqlite3)

- **A PRAGMA's default is a build option.** Apple's 3.51.0 starts `cache_size` at 2000 pages,
  and Guix's and the CI builds at −2000 KiB (`DEFAULT_CACHE_SIZE`). A row that read the default as
  its base passed on Linux and failed on the Mac. A row sets its own base first. (M2's Mac run,
  chez-sqlite3)

- **Some BUSY no wait fixes.** COMMIT answers `SQLITE_BUSY`, "cannot commit transaction - SQL
  statements in progress", while the connection's own write is unfinished, such as an
  `insert … returning` that has answered a row. A SELECT mid-row doesn't stop it. So
  `sqlite-busy?` isn't always "retry later": reset or finalize the write first. Slice 3's first
  wording, "mid-row", overstated it. (M3's research, reproduced in M2 slices 3 and 4,
  chez-sqlite3)

- **A statement's column count changes at its next step, after an `ALTER TABLE` on its own
  connection too,** not only another's: a held `select *` read 2, then 2 after the ALTER, then 3
  after its step. So a count read before a step can be stale, and a column read checks the count
  in its own section. (M3's research, reproduced in M2 slice 3, chez-sqlite3)

- **An interrupt sticks while any statement of its connection holds a row.** Every new prepare and
  step then answers `SQLITE_INTERRUPT` until that statement is reset: `ROLLBACK`, `COMMIT`,
  `ROLLBACK TO` and `RELEASE` among them, so the transaction can't be ended. With none active, the
  next statement's start discards it, so one that lands between two statements is lost
  (concurrency I2, I3, trap 2; slice-0 P7). (M3's research, chez-sqlite3)

- **A busy timeout doesn't cover a read transaction's first write.** After `BEGIN` and a read, a
  write under another connection's write lock answered BUSY at once, with no timeout and with 1500
  and 2000 ms ones, and in WAL `SQLITE_BUSY_SNAPSHOT` (517) once the other had committed. No retry
  of the statement can succeed. `BEGIN IMMEDIATE` waits under the timeout instead, while the
  connection holds no read of its own (concurrency B2, B5, B6, trap 4; slice-0 P12).
  (M3's research, chez-sqlite3)

- **`BEGIN IMMEDIATE` doesn't wait while the connection's own SELECT holds an old snapshot.** In
  WAL, with a SELECT held at a row and another connection's commit after it, `BEGIN IMMEDIATE` and
  `BEGIN EXCLUSIVE` answered 517 at once, with a 300 ms timeout, and began nothing. Reset the
  SELECT first (slice-0 P9). (M3's research, chez-sqlite3)

- **Some settings fail at once, with a busy timeout set.** `journal_mode = wal` under another
  connection's reserved lock, and `journal_mode = delete` on a WAL file beside another connection
  that has read it, even one idle now, answered BUSY with no wait under a 200 ms timeout (slice-0
  P2). A connection opened and never used holds nothing of the file, and doesn't block leaving
  WAL ([research/m3-slice-5/](research/m3-slice-5/README.md), `locks.sps`). (M3's research and M3
  slice 5, chez-sqlite3)

- **SQLite's unix VFS keeps a closed connection's file descriptor while another connection in
  the process holds a POSIX lock on the file.** A failed open under another's exclusive lock left
  one descriptor more, which a later open reused (`busy-probe.sps`). Read a file's descriptors
  only once every holder has let go. (M3 slice 5, chez-sqlite3)

- **`sqlite3_cancel_auto_extension` keeps SQLite's list of entry points;
  `sqlite3_reset_auto_extension` frees it.** A suite that registered one and cancelled it failed
  its `sqlite3_memory_used` check by 8 bytes, which Valgrind didn't report. (M3 slice 5's fixes,
  chez-sqlite3)

- **A refused `BEGIN IMMEDIATE` still takes its lock.** Inside a deferred transaction that had read
  nothing, it failed, "cannot start a transaction within a transaction", and `txn_state` went from
  NONE to WRITE (single T1). (M3's research, chez-sqlite3)

- **Whether a failure ended its transaction turns on the statement, not the code.** The same NOMEM
  or FULL undid only its statement, or rolled back the transaction, by one function call, one
  constraint, one row, or whether a table was read. A limit left in force across the statement's
  own rollback turned one into the other. An interrupted write always ends it, and an interrupted
  SELECT never does (single T8, T12, T13; concurrency I5). (M3's research, chez-sqlite3)

- **A PRAGMA never refuses a value or a name.** A word it doesn't know turns a boolean off,
  `synchronous = 4` is stored, `busy_timeout = 2147483648` gives 0, and `PRAGMA foreign_key = ON`
  does nothing. Inside a transaction, `foreign_keys = ON` does nothing and says nothing (single P4,
  P5, T4, T5; concurrency B1). (M3's research, chez-sqlite3)

- **A connection's `journal_mode` can be stale.** One that had read the file before another
  switched it to WAL answered `delete` until its next read (concurrency trap 5). (M3's research,
  chez-sqlite3)

- **`last_insert_rowid` can name a row that doesn't exist:** one a failed statement or a ROLLBACK
  undid. It doesn't move for a WITHOUT ROWID table or an upsert's DO UPDATE (single T7, C8, C11).
  (M3's research, chez-sqlite3)

- **After `ROLLBACK`, an open SELECT goes on answering rows,** the rolled-back ones among them,
  unless the rollback undid a schema change, when it answers 516 (single O2, O4b, T2). (M3's
  research, chez-sqlite3)

- **A busy wait's grain is the build's.** Without `nanosleep`, SQLite sleeps whole seconds: a
  timeout under 1000 ms answers BUSY at once, and 1500 waits 1000. No compile option shows it
  (concurrency B3). (M3's research, chez-sqlite3)

- **A connection's own held read stops its writes from waiting.** With its SELECT held at a row,
  under another's `BEGIN IMMEDIATE` and write, its `BEGIN IMMEDIATE` and an autocommit INSERT
  answered BUSY in microseconds, where without the held read they waited out a 1500 ms timeout,
  in WAL and rollback-journal mode alike. With `BEGIN IMMEDIATE` taken before the read, writes
  beside it ran (slice-0 P12; the plan's review found it). (M3's research, chez-sqlite3)

- **Any set of `foreign_keys` or `trusted_schema` expires every statement on its connection,**
  even one that changes nothing: `foreign_keys = 1`, `= 0` and `= off`, and `trusted_schema = 0`
  and `= 1`, each made a held statement re-prepare at its next step. No read form of the six
  settings did, nor a set of the other four (slice-0 P13, P13b). (M3's research, chez-sqlite3)

- **SQLite's list of PRAGMAs and its documentation's differ.** The floor's `aPragmaName`, in
  3.45.1's amalgamation, holds 78 names, and sqlite.org/pragma.html, read 2026-11-15, lists 74:
  the table adds `activate_extensions`, `lock_proxy_file`, `lock_status`, `sql_trace` and
  `vdbe_eqp`, and the page adds `legacy_file_format`. A complement taken from one of them misses
  names in the other; M3 slice 1's settings suite refuses their union. (M3 slice 1, chez-sqlite3)

- **Lifting only the hard heap limit leaves SQLite under memory pressure for the rest of the
  process.** `sqlite3_hard_heap_limit64(H)` sets the soft threshold to H too, and an allocation
  near it sets `mem0.nearlyFull`. `sqlite3_hard_heap_limit64(0)` zeroes the threshold but never
  clears the flag. Only an allocation made while a threshold is set, or
  `sqlite3_soft_heap_limit64`, clears it (`malloc.c`, read in 3.45.1's amalgamation).
  - **Measured on 3.53.1 and 3.45.1:** after a NOMEM and the hard lift alone, a writer in
    `BEGIN IMMEDIATE` that read a table made a second connection's read answer BUSY.
    `sqlite3_soft_heap_limit64(0)` after the hard lift cleared it.
  - **Both limits read 0 after the hard lift alone,** so reading them back can't show it: only
    the second connection's read does.
  - **Lift hard, then soft.** (M3 slice 4's groundwork, chez-sqlite3)

- **`sqlite3_stmt_status(…, SQLITE_STMTSTATUS_RUN)` doesn't count a step that fails at entry.**
  On 3.53.1 and 3.45.1, an interrupted step beside a held row raised SQLITE_INTERRUPT, and the
  statement's run count stayed 0. The same statement stepped again normally read 1. A row that
  counts steps by RUN can't see a step that failed before it ran: count those through the
  statement's state or the connection's extended code. (M3 slice 4's review, chez-sqlite3)
- **An interrupt sent as a statement starts stops it before its busy wait.** SQLite clears a
  connection's interrupt when a statement starts with none running, but one that lands after the
  clear, before the statement reaches the busy handler, stops it at once with SQLITE_INTERRUPT.
  M3 slice 6's busy-wait row, meant to show interrupts don't stop the wait, failed 2 plain runs of
  30 this way: its watchdog's first interrupt raced the step's start, and `BEGIN IMMEDIATE`
  answered INTERRUPT at 0 ms where it waited 1502 ms otherwise. A row about the wait sends its
  interrupts only once the wait has surely begun, as that row does from 200 ms.
  (M3 slice 6, chez-sqlite3)
- **Apple's SQLite refuses `sqlite3_auto_extension`.** Apple's 3.51.0, on macOS 26.7.1, answered
  21, `SQLITE_MISUSE`, for a real entry point. Upstream answers 21 there only for NULL, under API
  armor. Seven suites register an authorizer through it to note every prepare. On Apple's
  library they noted nothing:
  - 19 rows failed;
  - the reset rows and two kinds of checks passed without testing anything, since an empty tell
    satisfies them.

  Homebrew's 3.54.1, on the same Mac, registered it. The suites now name the tell unavailable on
  21 alone, and drop only the checks that read it ([research/m3-mac/](research/m3-mac/)). Like
  its 21 for `db_config`'s `ENABLE_LOAD_EXTENSION` ([mac-d7](research/mac-d7/)), it's Apple's
  change. (M3's Mac run, chez-sqlite3)
- **`ENABLE_MEMORY_MANAGEMENT` changes how far a NOMEM reaches.** A multi-row write gets a
  statement journal (`usesStmtJournal = isMultiWrite && mayAbort`). On a NOMEM, SQLite rolls
  back just that statement, and the whole transaction only if that rollback fails.
  - An allocation past the heap limit calls `sqlite3_release_memory`, which frees page cache
    only in a build with `-DSQLITE_ENABLE_MEMORY_MANAGEMENT`.
  - So in such a build, Homebrew's among them, the statement's rollback succeeds and the
    transaction stays open. `test-transaction-nomem`'s S3, `insert into b select
    randomblob(100000) from src limit 3`, ended the transaction at the floor, on 3.53.1 and on
    CI's 3.54.1, and left it open on Homebrew's 3.54.1.
  - That's reproduced on Linux: open in exactly the two of five 3.54.1 builds with the option.
  - So the case is the build's, not the SQL's or the version's. Read autocommit after the
    failure, as AGENTS.md says. (M3's Mac run, chez-sqlite3)

- **A watchdog that keeps interrupting stops `with-transaction`'s own ROLLBACK and COMMIT.** The
  trap above at a statement's start reaches every statement, the library's own exits among them.
  A watchdog that called `interrupt-database!` in a tight loop left the transaction open in 351 of
  20,000 calls on 3.53.1, and 623 of 8,000 at the floor. A later `with-transaction`, then only a
  savepoint inside the leftover transaction, answered normally, and its write was gone after a
  reopen (reviewer A's `watchdog-loss.sps`). `with-transaction` now rolls back with the latch shut
  (ADR-0017, amended). (M3's closing review, chez-sqlite3)
- **SQLite's statement trace runs inside the step, after the interrupt is cleared.** A
  `SQLITE_TRACE_STMT` callback that calls `sqlite3_interrupt` stops the statement as it starts,
  every time, so a row can interrupt an exit's ROLLBACK deterministically. The callback must be
  `__collect_safe`, and locked while SQLite holds it. (M3's closing review, chez-sqlite3)
- **A busy wait on whole seconds lets a Scheme retry pass a 3000 ms bound.** On a build without
  `nanosleep`, a 1500 ms timeout waits 1000 ms, so one retry waits 2000. The closing review built
  the floor with `-DHAVE_NANOSLEEP=0` and planted a retry: every timed row passed, each wait 2000
  to 2001 ms. The rows now read the grain, and bound the wait under 2000 ms there.
  (M3's closing review, chez-sqlite3)
- **`db_config` sets no error on its connection, and a load none of its own.** After
  `sqlite3_db_config` answered 1 for an op it didn't know, the connection still said 1, "no such
  column: nosuch", an earlier prepare's, and on a fresh connection 0, which `raise-sqlite-error`
  refuses as no error. After a failed `sqlite3_load_extension`, it still said what it said
  before: the load's text is in its message slot alone. But an extension's init that fails a
  call of its own leaves that call's error there: a replacing load beside a held row answered 1,
  its slot said "error during initialization: ", and the connection said 5, "unable to
  delete/modify user-function due to active statements" (M4's research, D3, L3; M4's plan
  review, rv1, rv2). Take the code from the call's answer. (M4's research, chez-sqlite3)
- **A failed load names a path the caller never gave.** SQLite tries the path, then the path with
  a suffix appended, `.so` on Linux and `.dylib` under `__APPLE__` (3.45.1's `azEndings`), and
  reports the second failure. On Linux a missing `nosuch.so` read
  `nosuch.so.so: cannot open shared object file`, and so did an empty file or a directory,
  hiding the real cause (L2). (M4's research, chez-sqlite3)
- **A bare name to `sqlite3_load_extension` is `dlopen`'s search.** On Linux, `ext.so`, with the
  working directory holding it, wasn't found, and `./ext.so` was (L2); from another working
  directory, `ext.so` and `ext` both loaded with `LD_LIBRARY_PATH` naming the directory that held
  it, and neither without it (M4's plan review, rv3). macOS's dlopen(3) documents a leaf name
  searched in the working directory too, for an unrestricted process: not measured.
  (M4's research, chez-sqlite3)
- **A `db_config` set that changes a flag expires every statement on its connection;** one that
  changes nothing doesn't. A statement prepared and run with DQS on failed at its next step once
  `DQS_DML` was turned off: its re-prepare refused the double-quoted name (D1, D2). (M4's
  research, chez-sqlite3)
- **Each library opens connections its own way.** Ubuntu's 3.45.1, built
  `ENABLE_LOAD_EXTENSION`, opens every connection with the C call to `sqlite3_load_extension`
  on; the others whose start could be read open it off. Apple's answers 21 to the op and leaves
  the cell, so its start isn't known. Apple's 3.51.0 opens every connection with `DEFENSIVE`
  on, and no compile option it lists says so (M4's pre-work). (M4's research, chez-sqlite3)
- **`DEFENSIVE` turns `writable_schema` off without a word.** Under it,
  `PRAGMA writable_schema = 1` answered done, and read back 0 (M4's pre-work). (M4's research,
  chez-sqlite3)
- **An FTS5 table on a library without FTS5 fails at its step, not its prepare:** "no such
  module: fts5", 1 (M4's pre-work; F1). (M4's research, chez-sqlite3)
- **Every load runs the extension's init again, and a close unloads it.** Its init count read 1,
  2 and 3 across two loads into one connection and one into another, and 1 again once both had
  closed. A load whose init replaces a function failed while a statement of the connection was at
  a row, and with none held it expired every statement (L4, L8). (M4's research, chez-sqlite3)

## Checks and environment

- **A check passes whenever something else produces what it looks for.** M0 slice 1's review
  found three self-test assertions that read a symptom instead of the property:
  - `loopback-only` read "no route to 192.0.2.1". A container with a network also gives that
    when the host has no default route, as when it is offline. Reproduced: with `--network`, in a
    user network namespace holding `lo` and a dummy interface and no default route, every
    assertion passed. `interfaces` now reads `/proc/net/dev`.
  - `sqlite-header` read a version string from whichever `sqlite3.h` the compiler found first.
    Reproduced: a fake 3.37.2 header put first on `C_INCLUDE_PATH` passed. `header-matches-library`
    now compares the header's number with the library's.
  - `chez-variable` read "under the profile". Reproduced: `CHEZ=$GUIX_ENVIRONMENT/bin/petite`
    passed, and petite has no compiler. It now requires the profile's `scheme` itself.

  All three came from chez-curl's self-test, which shares them. (chez-sqlite3)
- **A switch tested as non-empty is on at 0.** `scripts/guix-env` took any non-empty
  `GUIX_ENV_DRY_RUN` as a dry run. Reproduced: with `GUIX_ENV_DRY_RUN=0`, `make check-guix`
  printed the guix command and passed, with no container run. Only `1` is a dry run now, and T9
  checks that 0 runs guix. chez-curl's launcher shares the gap. (chez-sqlite3)

- **A pattern written against a tool's padding misses a line padded otherwise.** M0 slice 3's
  measurement matched Valgrind's leak summary as `==N==` and four spaces before each kind.
  Valgrind right-aligns the kinds, so "possibly lost" has six, and the first table had no
  possibly-lost column. The slice's review found 12,856 bytes there in one case. The pattern now
  matches the words after any run of spaces. (chez-sqlite3)

- **A reason to drop a copied rule is checked against every rule the copy keeps.** M0 slice 4
  dropped chez-curl's explicit-key, alias, non-ASCII and tab rules from `check-floors`, reasoning
  that they protected rules about keys and this project had none. `check-action-pins.sh`, kept in
  the same slice, reads a key: `uses`. Reproduced: `- ? uses` then `: some-owner/some-action@main`
  passed the pin check, which counted the 9 pinned lines and saw no tenth. The review found it;
  the rules now live in `tests/check-ci.sh`. It is slice 2's lesson again, that a dropped piece
  takes its protection with it, and a reason written down is no check of it. (chez-sqlite3)

- **`env -i` in a test drops the variable that names a tool, and the default may only work
  here.** The launcher's T11b ran `make test` under `env -i`, so `CHEZ` fell back to the
  Makefile's default, `scheme` on `PATH`. The host and the container have one; CI's runner keeps
  Chez in `$RUNNER_TEMP`, on no `PATH`. On CI's second run, `make test` stopped at its
  prerequisites, and T11b's four "says why" checks failed: 79 passed, 4 failed. Reproduced in the
  container with a `PATH` of every tool but `scheme`: the same 79 and 4, then 83 with `CHEZ`
  passed through. (chez-sqlite3)

- **A value has more than one spelling, and a check of its text sees one.** `check-floors`
  refused any workflow line holding `3.45.1`. SQLite writes the same floor as `3045001`
  (`SQLITE_VERSION_NUMBER`) and as `3450100` (`sqlite-amalgamation-3450100.zip`). M0's closing
  review planted both in the `main` job, and `check-floors` and `check-ci` passed. Before
  checking a value by its text, list every form its users write it in. (chez-sqlite3)

- **A rule a record states is a rule only once a check holds it.** AGENTS.md and ADR-0005 said
  `make test` runs `check-ci`. Nothing failed when the prerequisite went: `check-help`,
  `check-test-fails` and `make test` all passed, and no `check-ci:` line appeared. The
  prerequisites `check-suites` and `check-floors` each had a plant in `check-test-fails`;
  `check-ci`, added a slice later, had none. Each new prerequisite comes with its plant. (M0's
  closing review, chez-sqlite3)

- **A scanner of forms that walks list tails finds forms that aren't there.** `test-native`'s
  first scanner counted a 16th `foreign-procedure` form in `native.sls`: `(syntax
  foreign-procedure)` in the binder's fender ends in a `(foreign-procedure)` tail, and so does
  the import clause's `(only (chezscheme) … foreign-procedure …)`. Read list elements, never
  tails. (M1 slice 2, chez-sqlite3)

- **A probe that blocks a plain foreign call can't release itself.** A collection requested by
  another thread waits for every thread, the blocked one too, so no thread of that process runs
  until the call returns. Only another process can release it: `test-native`'s FIFO row opens
  the FIFO from a shell. (M1 slice 2, chez-sqlite3)

- **`--trace-children` with a skip list sees nothing below what it skips.** Chez's `system` runs
  a static bash, which, traced, reports about 300 uninitialised-value errors and exits 9 for every
  child. Skipping the shell untraced every child it started, so a planted child leak passed. The
  gate runs each child under its own Valgrind instead (ADR-0005, M1 slice 3, chez-sqlite3).

- **GNU `env` reads `-u` only before its first assignment.** `env A=1 -u HOME sh` runs a command
  named `-u`: "env: '-u': No such file or directory". Unset first, then assign. (M1 slice 3,
  chez-sqlite3)

- **A row that finds its anchor by counting occurrences breaks when the file gains one.** A
  `test-check-ci` row named the 6th `CHEZ:` line of the workflow; slice 3's new step made it the
  7th, and the row broke on an edit it wasn't about. Anchor on a line's content. (M1 slice 3,
  chez-sqlite3)

- **A test that reads the name of the file `CHEZ` names assumes a layout.** CI's and the
  container's Chez is `…/bin/scheme`; Homebrew's on a Mac is `/opt/homebrew/bin/chez`.
  `test-check-floors`' `check-chez.sh` rows took the prefix from `CHEZ`'s path and failed 6 rows
  on the maintainer's Mac. They now build a `bin/scheme` that execs it when the name differs.
  (M1, the Mac's first hand run, chez-sqlite3)

- **macOS has no `/proc`.** Children that read `/proc/self/maps` to say whether they run under
  Valgrind printed `(valgrind . no-maps)` there, and rows that expected `no` failed; one child
  read it unguarded and died. A row's expectation says what its own process can see. (M1, the
  Mac's first hand run, chez-sqlite3)

- **One failure can answer differently by build.** `sqlite3_open_v2` on a FIFO answers
  `SQLITE_IOERR` on Guix's 3.53.1 and Homebrew's 3.54.1, and `SQLITE_CANTOPEN` on Apple's 3.51.0.
  Where the code isn't what a row is about, it names the codes it accepts, each measured. (M1,
  the Mac's first hand run, chez-sqlite3)

- **`cc -E` puts a system header's macro on a line of its own.** After `#include <sqlite3.h>`,
  `chez_v SQLITE_VERSION` came out as `chez_v `, and the value came on the next line, after a
  `# 2 "<stdin>" 3` marker. Read macros with `-dM -E`, or keep lines whole with `-P`. (M1
  slice 5, chez-sqlite3)

- **A compile option at its default may be unlisted.** SQLite lists `DEFAULT_MEMSTATUS` only when
  it isn't 1, so `-DSQLITE_DEFAULT_MEMSTATUS=1` is invisible to `sqlite3_compileoption_get`. Only
  the whole list can hold a rule about it. (M1 slice 5, chez-sqlite3)

- **A row that runs a script with `sh` can't see its execute bit.** Both of slice 5's new CI
  scripts were first written without one, and every row passed. The workflow runs them by path.
  `test-ci-sqlite` holds both bits. (M1 slice 5, chez-sqlite3)

- **A red run against a check that refuses the whole input proves no row.** Slice 5's new
  workflow, run against the old `check-ci`, failed every new row, because the old script refused
  the unedited file. Three rules' rows were logged as watched failing on that evidence. Turn each
  rule off in the new check instead. (M1 slice 5, chez-sqlite3)

- **A row that narrows `PATH` must hand each tool it names over by its path.** `test-ci-sqlite`'s
  build rows run with only their shims on `PATH`, and passed `CHEZ` on as given. In CI and the
  container that is an absolute path. On the maintainer's Mac the Makefile's default is the bare
  name `chez`, and both rows failed: "chez: command not found". (M1, the Mac's run on `497d45b`,
  chez-sqlite3)

- **An engine spends no ticks inside a critical section.** A 100,000-step loop given 10 ticks a
  slice took 10,001 slices outside a section, and 1 inside one. So a row that expects an expiry at
  every fuel fails once the work moves into a section. Assert the outcome at every fuel instead.
  (M1's closing review, chez-sqlite3)

- **`diff -r` follows symbolic links.** Two trees holding the same dangling link made it exit 2,
  "No such file or directory"; with `--no-dereference` it exits 0. The seam's fixtures hold such
  links. (M1's closing review, chez-sqlite3)

- **`false &&` before an `||` chain disables only its first test.** `false && A || B` runs `B`.
  A mutant meant to skip a whole check, written so, failed 1 row, not 5. Mutate the refusal
  instead: `true || fail …`. (M1 slice 5, chez-sqlite3)

- **A value is cut where its readers cut it.** `CHEZ_SQLITE3_GATE_CHILD` holds an absolute log
  path, and its readers cut it at whitespace, so a checkout path holding a space split it, and
  nothing refused one; `test-memory` now does. A plant for such a path is a real directory:
  `CURDIR` is the physical path, and a symlink's name never reaches it. (M1's owed fixes,
  chez-sqlite3)

- **A planted library must sit in a whole copy of the tree.** `test-library-loading` starts its
  children with `--libdirs src`, so a planted `native.sls` on a library path ahead of `src/` never
  reaches them, and a mutant there passes unseen. M2 slice 2's builder and reviewer ran every
  mutant from inside a copy. (M2 slice 2, chez-sqlite3)

- **A list that makes rows makes no row for what it drops.** `test-library-loading` builds a
  decoy and a `missing-api` row for each entry point in a written list. With one entry deleted the
  suite passed 90 of 90, and with four reordered 91 of 91. A row now holds the list to the
  convention table, which `test-conventions` holds to native. (M2 slice 2's review, chez-sqlite3)

- **A forked thread's uncaught raise removes the suite's whole temp directory.** A thread
  inherits its parent's `base-exception-handler`, and `make-process-temp-directory` hooks that
  handler to remove its directory when the process dies on a raise. So a thread that dies on a
  raise runs the hook, and the main thread goes on without the directory. A probe printed
  `(before #t)`, the raise, then `(after #f)`, and exited 0 (`thread-removes-dir.sps`). Under a
  plant whose thread raised, every later row's open failed `cantopen`. M3 slice 6's suites make
  every thread's raise its answer, and `test-contention` gives each row its own directory through
  `call-with-temp-directory`. A fix in the testing library would remove the directory only on the
  thread that made it. ([research/m3-slice-6/](research/m3-slice-6/README.md); M3 slice 6,
  chez-sqlite3)

- **A deferred transaction's write fails at once only after it has read.** With nothing read, its
  first write waited out a 1500 ms busy timeout, 1501 to 1502 ms, then answered `busy`. After a
  `select`, the same write answered `busy` in 0 ms. Each left the transaction open
  (`deferred-first-write.sps`). SQLite calls the busy handler only while no read transaction is
  open (concurrency B2). ADR-0017's consequence had dropped "after a read" (ADR-0017, amended in
  M3 slice 6). (M3 slice 6, chez-sqlite3)

- **A flag set by a blocked thread can't show that its call returned before a collection.** The
  blocked thread joins the collection before it runs its `set!`, so the flag read "still blocked"
  under every plain binding of M2 slice 3's four blocking calls, and only the time bound failed.
  Bound the collection's time against the call's, and read the time, not a flag. (M2 slice 3,
  chez-sqlite3)

- **At the floor, Valgrind can't tell a leaked statement from its connection.** The statement
  plant's loss record at 3.45.1 is byte-identical to the connection plant's: 57,432 bytes in one
  block. At 3.53.1 the statement adds 5,152 bytes in 19 blocks. So the plant's own counts line,
  `(statement . 1)`, is what holds that the counters saw the statement. (M2 slice 3, chez-sqlite3)

- **zsh doesn't treat `#` as a comment at an interactive prompt.** That's `interactivecomments`,
  off by default. A command block given to the maintainer with `# Apple's …` after a command passed
  the comment as arguments, and its apostrophe opened a quote that swallowed the next line. So the
  Homebrew run of M2's Mac run never ran. Commands for the maintainer to paste carry no comments.
  (M2's Mac run, chez-sqlite3)

- **One CI run is one sample.** CI's runners differ about two to one: the same code ran
  `test-library-loading` in 555.1 s at `5dd3af0` and 284.8 s at `0572267`. M2 slice 2 settled from
  one 409.3 s run that the suite stays whole, and #19's own run took 562.2 s, 38 s from the
  timeout. Read a cost from several runs, and let `make test-memory`'s `SLOW` check hold the
  limit. (M2's closing review, chez-sqlite3)

- **`make check-suites` reads a suite's data as forms.** A quoted list holding `(exit return 0)`,
  a tag in a suite's own event log, was refused as an exit before the suite's verdict, and so was
  a `case` clause `((exit) …)`. The check reads every datum by its shape, as it must to see an
  exit anywhere; name such a tag something else. (M3 slice 1, chez-sqlite3)

- **A two-thread row whose mutant shows only inside a bounded wait passes that mutant when a
  thread is late.** M3 slice 1's interrupt row caught six mutants of the latch only if the closer
  reached the close's work within the stand-in's 200 ms wait: with a 1 s sleep put in the closer
  before its close, the mutant without the mutex passed. The fix starts the bounded wait only
  after the other thread has noted that it is about to act, so the window holds no thread's
  wake-up. (M3 slice 1's review, chez-sqlite3) `test-contention`'s default-mode row had the same
  shape, and failed on correct code: with the second thread 700 ms late, its deferred half failed
  with no fault in the library. Its window now starts when the second thread says it runs.
  (M3's closing review, chez-sqlite3)

- **A floor run that sets only the library compiles its C against another header.**
  - **What goes wrong:** `CHEZ_SQLITE3_LIBRARY` chooses the library the suites load. The C they
    compile reads whichever `sqlite3.h` the compiler finds first: `test-constants`' prototype and
    constant checks, the C oracle and the decoy. In the container, that header is Guix's 3.53.1.
  - **Where it happened:** M3 slice 2's local floor runs set only the library. So they held 3.45.1
    to 3.53.1's header, and passed.
  - **Reproduced:** under that setting, `$CC -dM -E` printed `SQLITE_VERSION "3.53.1"` while
    native loaded 3045001.
  - **The fix:** CI's `floor` lane sets `C_INCLUDE_PATH` to the floor's headers, and a local floor
    run must too.
  - **No check:** no suite compares the header with the loaded library. A check would also bind
    the Mac runs, where Homebrew's library through the override compiles against the SDK's header
    (the maintainer, 2026-11-16: "Record a trap only").

  (M3 slice 2's review, chez-sqlite3)

- **Under Valgrind, a watchdog thread waits while another thread runs C.** Valgrind runs one
  thread at a time, and the owner's `sqlite3_step` kept the lock, so a watchdog meant to
  interrupt it every 5 ms sent its first interrupt 16.5 s and 42.7 s into the call. Whole runs of
  `test-transaction-interrupt` took 12 to 71 s under the gate, and 99 s once. `--fair-sched=yes`
  answered "fair scheduling is not supported on this system". A deadline bounds the watchdog's
  life, and must never fail a row by itself: the latency is the scheduler's. (M3 slice 4's review,
  chez-sqlite3)
  - **Against a prepare, a watchdog may not run at all.** Under Valgrind, a watchdog against a
    prepare of 4 MB of comments, interrupting with no sleep, stopped none of 15 prepares in M3
    slice 6's runs, sending no interrupt in 14 of them; one sleeping 1 ms a round stopped none of
    3. Plain, the first stopped 8 of 9, in about 170 ms each, and the second 0 of 3.
  - **A thread blocked on a mutex lets the others run.** So M3 slice 6's watchdog takes SQLite's
    memory mutex, `SQLITE_MUTEX_STATIC_MEM`, sleeps 1 ms holding it, interrupts, then lets it
    go. The owner's next allocation inside SQLite blocks, and the interrupt lands there: 3 of 3
    prepares stopped in the first round, SQL chosen to allocate as it runs. It needs SQLite's
    memory statistics on.
  - **Every call the owner makes while the mutex may be held** is `__collect_safe` or takes none
    of SQLite's memory. Otherwise the owner blocks in a plain call that another thread's
    collection waits on.
  - **A critical section around the hold breaks it:** the owner's collections then wait for the
    section's end, which lets the mutex go.
  - **The first round can be lost before the call begins.** SQLite clears the interrupt at a
    statement's start and at a prepare's parse, when no other statement is active, and a prepare
    reads it only while its tokenizer runs, never in the code it generates after the last token
    (3.45.1's and 3.54.1's source). Slice 6's first round interrupted while the owner was still
    copying 3 MB of SQL in Scheme, so the parse's clear erased it, and a later round had to win
    the CPU from Valgrind inside the short tokenizing window. The long prepare ran unstopped
    once on CI (run 44087748537, on `main`), and in 1 of 27 gate runs here. With the prepare
    called 200 ms late, it ran unstopped in 13 of 70 probe trials and 15 of 40 suite runs
    (`research/m3-review/suites/prepare-race.sps`).
  - **So the first round is a handshake:** holding the mutex, interrupt before the call; read
    `sqlite3_is_interrupted` each 1 ms until it reads clear, which only the call's own start or
    parse does, the owner then held at its next allocation; interrupt again, inside the call; let
    go. None of 95 trials and none of 40 suite runs left it unstopped. A step reads the flag until
    it returns, so there a lost first round costs only time. (M3's closing review, chez-sqlite3)

  ([research/m3-slice-6/](research/m3-slice-6/README.md); ADR-0019, amended in M3 slice 6.)
  (M3 slice 6, chez-sqlite3)

- **Deleting a stacked PR's base branch closes the PR on GitHub; it doesn't retarget it.** In M3's
  merge train, after #22 was squash-merged, `git push origin --delete m3-slice-1-core` closed #23,
  whose base it was. GitHub retargets a dependent PR only when the merged PR's own branch is
  deleted through its merge flow, and `delete_branch_on_merge` is off here.
  - **Recovered** by pushing the branch back at its old SHA, `gh pr reopen 23`, `gh pr edit 23
    --base main`, and then deleting the branch.
  - **The order:** merge; retarget the next PR to `main`; check that no open PR still has the old
    base; then delete. (M3's merge train, chez-sqlite3)

- **A sweep that reuses one remainder across its trials sweeps nothing past the first.** The
  lead's first sweep of the conveniences under pending resumes took one remainder R a fuel and
  resumed it at every G. After the first trial R's call had ended, so every later trial was
  refused at once, and the sweep found slice 3's `query` clean in 3,876 trials, where a fresh
  engine and connection a trial found a statement left out of the cache in 3,655 of 10,147. Its
  `query-fold` passed the seed for the procedure, so every trial raised at the procedure's check.
  Take a fresh remainder and connection for every trial, check the call's clean answer first, and
  count the trials in which both runs got past the call's first section: a sweep fails by name
  when that count is trivial, as M3 slice 5's part D suites do (the M2 session's guard;
  [research/m3-slice-5/](research/m3-slice-5/README.md), `pending-sweep.sps`). Count it
  against the fuels swept, not as a fixed total: slice 4's guard of 1,000 trials failed at 647
  once part D halved the call's fuel.
  (M3 slice 5's part D, chez-sqlite3)
- **A stand-in that only notes its call may cost an engine no tick, so no fuel splits it from the
  code before it.** M3 slice 6's sweep of `interrupt-database/with` on a stand-in was to catch a
  call made after the latch returns, an expiry between the latch and the call. With a stand-in
  that only noted its call, the probe found no fuel at which the planted call came after the
  close, bare or wrapped, and the suite one fuel of 14, by its own guard's ticks. With 20 turns of
  a loop before the note, the probe found 20 fuels of 26, alike at the floor, and the suite 21 of
  34. Which code costs a tick is the compiler's. Give a stand-in ticks of its own before the
  effect a row reads, and watch the plant fail at more than one fuel. Inside a critical section
  the loop costs no tick, so the right code completes at the same fuel
  ([research/m3-slice-6/](research/m3-slice-6/README.md), `a2-engine-trials.sps`).
  (M3 slice 6's review, chez-sqlite3)
- **A comma inside a make function's arguments splits them, and the recipe's shell then fails.**
  M3 slice 6's first refusal of a shard's list from outside wrote "to run other suites, give …"
  inside `$(foreach … $(if …,echo "…",))`. Make read the comma as the end of the `$(if)`'s
  then-part, so the shell got an `echo` with its quote left open, and every `make test-memory`
  failed before any suite ran. Reproduced with GNU Make 4.3: a recipe
  `$(if $(X),echo "one, two" >&2; exit 1;) echo after`, with `X := 1`, fails with
  `Syntax error: Unterminated quoted string`; with "one and two" it prints the message. Write a
  message inside a make function's arguments with no comma, or take the test into the shell, as
  `test-memory` now reads the lists' origins.
  (M3 slice 6's part C, chez-sqlite3)

- **A gate's `UNAVAILABLE` line on Linux is read by no one unless something holds the gate.**
  PR #30's tell gate skipped its 33 rows when `sqlite3_auto_extension` answered 21. Planted to
  answer 21, the main and floor lanes passed 73 of 73, and `make test-memory` printed nothing:
  a passing suite's lines stay in `build/memory/<suite>.log`. The memory check was held all along,
  by `test-memory-check`'s rows, `check-test-fails`' leaks case and the lanes' compile-option
  lists; the tell by nothing. The suites now register an idle entry point straight through the
  FFI, and require the gate to agree with it. So does NOMEM's `memory-kept`, with the memory
  check's control. (M3's closing review, chez-sqlite3)
- **A watchdog that dies holding SQLite's memory mutex hangs the owner for good.** In
  `test-interrupt-reach` and `test-interrupt-close`, a raise from the hold's `sleep` killed the
  thread with the mutex taken: each suite hung to its 400 s timeout. A raise from `mutex-enter`
  killed it before it started, and the long step ran uninterrupted. A round's raise now goes to a
  handler that lets the mutex go and notes it. (M3's closing review, chez-sqlite3)
- **A suite's time under the gate can be the host's, not the code's.**
  `test-transaction-interrupt`'s plain watchdog took 18 to 77 s under the gate on 18 cores, and 11
  to 15 s pinned to two; slice 6 had measured 429 to 434 s, and CI 31 to 318 s. Valgrind runs one
  thread at a time, so a watchdog's turn is the scheduler's. With the memory-mutex device it took
  10 to 16 s in every run. (M3's closing review, chez-sqlite3)

## Editing the records

- **A global replace also hits the sentence that defines what it replaces.** In M0 slice 0,
  `sed 's/ \*(provisional)\*//g'` over `global-constraints.md` removed every rule's marker. It also
  removed the marker from the preamble, the sentence that says what the marker means: "is marked
  *(provisional)* until" became "is marked until". A `grep -c` afterwards answered 0, where 1 was
  due. (chez-sqlite3)
- **A sibling's record cited by its number alone reads as one of ours.** Four citations in M0 slice 0's records named a sibling's
  record by its number alone, after a line break or the word "its". The slice's check of cited
  record numbers flagged the one with no record here; the other three needed a read. (chez-sqlite3)
