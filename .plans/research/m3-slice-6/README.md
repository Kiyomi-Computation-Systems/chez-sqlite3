# What M3 slice 6 measured

Six probes, run 2026-11-16 in the Guix container on Chez 10.4.0, from the repository's root, on
Guix's 3.53.1 unless the command sets the floor's library, 3.45.1. Their output is in
[output.txt](output.txt), each after the command that made it. The builders ran them first from
the worktree's git-ignored `build/`; the lead reran each here. The memory job's measured input
for part C is beside them.

## The interrupt (part A)

- **A watchdog under Valgrind** ([prepare-gate.sps](prepare-gate.sps)). A watchdog thread
  interrupts as fast as it can while the owner prepares 4 MB of comments.
  - Under Valgrind it sent no interrupt during any of three prepares, each about 3.8 s. Valgrind
    runs one thread at a time, and a thread running C keeps it.
  - Plain, each prepare stopped in about 170 ms.
  - Across the slice's runs: none of 15 stopped under Valgrind, and 8 of 9 plain.
- **The suites' device** ([prepare-mem.sps](prepare-mem.sps)). Each round the watchdog takes
  SQLite's memory mutex, `SQLITE_MUTEX_STATIC_MEM`, sleeps 1 ms holding it, interrupts, then lets
  it go. The owner prepares 900,015 characters of `select 1 in (1, 1, …)`, whose items each
  allocate. The owner blocks at its next allocation inside SQLite, so Valgrind runs the watchdog:
  all three prepares stopped in its first round. It needs SQLite's memory statistics on.
- **A critical section and collections** ([section.sps](section.sps), no SQLite):
  - a collect request made inside a section waits for its end;
  - `sleep` and `with-mutex` inside a section block as usual;
  - another thread's `collect-rendezvous` waits for the section to end.

  So a watchdog that held the mutex inside a section would keep the owner's collections waiting,
  then let the mutex go before the prepare blocked: in the builder's gated runs, the long prepare
  ran unstopped every time.
- **Probe P5, direct** ([p5-direct.sps](p5-direct.sps)). `sqlite3_interrupt` on a connection
  that `sqlite3_close` has freed. Valgrind reports "Invalid write of size 4 at sqlite3_interrupt",
  408 bytes inside a freed block of 840 on 3.53.1, and of 792 at the floor. **This probe writes
  into freed memory: run it only under Valgrind, as the command shows.** The gate's race row
  can't reach that write: its plant hands Chez a cleared handle, and Chez refuses it before C
  (ADR-0019, amended in M3 slice 6).

## Contention (part B)

- **A deferred transaction's first write** ([deferred-first-write.sps](deferred-first-write.sps)).
  Two WAL connections on one thread. The holder is in `BEGIN IMMEDIATE` with a write; the waiter,
  under a 1500 ms busy timeout, begins deferred and writes. With nothing read, its write waited
  1502 ms, then answered `busy`, extended `busy`. After a `select`, the same write answered `busy`
  in 0 ms. Each left the transaction open. Alike on both libraries (ADR-0017, amended in M3
  slice 6).
- **A forked thread's uncaught raise** ([thread-removes-dir.sps](thread-removes-dir.sps)). A
  thread raises past everything, with `make-process-temp-directory`'s directory made. The probe
  printed `(before #t)`, then `(after #f)`, and exited 0: the thread ran the inherited base
  exception handler, whose hook removed the directory under the main thread.

## The memory job's shards (part C)

[memory-shard-input.md](memory-shard-input.md), prepared by the M2 session from six CI runs'
`memory` logs:
- each suite's gate time, normalised by its run's runner factor, the median suite's ratio;
- a projection: one job past 45 minutes on the slower runners, and two shards each about 23 to 29
  minutes;
- a balanced split, the starting point for part C's two lists.
