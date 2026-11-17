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
  - Across the slice's runs, these three and part A's log's: with no sleep, none of 15 stopped
    under Valgrind, and 8 of 9 plain. A watchdog sleeping 1 ms a round (part A's log) stopped none
    of 3 under Valgrind, and none of 3 plain.
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
- **The hold's window allocates nothing** ([sleep-alloc.sps](sleep-alloc.sps), output in
  [sleep-alloc.txt](sleep-alloc.txt), the lead's rerun). A sleep, a foreign call and a `set!`
  allocate 0 bytes a call; `critical-section` 48 at its entry, as a `make-time` does. The probe's
  `cons` control reads 0: its operands are constants, so it is made once.
- **The lead's part A mutants** ([lead-drive-a.py](lead-drive-a.py), output in
  [lead-drive-a.txt](lead-drive-a.txt)): K1, K2, K4 and K5, run from `build/lead-mut/`.
- **Follow-up 2, the call inside the latch.** After the slice's review:
  - [a2-engine-trials.sps](a2-engine-trials.sps), output in
    [a2-engine-trials.txt](a2-engine-trials.txt): an engine sweep of `interrupt-database/with`
    on a stand-in, closing at the first expiry. On the review's plant P-a, a stand-in that only
    notes its call is never called after the close; one that spins 20 turns first is, at most
    fuels;
  - [a2-plants.py](a2-plants.py) makes the follow-up's plant copies under `build/a2/final/`, and
    [a2-run.sh](a2-run.sh) runs the suites on them plain and under the gate; their output is
    [a2-plants.txt](a2-plants.txt). Both run from the worktree's root, and the output writes
    that root as `<worktree>/` (M3's closing review).

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
