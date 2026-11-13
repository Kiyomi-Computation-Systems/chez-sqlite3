# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 slice 0, the records,** is open on `m0-slice-0-records`. It holds the brief, the harness
  plan, AGENTS.md's cleanup, ADR-0001 to ADR-0009, these global constraints and this ledger.
  All nine are Accepted; the maintainer accepted ADR-0001 (no C shim, the Chez floor) and
  ADR-0002 (discovery) on 2026-11-13.
- **Next: M0 slice 1, the container.** It measures what chez-curl's Guix pin gives for Chez,
  SQLite, gcc and Valgrind before anything is copied (harness plan §6).
- **Open:** brief D1 to D7. D1 (threaded Chez) and D7 (the Mac's SQLite) are due in M1.

## Close-outs

None yet.
