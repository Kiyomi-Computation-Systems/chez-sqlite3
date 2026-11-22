# 0.1.1's Mac run on the release branch

The release's step 2 (the M5 plan, §4.9): the release branch's `make test` on the Mac, with
Apple's library and with Homebrew's, before the squash merge and the tag. The branch is
`release-0.1.1`: CHANGELOG.md's `[0.1.1]` entry, `Akku.manifest` at 0.1.1, and both clone lines
at `--branch v0.1.1`. It is also the examples' first run on a Mac: `test-docs` runs each of
`docs/examples.md`'s five programs, and the file example twice.

These are its commands, for zsh, in your chez-sqlite3 clone. They carry no comments. They write
under `build/rel011-mac/`, which git ignores, and `rel011-mac.tgz` at the clone's root.

## 1. Get the release branch

Start from a clean tree: `git status --short` should print nothing that git tracks. The
`git log` line should be the branch's head, the one PR #64 shows.

```
git status --short
git fetch origin release-0.1.1
git switch release-0.1.1
git pull --ff-only
git log --oneline -1
mkdir -p build/rel011-mac
sw_vers | tee build/rel011-mac/macos.txt
```

## 2. Apple's library

```
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
make test 2>&1 | tee build/rel011-mac/apple-test.txt
```

## 3. Homebrew's library

```
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
make test 2>&1 | tee build/rel011-mac/brew-test.txt
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
```

## 4. Back to `main`, and send back

```
git switch main
tar czf rel011-mac.tgz build/rel011-mac/*.txt
```

Send `rel011-mac.tgz`. A step that fails is a result too: carry on to the next one.

## What we will read

- Each `make test` ends with `test: ran 93, passed 93, failed 0, hung 0`, as on Linux, and as
  0.1.0's run did on the Mac with each library ([its steps and results](../m5-mac/release.md)).
- `test-docs` gives `# of expected passes      191` on both, as on Linux: its rows for
  `docs/examples.md` among them, each program exiting 0 with nothing on stderr and printing its
  text block, and the file example printing the same run again. 0.1.0's Mac run gave 162 on
  each, as Linux did then.
- The libraries are the ones README.org's Status names: Apple's run's P4 line names SQLite
  3.51.0, Homebrew's 3.54.1. `macos.txt` names macOS 26. Another version is a question for the
  Status before the tag.
- Apple's run names its unavailable rows as 0.1.0's did; Homebrew's names none.
- `test-manifest` passes on both, holding the manifest, the changelog and the clone lines at
  0.1.1 together.
