# ADR-0009: Written fresh, as `(chez-sqlite3)`, with nothing copied from Thunderchez

- **Status:** Accepted (the maintainer, 2026-11-13). Amended 2026-11-14: what `check-seam` reads
  ([amendment](#amendment-2026-11-14-what-check-seam-reads-m1s-plan)).
- **Date:** 2026-11-13
- **Scope:** chez-sqlite3's library names and the provenance of its code
- **Settles:** brief §2.1 and §2.3
- **Related:** [the Thunderchez assessment](../chez-sqlite-thunderchez-assessment.org)

## Context

- **The assessment recommended a focused fork:** extract Thunderchez's useful code from
  `sqlite3.sls`, keep its Apache-2.0 notice, and fix the defects it listed. Its public library is
  `(sqlite3)`.
- **Nearly every function the assessment examined needs rewriting** for one of those defects:
  loading, open, prepare, finalize, the 64-bit declarations, errors, transactions.
- **This project is BSD-3.** Copying Apache-2.0 code would carry its notice obligation.
- **The house discipline is test-first.** A test is finished when it has been watched failing.

## Decision

1. **The public library is `(chez-sqlite3)`.** Internals live under `(chez-sqlite3 private …)` and
   never escape it. The test helpers are `(chez-sqlite3-testing)`, in `tests/`.
2. **No Thunderchez code is copied.** Its API ideas, such as a fold over rows, a transaction form
   and a distinct SQL null, are fair to take. Its text is not. Thunderchez is not vendored,
   fetched or imported.
3. **Each defect the assessment lists becomes a test,** watched failing against a planted copy of
   that defect before the fix counts.

### Rejected

- **Depending on Thunderchez.** Its global library name, its dependency tree and its defects would
  sit inside our boundary (the assessment).
- **A focused fork.** Rewriting costs the same, test-first means the code is written fresh anyway,
  and the fork would carry an Apache-2.0 notice.
- **`(sqlite3)`.** It clashes with Thunderchez's on a shared library path.
- **`(sqlite)`.** It is generic enough to clash too.

## Consequences

- **`check-seam` (M1) enforces the private boundary:** nothing public imports a
  `(chez-sqlite3 private …)` library except `(chez-sqlite3)` itself.
- **The assessment's defect list is a test plan** for M1 and M2.

## Amendment, 2026-11-14: what `check-seam` reads (M1's plan)

Proposed in M1 slice 0, for the maintainer's acceptance with its PR.

- **`check-seam` reads `src/` alone.** The rule is about what the library exposes:
  under `src/`, only `(chez-sqlite3)` and the `(chez-sqlite3 private …)` libraries exist, and no
  library but `(chez-sqlite3)` and the private ones imports a private one.
- **Tests and the test helpers may import private libraries.** `(chez-sqlite3-testing)` and
  `test-counters` already import `(chez-sqlite3 private counters)`, and each private library's
  suite imports the library it tests. The plants and the probes call `foreign-alloc` directly
  (M0's closing review).
- **It is chez-curl's `check-seam`, trimmed to one family.** It keeps chez-curl's rules on
  `(chezscheme)` imports, the import allowlist, the names only some libraries may import, and
  exports. Its rule (d), that every library belongs to a family, becomes the boundary rule above.
  It drops rules (a), (b) and (j), about chez-curl's second family and its escape hatch. Each dropped
  rule is listed, with what it protected, in the slice that copies it (the M1 plan, §3.5).
