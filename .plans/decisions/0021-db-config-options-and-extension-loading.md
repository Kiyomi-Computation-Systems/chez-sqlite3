# ADR-0021: `db_config`'s options are settings, held by the set's own answer, and extension loading is opted into at open and refused in Scheme otherwise

- **Status:** Accepted (the maintainer, 2026-11-17, "Accept all"), proposed in M4 slice 0 ([the M4 plan](../2026-11-17-m4-plan.md), §4.1 to §4.4).
  Built on the maintainer's answers of 2026-11-16 and 2026-11-17 to the pre-work's questions
  ([research/m4-prework/](../research/m4-prework/README.md#the-maintainers-answers-2026-11-16)):
  decision 3's place, "In the settings list" (Q10), and its check, "Hold the set's answer" (Q8);
  decision 2's starts, "SQLite's default, settable" (Q5) and "Library's start, documented" (Q13);
  decision 6, "Refuse in Scheme" (Q3); decision 5's condition, tested by "The decoy" (Q4);
  decision 4's check, "Check plus check-variadic" (Q9); decision 11's `TRUSTED_SCHEMA`, "PRAGMA
  only" (Q7). And on the maintainer's answers to the plan's own questions, 2026-11-17 (the plan,
  §3): decision 1's names, "The rule's names" (Q14); decision 5's `#f`, "Same as leaving it out"
  (Q15); decision 7's path, "An absolute path" (Q16); and Q14 and Q15 taken together, asked again
  from the user's side, "Yes, as shown". Revised the same day after the plan's review (Opus):
  decision 3's and 7's codes, decision 7's message, its owner check, its free, and the
  context's Linux facts.
  Amended 2026-11-17 in M4 slice 1, and accepted by the maintainer that day ("Accept"): the
  cell's sentinel, the core's constant, and a code that names no error, "Assertion violation"
  ([amendment](#amendment-2026-11-17-the-sentinel-and-a-code-that-names-no-error-m4-slice-1)).
  Amended 2026-11-17 in M4's close fix, and accepted by the maintainer that day ("Accept all"): an extension's open work and the close
  ([amendment](#amendment-2026-11-17-an-extensions-open-work-and-the-close-m4s-close-fix)).
- **Date:** 2026-11-17
- **Scope:** chez-sqlite3 v1: `sqlite3_db_config`, and loading an extension
- **Settles:** brief §2.5 and §2.8, as the M4 plan amends them
- **Related:** [ADR-0001](0001-bind-libsqlite3-directly.md) (the variadic binding) ·
  [ADR-0002](0002-runtime-libsqlite3-discovery.md) (the optional entry point) ·
  [ADR-0010](0010-a-connection-belongs-to-its-thread.md) (the owner thread) ·
  [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (conventions and memory) ·
  [ADR-0012](0012-explicit-close-and-the-handle.md) (the record) ·
  [ADR-0013](0013-errors-are-condition-types.md) (the new condition) ·
  [ADR-0018](0018-the-settings-list.md) (the settings list) ·
  [research/m4-prework/](../research/m4-prework/README.md) · [research/m4-plan/](../research/m4-plan/README.md)

## Context

Measured on Guix's 3.53.1, the floor's 3.45.1, the `current` lane's 3.54.1, Ubuntu 24.04's
3.45.1 (the `main` lane's), a floor built `OMIT_LOAD_EXTENSION`, and on the maintainer's Mac,
Apple's 3.51.0 and Homebrew's 3.54.1 (pre-work); and on the first three again, on Linux x86_64
(M4's research, and M4's plan review's probes rv1 to rv3, rerun there):

- **`sqlite3_db_config` is variadic:** `int sqlite3_db_config(sqlite3*, int op, ...)`. Bound with
  `(__varargs_after 2)` in the shape `(db op int int*)`, every op round-tripped on every library.
  Bound plain, it worked on x86_64 and crashed on Apple arm64, with both libraries (pre-work).
- **The `int*` gets the state after every call,** a set's as well as a read's: always 0 or 1
  (research D6). An unknown op answers 1 and leaves the cell untouched (pre-work).
- **The starts differ by library.** `DQS_DML` and `DQS_DDL` start at 1 everywhere measured.
  `DEFENSIVE` starts at 1 on Apple's, 0 on the six others. `ENABLE_LOAD_EXTENSION` starts at 1 on
  Ubuntu's, which is built `ENABLE_LOAD_EXTENSION`, and 0 on the others whose start could be read;
  Apple's answers 21 to every call of that op, leaving the cell untouched, so its start isn't
  known (pre-work; [mac-d7](../research/mac-d7/)).
- **A set does no I/O and never waits:** under another connection's `BEGIN EXCLUSIVE`, with a
  1500 ms busy timeout, each set took 0.001 ms or less, where a prepare waited 1501 ms (research
  D4). It round-trips on `:memory:`, an unread file, `READONLY`, `NOMUTEX`, inside a transaction,
  and beside a statement at a row (D5).
- **A set that changes a flag expires the connection's other statements;** one that changes
  nothing doesn't. A statement prepared under DQS on then fails at its next step once DQS is
  turned off: its re-prepare refuses the double-quoted string (D1, D2).
- **No op changes what ADR-0018's PRAGMAs do:** on a file holding a table, each of the six read
  back as written with the ops at their start and with `DEFENSIVE` 1 and both DQS 0. Under
  `DEFENSIVE`, `journal_mode = off` and `writable_schema = 1`, which the list doesn't hold, were
  refused silently (rv1, part C).
- **`db_config` sets no error on its connection:** after a refused op, the connection's code and
  `sqlite3_errmsg` were still the last statement's failure's, 1 and "no such column", and on a
  fresh connection 0 and "not an error" (D3). M2's `raise-sqlite-error` refuses a code whose low
  byte is 0 as no error (rv2).
- **Extension loading's two switches:** `ENABLE_LOAD_EXTENSION` turns on the C call alone. SQL's
  `load_extension()` needs `SQLITE_LoadExtFunc` too, which only `sqlite3_enable_load_extension`
  sets, and stays "not authorized" with the C call on (pre-work; research L7).
- **A library without extension loading:** Apple's lacks `sqlite3_load_extension`. Upstream's
  `OMIT_LOAD_EXTENSION` build lacks it too, yet answers 0 to the op and round-trips a flag that
  does nothing (pre-work). So `db_config`'s answer can't tell such a library; `foreign-entry?` can.
- **`sqlite3_load_extension`** (research L1 to L8; X1; rv1; rv3):
  - every failure measured answers 1, its message in `*pzErrMsg`, allocated by SQLite, for
    `sqlite3_free`. SQLite's own failures set no error on the connection: its code and message
    stayed as they were, 0 and "not an error" on a fresh one (L3), 1 and "no such column: nosuch"
    after a failed prepare, through a failed load and a successful one (rv1, part A). By the
    source, `sqlite3_load_extension` sets one only when memory runs out;
  - **an init that fails a call of its own leaves that call's error on the connection:** a second
    load, whose init replaces the functions the first registered, beside a statement at a row,
    answered 1, its slot "error during initialization: ", and the connection said 5, "unable to
    delete/modify user-function due to active statements", where it had said 100 before (rv1,
    part B; L8). The reason is the connection's, and the slot lost it;
  - SQLite tries the path, then the path with a suffix appended, `.so` on Linux, `.dylib` under
    `__APPLE__` (3.45.1's `azEndings`), and reports the second failure: on Linux a missing
    `nosuch.so` reads `nosuch.so.so` (L2);
  - with no entry point named, it tries `sqlite3_extension_init`, then a name derived from the
    file (L2);
  - on Linux a bare name is `dlopen`'s search: never the working directory (L2), and
    `LD_LIBRARY_PATH`'s directories, where both `ext.so` and `ext` loaded from another working
    directory (rv3). macOS's dlopen(3) documents a leaf name searched in the working directory
    too, for an unrestricted process: not measured;
  - every load runs the extension's init again, and a close unloads it (L4);
  - SQLite lets another thread load on a connection (L5);
  - on a FIFO the call blocked until a writer opened it (L6). Bound plain, another thread's
    collection waited 1.15 s, the whole wait; bound `__collect_safe`, 1 ms (X1);
  - an extension compiled at test time against `sqlite3ext.h`, 50 ms with `$CC`, loaded, called
    and closed under the gate's Valgrind with 0 errors and nothing definitely lost, and the same
    still reachable blocks as the same program left without a load. Its unfreed messages were 448
    bytes definitely lost, and 432 bytes of `sqlite3_memory_used` (X1);
  - a second load whose init replaces functions fails while a statement is at a row, and a
    replacing load expires the connection's statements (L8).
- **What a user expects, by the maintainer's re-check of Q14 and Q15:** Python's `sqlite3` has
  `enable_load_extension(True)`, then `load_extension(path)`. The C flag's own state can't be
  observed through this library: no verb reads it, and SQL's `load_extension()` stays refused
  whatever it holds. The maintainer's principle is least surprise, and a clear method for a user
  to load an extension.

## Decision

1. **Four `db_config` options join ADR-0018's settings list,** each `#t` or `#f`:

   | Setting | Op | What `#t` does |
   |---|---|---|
   | `enable-load-extension` | `SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION` (1005) | lets `load-extension!` work: the opt-in (decision 5) |
   | `defensive` | `SQLITE_DBCONFIG_DEFENSIVE` (1010) | defensive mode |
   | `dqs-dml` | `SQLITE_DBCONFIG_DQS_DML` (1013) | double-quoted strings in DML |
   | `dqs-ddl` | `SQLITE_DBCONFIG_DQS_DDL` (1014) | double-quoted strings in DDL |

   Each name is its op's C name with `SQLITE_DBCONFIG_` dropped, lower-cased, `_` turned to `-`,
   as ADR-0013 names a code (the maintainer's Q14, "The rule's names"). By that rule
   `TRUSTED_SCHEMA`'s would be `trusted-schema`, ADR-0018's PRAGMA, which sets the same flag: it
   stays the one way in (Q7). Every other op is no setting, refused as `unknown-setting`.
2. **A setting is set only where the list names it** (Q5, Q13). No call is added to an open: a
   connection starts as its library starts it, DQS on everywhere measured, `DEFENSIVE` on Apple's
   library alone. `docs/reference.md` says so, and says that under `defensive` a caller's
   `PRAGMA writable_schema = 1` answers done and does nothing (Q6).
3. **Each of `defensive`, `dqs-dml`, `dqs-ddl` and the opt-in's `#t` is one call, at open, in the
   list's order, held by its own answer** (Q8, Q10):
   - it runs among ADR-0018's settings, by its decision 5: `busy-timeout` first, then the rest in
     the list's order, each finished before the next begins;
   - it is one `sqlite3_db_config` call in a critical section of its own, which claims the open's
     claim as each PRAGMA's sections do (ADR-0018, amended in M3 slice 5). The cell is a counted
     block holding a sentinel that is neither 0 nor 1 before the call (ADR-0011, decision 3), read
     and freed in the same section;
   - **code 0 and the cell the value written** is a match. **Code 0 and any other cell** raises
     `&sqlite-setting-mismatch`: the setting, the value asked for, and the value read, `#t` for 1,
     `#f` for 0, `()` for a cell left at the sentinel, "nothing read" as ADR-0018's no-row
     read-back has it, and any other integer as itself;
   - **any other code** raises `&sqlite-error` from the one procedure that makes one, its code
     and extended code that answer, never the connection's `sqlite3_extended_errcode`, which a
     refused set leaves at another call's, or at 0, which `raise-sqlite-error` refuses (D3, rv2);
     its message `sqlite3_errstr` of the answer, for the same reason; no SQL or offset. 1 means an
     op the library doesn't know, a mistake of ours at the floor; Apple's 21 is the one other code
     measured, and decision 5 refuses first where it arises;
   - either way the connection is closed first, then the condition raised, and a close that fails
     then isn't raised over it (ADR-0018, decision 7, amended).
4. **`sqlite3_db_config` is bound once, in the shape `(uptr int int uptr) int`, with
   `(__varargs_after 2)`, plain** (ADR-0001, decision 2; Q11: it never waited, D4). It is a
   required entry point, in the floor's build. `make check-variadic` removes the convention in a
   copy of the tree and watches `test-conventions` fail, and, on Apple arm64, `test-native` too
   (Q9). CI's `main` job runs it as a step, as chez-curl's ci.yml runs its own, and `make test`
   doesn't. No other shape is bound: `LOOKASIDE`'s isn't in v1 (brief §2.8).
5. **`enable-load-extension` says whether `load-extension!` works on the connection** (Q14, Q15,
   and the re-check, "Yes, as shown"). It is the library's form of Python's
   `enable_load_extension(True)` before `load_extension(path)`.
   - **`#t` is the opt-in.** Before anything opens, with the list's own checks, a library that
     lacks `sqlite3_load_extension`, by native's `foreign-entry?` at its load (ADR-0002), is
     refused: `&sqlite-extensions-unavailable` from the open verb, nothing allocated, no
     `db_config` call (Q4). Otherwise the op is set to 1 by decision 3, and the record holds the
     opt-in, fixed when the record is made, as the cache's capacity is (ADR-0020, amended in M3
     slice 5). A set that fails or mismatches closes the connection, so no caller holds a record
     whose opt-in the C call doesn't have.
   - **`#f` is the same as leaving the setting out** (Q15, "Same as leaving it out"): no call,
     and `load-extension!` refused. The op's 0 is never sent. The C flag's state can't be observed
     through the library, so a call that turned it off would protect nothing decision 6's refusal
     doesn't, and would add a failure, Apple's 21. Here the opt-in departs from Q10's "set at every
     open": only its `#t` is a set.
6. **The guarantee lives in Scheme** (Q3). `load-extension!` refuses a connection without the
   opt-in, an assertion violation naming its rule, `extension-loading-not-enabled`, before
   anything reaches C, and its message names the fix, `(enable-load-extension . #t)` (the
   re-check). So on Ubuntu's library, whose every connection opens with the C call on, nothing
   loads unasked: no C call is made but the verb's. SQL text never loads a library:
   `sqlite3_enable_load_extension` is never bound (ADR-0002, amended), and SQL's
   `load_extension()` stays refused with the C call on (L7).
7. **`load-extension!`:**

   ```scheme
   ;; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))
   (define db (open-database "app.db" '((enable-load-extension . #t))))
   (load-extension! db "/usr/lib/sqlite3/ext.so")
   (load-extension! db "/usr/lib/sqlite3/ext.so" "sqlite3_ext_init")
   ```

   - **Its checks, in order, before anything reaches C:** a database; on its owning thread, else
     `&sqlite-wrong-thread` (ADR-0010); open, else `&sqlite-closed`; the path a string holding no
     U+0000 and absolute (Q16, "An absolute path"), and the entry point, when given, a string
     holding no U+0000, each an assertion violation naming a string by its kind (ADR-0013,
     decision 7); then the opt-in (decision 6). SQLite itself loads from any thread (L5).
     `call-with-open-handle` checks the owner again before its section, so the two checks keep
     another thread out, and the verb's own puts the thread's refusal before the argument checks.
   - **The call holds a claim,** as the conveniences' and the open verbs' do (ADR-0016 and
     ADR-0018, amended): one critical section, through `call-with-open-handle`, claims it, so a
     run of the call that another has passed loads nothing and raises `&sqlite-closed`. An
     extension's init runs again at every load (L4), so a second run would run it twice.
   - **That one section** holds the path's and the entry point's C strings, the message's slot, a
     pointer-sized counted block set to NULL; the connection's extended code, read just before the
     call and again just after it; the call; when the slot holds a message, its copy by
     `c-string->string` under a guard, then its `sqlite3_free` whatever the copy did; and, when
     the extended code changed across the call, the connection's `sqlite3_errmsg`, copied. It
     answers data, and anything the copy raised is raised after it, so no message is left unfreed
     on any path.
   - **No entry point given passes NULL,** and SQLite's own search runs: `sqlite3_extension_init`,
     then the name it derives from the file.
   - **A failure raises `&sqlite-error`** from the one procedure, its code and extended code the
     call's own answer, 1, `error`, in every failure measured, never the connection's, which read
     5 after rv1's (part B); no SQL or offset. Its message is the slot's text, as SQLite wrote it,
     which names the path it tried last, its suffix appended when the path failed (L2); followed,
     when the connection's extended code changed across the call, by the connection's message,
     which holds an init's reason where the slot says only "error during initialization: " (rv1,
     part B); and `sqlite3_errstr`'s when the slot holds none. An init whose failing call leaves
     the code it found gives the slot's text alone.
   - **Success answers nothing.** The extension stays loaded until the connection closes, and
     what it registers belongs to that connection (L4).
8. **`sqlite3_load_extension` is `__collect_safe`** (ADR-0011, decision 5): a measurement shows it
   waiting, on a FIFO, and a plain binding held another thread's collection for the whole wait
   (L6, X1). It is optional (ADR-0002, amended): bound only when `foreign-entry?` finds it, its
   absence decision 5's condition, never a refusal of the load.
9. **`sqlite3_free` is required and plain,** bound to free the load's message alone. Both the
   gate's Valgrind and the memory check see a message left unfreed (X1).
10. **`&sqlite-extensions-unavailable`** is a new condition under `&chez-sqlite3-error`, with no
    field beyond its `&who` and a fixed `&message` (ADR-0013, amended). It isn't a
    `&sqlite-error`, since SQLite answered no code, nor a `&sqlite-library-unavailable`, since the
    library loads and works.
11. **Never bound:** `sqlite3_enable_load_extension` (decision 6); `sqlite3_config` (brief §2.8);
    `db_config`'s other shapes, `LOOKASIDE`'s and `MAINDBNAME`'s; `TRUSTED_SCHEMA` as an op (Q7);
    `sqlite3_auto_extension` and its two siblings, which register an init for every connection of
    the process.

### Rejected

- **A verb that sets an op on an open connection** (Q10's other options). A changing set expires
  the connection's statements, the cache's among them, and one prepared under DQS on can then
  fail at its next step (D1, D2). At open there is no statement to expire.
- **A second call to read the value back** (Q8's other option). The set's own cell is the state
  after the call (D6), so a read adds a call and checks nothing more.
- **A failure's code read from the connection,** as M2's `failure-details` reads it for a
  statement. After a refused set it is another call's, or 0, which `raise-sqlite-error` refuses
  as no error (D3, rv2), and after rv1's failed load it was 5 where the call answered 1.
- **A load's message from the slot alone,** or from `sqlite3_errmsg` alone. The slot lost the
  reason when an init's own call failed; the connection's message, read unconditionally, is an
  earlier call's after SQLite's own failures (rv1, parts A and B).
- **Turning DQS off by default,** as SQLite's documentation advises (Q5), and **setting
  `DEFENSIVE` at every open** (Q13): each adds a call to every open, and changes what SQL means
  for a caller who didn't ask.
- **`(enable-load-extension . #f)` as a call setting the op to 0,** and **`#f` refused** (Q15's
  other options).
- **A path that is relative, or a bare name** (Q16's other options): a bare name is `dlopen`'s
  search, which the environment steers (rv3), and a relative path the working directory's at the
  call.
- **Telling a library without extension loading by `db_config`'s answer:** upstream's
  `OMIT_LOAD_EXTENSION` build answers 0, and Apple's 21 is Apple's own (pre-work, Q4).
- **A real `OMIT_LOAD_EXTENSION` build in CI** (Q4): the decoy reaches the condition in a fresh
  process, without a third compiled lane.
- **Binding `sqlite3_enable_load_extension`:** it turns on SQL's `load_extension()` too.
- **A library condition for a connection that didn't opt in:** it is the caller's mistake, found
  before anything reaches C, so it is an assertion violation (ADR-0013, decision 7), as
  `with-transaction`'s refusal beside a held row is.
- **The load bound plain:** it waits on a FIFO, and held another thread's collection 1.15 s (X1).
- **Refusing a load while a statement of the connection is at a row.** Only a load that
  replaces functions fails then, with SQLite's own code, and its reason now reaches the caller
  (decision 7); no promise of ours breaks (L8).

## Consequences

- **An open with these settings makes one more call each,** no statement and no I/O: smaller
  than a PRAGMA's two statements.
- **On Apple's library, `(enable-load-extension . #t)` refuses the open** with the named
  condition; a caller who wants extensions there names another library with
  `CHEZ_SQLITE3_LIBRARY`, Homebrew's among them.
- **A connection that never opts in can't load, whatever its library's start:** on Ubuntu's, the
  C call is on and nothing makes it.
- **A load's message carries the caller's path,** as SQLite wrote it. It is SQLite's text, kept
  whole as every `&sqlite-error`'s message is, where ADR-0013's decision 7 names a string by its
  kind only in the library's own refusals.
- **An extension is C code that runs in the process,** at every load, with the calling thread
  deactivated for the call (decision 8). chez-sqlite3 checks none of it; the caller chooses what
  to load. A loaded extension's functions are callbacks of C into C, outside brief §4's
  exclusion of callbacks into Scheme.
- **The suites need a loadable extension:** they compile one at test time from a C file under
  `tests/`, with the compiler the constants check uses, as the decoy is compiled. A missing
  compiler or `sqlite3ext.h` fails the suite, never skips it (ADR-0001, decision 3). On the Mac it
  is a `.dylib`.
- **`docs/reference.md`** gains the four settings, their starts by library, and, in slice 4, an
  Extensions entry that opens with the method: open with `(enable-load-extension . #t)`, load by
  an absolute path, and the refusal, naming the setting, without it. It says that a failure's
  message names the path SQLite tried last, and gives `sqlite-extensions-unavailable?`.

## Amendment, 2026-11-17: the sentinel, and a code that names no error (M4 slice 1)

Accepted by the maintainer on 2026-11-17 ("Accept"), proposed in M4 slice 1
([its mutation log](../m4-slice-1-mutation-log.md)), from the slice and its review (Opus). The
code's rule is the maintainer's: "Assertion violation" (2026-11-17).

- **The sentinel is the core's constant, -1:** `db-config-sentinel`, in
  `(chez-sqlite3 private settings)`, not an argument of the verdict. The call writes 0 or 1 to
  the cell whatever it is given (the M4 plan's research, D6), so a cell still holding -1 was left
  by the call, and the verdict reads it as `()`. The open fills the cell with
  `db-config-sentinel`, never a literal of its own, so the fill and the reading are one value.
  The plan's "a sentinel of 0 or 1 refused" (§5, item 1) is held by a row on the constant: an
  exact integer a C `int` holds, neither 0 nor 1.
- **A code that names no error is an assertion violation.** Decision 3's "any other code raises
  `&sqlite-error`" holds for each code SQLite answers a refused set with: 1, and Apple's 21. A code
  whose low byte is 0, 100 or 101 names no error, and `raise-sqlite-error` refuses it as
  `not-an-error`, an assertion violation. No library measured answers one to `sqlite3_db_config`.
  If one does, the open closes the connection first, as decision 3 says, and then raises an
  assertion violation from the verb called, `open-database` or `call-with-database`, its
  irritants `(not-an-error CODE)`: the answer is a defect, SQLite's or chez-sqlite3's, not a
  refusal. The open tests the code itself before `raise-sqlite-error`, whose own refusal would
  name `raise-sqlite-error`, where ADR-0013's decision 2 has every raise name the procedure the
  caller called. The verdict answers `(error CODE)` for it, as for any code but 0. M4 slice 3's
  stand-in row answers 100 and asserts the verb's `&who` and `(not-an-error 100)`, which a code
  read from the connection, `(not-an-error 0)`, does not meet.
- **This narrows "another code raises `&sqlite-error`"** in decision 3, in ADR-0018's amendment
  of 2026-11-17, and in the global constraints, which now say so.

## Amendment, 2026-11-17: an extension's open work and the close (M4's close fix)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4's close fix [its mutation log](../m4-close-fix-mutation-log.md), from M4 slice 5's FTS5 suite, its review and the fix's own (Opus). A loaded extension's virtual tables close as SQLite's own modules do: `sqlite3_close`
disconnects them first ([ADR-0012](0012-explicit-close-and-the-handle.md), amended). A statement, a
blob or a backup an extension leaves open on the connection makes `close-database!` refuse, and is
the extension's, with what SQLite's refused close does to it: the close vouches only for what
chez-sqlite3 tracks ("Vouch only for ours"). Slice 4's Extensions entry says so.
