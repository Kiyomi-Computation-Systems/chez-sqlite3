# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 slice 0, the records,** merged as PR #1. ADR-0001 to ADR-0009 are all accepted.
- **M0 slice 1, the container,** is open on `m0-slice-1-container`. Its first commit holds slice
  0's close-out, the first entries in [traps.md](traps.md), and a correction to AGENTS.md's rule
  on evaluation order, with [the measurement behind it](research/evaluation-order/). Next, it
  measures what chez-curl's Guix pin gives for Chez, SQLite, gcc and Valgrind, before anything is
  copied (harness plan §6).
- **Open:** brief D1 to D7. D1 (threaded Chez) and D7 (the Mac's SQLite) are due in M1.

## Close-outs

### 2026-11-13 — M0 slice 0: the records (PR #1, `d998b3e`)

- **Measured first:** on the host, Guix's Chez can't load the system's `libsqlite3.so.0` by its
  soname, and that library is 3.37.2, below the floor. Binding NaN returns `SQLITE_OK` and stores
  NULL. `utf8->string` replaces invalid bytes with U+FFFD without raising. What the Guix pin gives
  is slice 1's first measurement.
- **Built:**
  - the brief and the harness plan;
  - ADR-0001 to ADR-0009, with 0001 and 0002 accepted after the maintainer reviewed them;
  - `global-constraints.md` and this ledger;
  - AGENTS.md, cleaned of chez-curl's leftovers.
- **Checked:** every relative link in `.plans` resolves, and every record number cited exists.
  The check flagged one citation of a sibling's record that read as ours, and a read found three
  more.
- **Reviewed:** by the maintainer. M0's adversarial review comes at its end (harness plan §6).
- **CI:** none yet.
- **Subagents:** one, Sonnet: an inventory of chez-curl's harness, 171k tokens, 30 tool calls,
  4 min. Its claims were checked against the files before the harness plan used them, and they
  held: the Makefile's targets, `.gitignore`, the container's exports, the counters, the suite
  count, and `.github`.
- **Learned** ([traps.md](traps.md)):
  - A probe follows the test rules. The value probe's first run saw `step` before `bind`.
    Measuring why showed that AGENTS.md's inherited rule on evaluation order was wrong on this
    Chez; slice 1 corrects it.
  - A global replace hits the sentence that defines its marker.
  - Name the repository in every citation of a sibling's record.
