# ADR-0008: The floors have one source, `packaging/floors.sexp`

- **Status:** Accepted (the harness plan, 2026-11-13); amended 2026-11-13 with what M0 slice 2
  built ([amendment](#amendment-2026-11-13-what-m0-slice-2-built)), the workflow rules
  ([amendment](#amendment-2026-11-13-the-workflow-rules-m0-slice-4)), and the SQLite floor's numeric
  forms ([amendment](#amendment-2026-11-13-the-sqlite-floors-numeric-forms-m0s-closing-review))
- **Date:** 2026-11-13
- **Scope:** every statement of the Chez and SQLite floors
- **Related:** chez-curl ADR-0016, which this copies · [ADR-0001](0001-bind-libsqlite3-directly.md)
  (the Chez floor) · [ADR-0003](0003-sqlite-floor-3-45-1.md) (the SQLite floor)

## Context

A floor gets written in several places: the code that enforces it, the README that promises it,
and CI, which builds at it. When those places drift apart, the README promises a version the code
refuses, or CI tests a version nobody supports. chez-curl also found that a job-level `env:` could
redefine a floor that CI wrote as a variable, and a text check couldn't see it.

## Decision

1. **`packaging/floors.sexp` holds the floors** as one datum: `((chez "10.4.0") (sqlite "3.45.1"))`.
   The keys are exactly `chez` and `sqlite`, in that order. Each version is three numbers of ASCII
   digits, with no leading zero.
2. **`make check-floors` holds the prose to the file,** and `make test` runs it. README.org's
   `** Requirements` section must hold the list lines the file calls for.
3. **CI states no floor.** `scripts/ci/floor.sh NAME` prints one floor from the file, failing
   closed unless the file has exactly one well-formed entry for NAME. Build scripts read their
   floor through it. `check-floors` fails if any workflow line holds a floor's version text.
4. **The code is held to the file by behaviour, not text.** The SQLite check must accept 3.45.1
   (3045001) and refuse 3.45.0 (3045000), with both rows built from the file. The Chez floor's
   check is designed with brief D1.
5. **`check-test-fails` plants a README that disagrees with the file,** and `make test` must fail
   on it, naming the line.

### Rejected

- **Generating the code's floors from the file.** A library contains its own code (AGENTS.md).
  Checking behaviour gets the same guarantee.
- **Floors as CI variables.** A job can redefine one, and no text check sees it.

## Consequences

- **Changing a floor edits** the file, the README's lines, the code's constant, and the literal
  test rows that name the old floor. Each place left behind fails by name.
- **CI's cache keys hash the file** with each build script, so changing a floor rebuilds.

## Amendment, 2026-11-13: what M0 slice 2 built

- **The Chez floor's check is built** (decision 4): `tests/test-require-threaded.sps` builds rows
  from the file's Chez floor, which it must accept, and keeps literal rows that it must refuse:
  10.3.0, 10.3.9 and pre-releases of 10.4.0. Brief D1 settled that a threaded Chez is required
  (ADR-0001's amendment).
- **The SQLite floor's check comes with loading, in M1:** 3.45.1 accepted, 3.45.0 refused, rows
  from the file.
- **`check-floors` holds README.org only,** and refuses while a `.github/workflows` directory
  exists, until slice 4 writes the workflow rules of decision 3. A workflow can't be added with
  the rules forgotten.
- **"Each place left behind fails by name" was too strong.** It holds for the file, README.org,
  `require-threaded`'s minimum and the suites' rows. The decision records state their floors too,
  but a record is changed by a new record, not kept in step. AGENTS.md and the global constraints
  stated the floors with nothing to check them; they now point at the file and state none.

## Amendment, 2026-11-13: the workflow rules (M0 slice 4)

- **Decision 3's rules are built,** replacing slice 2's tripwire. `make check-floors` takes the
  workflow directory as its third argument, `.github/workflows`, and requires:
  - the directory to exist, not as a symbolic link, to hold a file, and to hold `ci.yml` directly
    in it. Every file under it, in subdirectories too, is held;
  - no line of any of them to contain either floor's version text, whatever the line is: a step,
    a cache key, a comment;
  - no line to hold a backslash after a double quote. YAML reads escapes there, so
    `"3\x2e45\x2e1"` spells a floor without its text;
  - no line to hold an odd number of double quotes. A double-quoted string left open goes on
    over the lines after it, where an escape is no longer after a quote on its own line. The
    slice's review found this, along with the corrections below.
- **chez-curl's two env keys and `node-version` are left out:** no env key here ever held a
  floor, and there is no setup-node.
- **Its explicit-key, alias, non-ASCII and tab rules were first left out too, wrongly.** The
  reason given was that they protected rules about keys, and we had none. We have two: the
  `uses` key that `check-action-pins.sh` reads, and the workflow's own keys. The review showed an
  explicit `? uses` key hiding an unpinned action from the pin check, and a quoted `"if"` hiding
  a skipped step. Those rules now live in `tests/check-ci.sh`, beside the key rules they protect
  (ADR-0005's slice 4 amendment).
- **The text is searched, not parsed.** An expression that builds a version, such as GitHub's
  `format()`, isn't seen. Nothing would read it: `scripts/ci/build-chez.sh` takes no version.
- **`scripts/ci/floor.sh` is built.** It prints the `chez` or `sqlite` floor from the file and
  fails closed on a malformed one. `build-chez.sh` reads the Chez floor through it, and the
  Chez caches are keyed by a hash of the file and the build script.
- **Tests:** `tests/test-check-floors.sps` holds each rule on texts and fixture trees, and runs
  `floor.sh` and `scripts/ci/check-action-pins.sh` in temporary trees.

## Amendment, 2026-11-13: the SQLite floor's numeric forms (M0's closing review)

- **Decision 3 covers every form a floor is written in.** The review found that SQLite writes its
  floor in two forms that hold no `3.45.1`: the version number, `3045001`
  (`SQLITE_VERSION_NUMBER` and `sqlite3_libversion_number`), and the amalgamation's file name,
  `sqlite-amalgamation-3450100.zip`. Two such lines in the `main` job passed `check-floors` and
  `check-ci`. M1's `floor` lane is where both would be written.
- **`check-floors` now refuses both,** computed from the SQLite floor in the file: X·1000000 +
  Y·1000 + Z, and X·1000000 + Y·10000 + Z·100. Neither is written in the code. Each is found only
  as a whole run of digits, with no ASCII letter or digit beside it, since a hex digest holds
  such runs inside longer ones. The problem names the file, the line, the form and the floor.
- **The Chez floor has no numeric form.** Chez names its releases by the dotted version alone,
  in its tarball (`csv10.4.0.tar.gz`) and its tag (`v10.4.0`).
- **Tests:** `test-check-floors` holds each form at every position, beside each kind of
  neighbour, and on a fixture whose own floor is 3.46.0, where 3.45.1's forms pass
  ([the log](../m0-review-mutation-log.md)).
