# M5's Mac run on the release branch

The release's step 2 (the M5 plan, §4.9): the release branch's `make test` on the Mac, with
Apple's library and with Homebrew's, before the squash merge and the tag. The branch is
`m5-release`, PR #59: CHANGELOG.md's `[0.1.0]` entry, `Akku.manifest` at 0.1.0, and both clone
lines at `--branch v0.1.0`.

These are its commands, for zsh, in your chez-sqlite3 clone. They carry no comments. They write
under `build/m5rel-mac/`, which git ignores, and `m5rel-mac.tgz` at the clone's root.

## 1. Get the release branch

Start from a clean tree: `git status --short` should print nothing that git tracks. The
`git log` line should be the branch's head, the one PR #59 shows.

```
git status --short
git fetch origin m5-release
git switch m5-release
git pull --ff-only
git log --oneline -1
mkdir -p build/m5rel-mac
```

## 2. Apple's library

```
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
make test 2>&1 | tee build/m5rel-mac/apple-test.txt
```

## 3. Homebrew's library

```
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
make test 2>&1 | tee build/m5rel-mac/brew-test.txt
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
```

## 4. Back to `main`, and send back

```
git switch main
tar czf m5rel-mac.tgz build/m5rel-mac/*.txt
```

Send `m5rel-mac.tgz`. A step that fails is a result too: carry on to the next one.

## What we will read

- Each `make test` ends with `test: ran 93, passed 93`, as on Linux, and as slice 4's walk did
  on the Mac with each library.
- Apple's run names its unavailable rows as before: the tell's, the load rows' and the memory
  check's. Homebrew's names none.
- `test-manifest` passes on both, holding the manifest, the changelog and the clone lines at
  0.1.0 together.

## What it gave

On `10a9569`, 2026-11-21 ([outputs](out/release/)): `make test` ran 93 and passed 93 with Apple's
library and with Homebrew's. Apple's run named the same 140 rows unavailable as the run after
M4's closing review, line for line, the one suite added since being `test-site-testing`; Homebrew's
named none. `test-manifest` passed on both. The release's later fix, PR #60, changed only text,
and the maintainer chose to skip a rerun on it ([the release](../m5-release/README.md)).
