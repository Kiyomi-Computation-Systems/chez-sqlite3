# M4's closing review: the code and the user's docs, the log

Evidence that each fix of the closing review's "Code" section, and its m1, holds through the
property it names, and fails without it. An Opus agent, builder C, built it from the lead's brief,
in the worktree of branch `m4cr-code`, from `main` at `34721b4`. The findings and the maintainer's
decisions of 2026-11-18 are the lead's. The plants' tools are
[plants.py](research/m4-closing-review/code/plants.py), which makes each copy on the host, and
[run-plants.sh](research/m4-closing-review/code/run-plants.sh), which runs a suite in the copies
in the container; their runs are in [plants.txt](research/m4-closing-review/code/plants.txt).

## F2: the owner check inside the section

**The defect.** `call-with-open-handle` checked the owner before its critical section alone. Chez
resumes an engine's remainder on whichever thread calls it, so a call could pass the check on the
owner's thread, expire, and make its section, the C call's, on another thread.

**The fix,** in `connection.sls`. The section reads the owner, the caller's thread id and the
handle, and checks the owner first, then the open state:

```scheme
(cond ((not (eqv? owner caller)) (list 'wrong-thread owner caller))
      ((not handle) '(closed))
      (else ...))
```

The wrong thread is answered as data, and `&sqlite-wrong-thread` raised after the section, from
the caller's `who`, as the first check raises it. The first check stays, so a wrong thread is still
refused before anything else, and the order of the refusals is the same. No signature changed.
Every caller gets the refusal as it gets the closed one, a raise after the section; the M4 sites
that wrap the call in a section of their own catch it there, as they catch the closed one.

**The rows,** in `tests/test-connection.sps`, "a remainder resumed on another thread". Each sweeps a
call at every fuel from 1 until it completes without expiring, with a fresh `:memory:` connection
for every trial, opened on the main thread. A remainder is finished on a forked thread, in slices
of 10^8 ticks, by the suite's `in-thread`, whose wait is bounded at 120 s and whose thread makes
any raise its answer. Each trial is judged by its own answer and the ids it carries, compared raw:

| Row | Before the resume | Refusal | Past the section |
|---|---|---|---|
| bare `call-with-open-handle` | nothing | wrong thread, its `who` | `ran-on-the-owner` |
| bare, closed | the owner closes | wrong thread, its `who` | its answer |
| bare, closed, depth | the owner closes | the handler at `depth-1` | `(no-raise …)` |
| `changes` | the owner closes | from `changes` | `(changed 0)` |
| `in-transaction?` | the owner closes | from `in-transaction?` | `out` |
| `step!` | the owner closes | from `step!` | `#t` |
| `prepare-statement` | the owner closes | from `prepare-statement` | `prepared` |

Each row asks for both kinds reached, a refusal and an answer past the section, and no other trial.
With the connection closed first, a section that ran on the other thread would have answered
closed, so the verbs need no stand-in to show where their section ran.

`query` and `execute-script!` were tried and left out. `query`'s sections each sit in an outer
critical section, so it passed on `main`'s code; and `execute-script!` doesn't survive an engine's
preemption (the reference), its resumed runs refused by its block.

**Red, on `main`'s code,** with the rows written first: 63 passed, 6 failed, each by three trials,
at fuels 9 to 11 for the bare rows, 10 to 12 for the counters, 21 to 23 for `step!` and 25 to 27
for `prepare-statement`:

- bare: `(9 resumed (ran-on the-thread) the-thread done closed)`, and 10 and 11;
- bare, closed, and each verb: `(raised (closed WHO message))` from the other thread.

The depth row came after the fix. It fails on `f2-before-only`, which is `main`'s check, and on
`f2-raise-inside`. **Green:** 70 passed.

## F3: the opt-in's reader takes the caller's `who`

**The defect.** `load-extension!` read the opt-in through `database-extension-loading?`, whose
owner check named itself. A remainder resumed on another thread after the first checks was refused
from `database-extension-loading?`.

**The fix.** `database-extension-loading?` takes the caller's `who` as an optional first argument:

```scheme
;; database-extension-loading? : (case-> (Database -> Boolean) (Symbol Database -> Boolean))
```

The one-argument form names itself, as before; `load-extension!` passes its own. A `who` that is no
symbol is an assertion violation first. `tests/test-public.sps` holds the private library's export
list whole, and isn't this builder's file, so the reader is the old name with a second arity, not a
new export.

**The rows,** in `tests/test-load-extension.sps`, "a remainder finished on another thread". The
sweep is F2's, with the call `load-extension!` of the default extension's path; the effect is
`chez_inits()`, read on the owner's thread after each trial:

- **a connection that didn't opt in,** on every library: each resumed trial refused from
  `load-extension!` with the owner and the caller, the init never run; or the opt-in's refusal,
  raised on the owner's thread before the expiry; both reached;
- **one that opted in,** a load row: refused from `load-extension!`, the init never run; the
  completing call loads, its init run once.

**Red,** with the F2 fix in and F3's not: 44 passed, 2 failed. In each row 49 trials, at fuels 10
to 58, were refused from `database-extension-loading?`. **Green:** 46 passed, then 47 with the
row below.

A third row holds the reader's new arity: from another thread its refusal names the `who` given;
on the owner's thread it answers the opt-in; a `who` that is no symbol, 42 or a string, is
`(not-a-who …)` from `database-extension-loading?` before the database is looked at; and a database
that is none is refused from the `who`. It fails on `f3-who-dropped` and on `f3-who-unchecked`.

The opted row first asked for a trial past the load too, as the plain row does. None came: the
load's section is the call's last, and at this trip no tick falls after it. So the row asks only for
the refusal, the completion and no other trial, and was watched failing again on `f3-no-who` and
`f3-who-dropped`.

## m1: ENABLE_LOAD_EXTENSION's round trip, chosen by its own answer

`test-native`'s round trip was chosen by native's record of `sqlite3_load_extension`, so the
no-load build printed it UNAVAILABLE, where the op answers 0 and round-trips. It is now chosen by
the op's first read, on a connection of its own, its cell's sentinel 7400:

- **21,** as Apple's answers: UNAVAILABLE printed, and a read, a set to 1 and a read asserted in its
  place, each `(21 SENTINEL)`, sentinels 7411 to 7413, as the Mac measured them;
- **anything else:** the round trip, held as the other three ops are, sentinels 7401 to 7405.

On `m4-noload`, `main`'s suite printed the round trip UNAVAILABLE; this one runs it, and passes.
Both pass 117.

## The plants

Each is a copy under `build/cr-code/`, made by `plants.py`, run by `run-plants.sh`:

| Plant | What it does | Suite, library | Result |
|---|---|---|---|
| `f2-before-only` | the section's caller read as the owner, `main`'s check | `test-connection`, Guix | 7 fail |
| `f2-closed-first` | the section's open check before its owner check | `test-connection`, Guix | 6 fail, the open bare row passes |
| `f2-caller-before` | the caller's id read before the section | `test-connection`, Guix | 7 fail |
| `f2-who-lost` | the section's refusal from `call-with-open-handle` | `test-connection`, Guix | 7 fail |
| `f2-raise-inside` | the wrong thread raised inside the section | `test-connection`, Guix | 1 fail, the depth row: `depth-2` |
| `f3-no-who` | `load-extension!` reads the opt-in without its `who` | `test-load-extension`, Guix; `m4-noload` | 2 fail, the sweeps; 1, the plain sweep |
| `f3-who-dropped` | the reader takes a `who` and names itself | `test-load-extension`, Guix; `m4-noload` | 3 fail; 2 |
| `f3-who-unchecked` | the reader's `who` left unchecked | `test-load-extension`, Guix; `m4-noload` | 1 fail, the arity's row; 1 |
| `m1-misuse-left` | op 1005 answers 21, its cell left | `test-native`, Guix and `m4-noload` | the 21 branch green |
| `m1-misuse-writes` | op 1005 answers 21, its cell written 0 | `test-native`, Guix | the 21 row fails |
| `m1-set-ignored` | a set of op 1005 answers 0 and sets nothing | `test-native`, Guix and `m4-noload` | the round trip fails |

`f2-closed-first` leaves the open bare row passing, as it should: with the connection open, the
order inside the section changes nothing. The `m1` plants wrap native's binding, so
`test-native`'s rows that read native's source, and its load rows that set the op, fail beside the
target row; only the target row is the plant's reading. The 21 branch can run green only on a plant
off a Mac.

## The docs and the comments

`docs/reference.md`:

- **DYLD,** F5's list: the Extensions intro names the file by its absolute path; the path's
  paragraph says the loader takes an absolute path as it is on Linux, and that on a Mac
  `DYLD_LIBRARY_PATH` sends it to a file of the same name in its folders first; the trust
  paragraph adds that `DYLD_LIBRARY_PATH` must name only folders you trust; "The library" reports
  on the library in use; `sqlite-library-path` is the path given to the loader, with the Mac's
  caveat; `sqlite-library-source` lists every source and links the new part; and
  `sqlite-extensions-unavailable?` links it.
- **"Which SQLite",** a `####` part under "## The library", before its first entry, since a `###`
  heading is an entry to `test-reference`: the override, discovery's three lists, the checks, and
  the Mac's caveat. No `scheme run` block was added.
- **F1:** `call-with-database`'s engine note names an extension's leftover statement as a way its
  close fails.
- **F4:** a setup that fails the same way on two loads in turn, beside a held row, gives its
  reason the first time, and SQLite's text alone the second.

The comments and messages F5 lists: `discovery.sls`'s override refusal says chez-sqlite3 loads the
path "with no search of its own", and its header that the path chosen is what the loader is given;
`extension.sls`'s check 4 and its refusal's message no longer say an absolute path keeps the loader
out; `report.sls`'s `sqlite-library-path` is the path given to the loader, with the Mac's caveat.
No suite reads a message.

## Green, the libraries and the gate

`make test`, on the final tree, in the container, each library's version read before its run:

| Library | Suites | `test-connection` | `test-load-extension` | `test-native` |
|---|---|---|---|---|
| Guix's 3.53.1 | 81 of 81 | 70 | 47 | 117 |
| `m3-floor`, 3.45.1 | 81 of 81 | 70 | 47 | 117 |
| `m4-current`, 3.54.1 | 81 of 81 | 70 | 47 | 117 |
| `m4-noload`, 3.54.1 | 81 of 81 | 70 | 47 | 117 |

`test-docs` passed 107 and `test-reference` 22 on each. On `m4-noload` the run printed 51
UNAVAILABLE lines, as `main` did: the round trip's line is gone, and the opted sweep's load row
adds one. No lane printed the 21 branch's line.

`make test-memory` on Guix's library, each time from the gate's `time:` line, beside `main`'s
suites timed the same way on this machine:

| Suite | This tree | `main`'s suite |
|---|---|---|
| `test-connection` | 17 s | 16 s |
| `test-load-extension` | 20 s | 16 s |
| `test-native` | 22 s | |
| `test-docs` | 39 s | |
| `test-reference` | 12 s | |

Every suite passed, none slow.

## For the records

The lead's to edit; this builder edited none of them.

- **ADR-0012, amended:** `call-with-open-handle` checks the owner again inside its section, first,
  the thread id read there, answers the wrong thread as data, and raises `&sqlite-wrong-thread`
  after the section from the caller's `who`. Its reason: Chez resumes an engine's remainder on
  whichever thread calls it, so the calling thread can change across an expiry.
- **`global-constraints.md`,** "Connections, threads and conditions": the same rule, beside "Every
  verb checks, in order".
- **`AGENTS.md`,** "Chez and the FFI": a remainder goes on on whichever thread resumes it, so a
  check of the calling thread vouches only for the section it is made in.
- **`traps.md`:** the same, reproduced by `f2-before-only` against `test-connection`, and by A's
  `probes/handle-other-thread.sps`.
- **ADR-0013, decision 2, and ADR-0021, decision 6:** `load-extension!` reads the opt-in with its
  own `who`, through `database-extension-loading?`'s second arity.
- **ADR-0001 or ADR-0005, and `global-constraints.md`'s "A suite's rows for what a library may
  lack":** `test-native`'s `ENABLE_LOAD_EXTENSION` round trip is chosen by the op's own first
  answer, 21 on Apple's library, not by native's record.
- **F5's records,** as the findings list them: ADR-0002:53-54, :79 and :87-89;
  `global-constraints.md`:79-80; ADR-0021:251-253; and the plan:214-215.
- **`progress.md`:** the close-out.

## Traps

- **The main thread's `get-thread-id` is 0.** A rename of thread ids over a whole value, as
  `test-connection`'s `ids` does, renames every 0 in it: the first draft of the `changes` row
  read `(changes db)`'s 0 as `main`. Reproduce: in a sweep that renames, let the call answer 0.
  The rows now compare the ids raw and rename only to show a failing trial.
- **No remainder past `load-extension!`'s load at the high trip.** Its section is the call's
  last, and no tick falls after it, so a sweep that asks for a trial past it fails on correct code.
  Slice 4's note that a high trip hides a remainder past the last section is the same fact.
