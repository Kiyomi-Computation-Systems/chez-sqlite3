# describe.py: the log's mutation tables, built from build/mut2/results.txt.
import collections, sys
D = collections.OrderedDict([
 ('cv-mutant', "check-variadic's own mutant: the convention removed from `sqlite3_db_config`'s form"),
 ('table-dbc-plain', "the table's `sqlite3_db_config` row made plain"),
 ('table-dbc-safe', "the same row made collect-safe"),
 ('load-plain', "the load bound plain, in `native.sls` alone"),
 ('load-plain-both', "the load bound plain, its row made plain too"),
 ('bind-optional-refuses', "`bind-optional` refusing an absent entry point, `missing-api`"),
 ('available-true', "`load-extension-available?` always `#t`"),
 ('available-false', "`load-extension-available?` always `#f`"),
 ('decoy-dbc-inverted', "the decoy's `DECOY_LACKS_sqlite3_db_config` inverted"),
 ('decoy-free-inverted', "the decoy's `DECOY_LACKS_sqlite3_free` inverted"),
 ('decoy-load-inverted', "the decoy's `DECOY_LACKS_sqlite3_load_extension` inverted"),
 ('optional-moved', "`optional-entries` joined to `every-entry`, moved (`optional-entries` empty)"),
 ('optional-appended', "`optional-entries` joined to `every-entry`, appended (kept in both)"),
 ('const-defensive-1011', "`sqlite-dbconfig-defensive` 1011"),
 ('const-ele-1006', "`sqlite-dbconfig-enable-load-extension` 1006"),
 ('const-dml-ddl-swapped', "`DQS_DML` and `DQS_DDL` swapped"),
 ('dbc-args', "`sqlite3_db_config`'s arguments `(uptr int uptr uptr)`"),
 ('dbc-after-3', "`sqlite3_db_config` with a count of 3"),
 ('dbc-after-3-both', "a count of 3 in native and in `convention-forms`"),
 ('dbc-safe', "`sqlite3_db_config` `__collect_safe` beside its count"),
 ('free-safe', "`sqlite3_free` `__collect_safe`"),
 ('free-noop', "`sqlite3_free` doing nothing"),
 ('bind-optional-no-check', "`bind-optional` without its `foreign-entry?`"),
 ('available-by-entry', "`load-extension-available?` from a second `foreign-entry?`"),
 ('order-free-first', "`sqlite3_free` bound before `sqlite3_db_config`"),
 ('order-optional-first', "the optional entry point bound before the required ones"),
 ('table-optional-record', "the optional row's records without \"an optional entry point\""),
 ('table-proto-tail', "the prototype with the variadic tail's `int` and `int*` for `...`"),
 ('table-proto-3', "the prototype with three named parameters"),
 ('forms-no-variadic', "`convention-forms` without `variadic`"),
 ('convention-of-membership', "`convention-of` reading any list headed `__varargs_after` as variadic"),
 ('convention-of-safe-ignored', "`convention-of` ignoring `__collect_safe` beside the count"),
 ('fender-required-only', "the fender allowance for `bind-required` alone"),
 ('fender-two-each', "two fender mentions allowed a binder"),
 ('reader-skips-optional', "the reader skipping forms inside `bind-optional`"),
 ('violations-skip-plain', "the convention not compared for plain rows"),
 ('violations-skip-variadic', "the convention not compared for variadic rows"),
 ('map-no-convention', "the map rule's variadic convention dropped"),
 ('map-no-after', "the map rule's count dropped"),
 ('map-no-without-ellipsis', "the map rule's `variadic-without-ellipsis` dropped"),
 ('map-no-tail-argument', "the map rule's argument after the named ones dropped"),
 ('map-inverted', "the map rule's convention test inverted"),
 ('generic-default-1', "`_Generic`'s default answering 1"),
 ('constant-row-dropped', "a constant's row dropped from `test-constants`"),
 ('decoy-parts-moved', "the parts: `sqlite3_db_config` moved to `-real`"),
 ('probe-always-true', "the probe printing `#t` whatever native records"),
 ('probe-flag-ignored', "the probe ignoring `--extension-loading`"),
 ('all-builds-no-optional', "no lacking build for the optional entry points"),
 ('decoy-dbc-not-variadic', "the decoy's `sqlite3_db_config` defined with named `int` and `int*`"),
 ('ci-dropped', "`check-variadic` dropped from `ci.yml`'s line"),
 ('ci-and-check-ci-dropped', "dropped from `ci.yml` and `check-ci.sh` together"),
 ('ci-order', "`check-variadic` before `check-test-fails` in `ci.yml`"),
 ('make-phony', "`check-variadic` out of `.PHONY`"),
 ('make-no-help', "its help line dropped"),
 ('make-no-shard', "`test-check-variadic` in neither shard"),
 ('int-fill-zero', "`call-with-int-cell`'s fill always 0"),
 ('int-never-freed', "its cell never freed"),
 ('int-read-before', "its cell read before PROC runs"),
 ('int-range-chez', "its range Chez's foreign int's, to 2^32-1"),
 ('int-range-dropped', "its range check dropped"),
 ('int-range-inexact', "an inexact integer fill taken"),
 ('int-check-in-section', "the fill checked inside the block's extent"),
 ('optional-in-main', "the optional prototype asked in the one compile again"),
 ('optional-in-main-hdr', "the same, with the review's stand-in header first on the path"),
 ('control-hdr', "no plant: the stand-in header first, on Guix's library, which has the entry point"),
 ('rule-inverted', "the rule: a failed compile unavailable where native records the entry point there"),
 ('rule-inverted-hdr', "the same, with the stand-in header first"),
 ('rule-asks-always', "the rule asking native whatever the compile did"),
 ('loader-steps-1', "the FIFO row's loader bound one 10 ms wait: its hung branch"),
 ('loader-steps-1-no-release', "the same, without the release before the close"),
 ('loader-steps-1-silent-collector', "the hung branch, the collector never releasing the FIFO"),
 ('loader-steps-1-silent-collector-no-release', "the same, without the hung branch's release"),
 ('rename-sweep', "a sweep of `test-conventions` renamed"),
 ('marker-in-comment', "a comment in `native.sls` writing the convention's text"),
 ('list-stale', "the script's list naming a stale count, 74 arguments"),
])
V = collections.OrderedDict([
 ('once-dropped', '"exactly once" dropped'), ('left-dropped', '"stands on none after" dropped'),
 ('changed-dropped', '"one line changed" dropped'), ('static-any-status', 'the static step taking any failing status'),
 ('static-no-names', "the failing tests' names not compared"), ('static-no-violations', 'the violations not compared'),
 ('uname', 'the machine from `uname`'), ('no-tarm64osx', '`tarm64osx` not Apple arm64'),
 ('arm64-no-evidence', 'arm64: no evidence asked, a named test or a death'), ('arm64-exit-0', 'arm64: exit 0 taken, with a FAIL line'),
 ('arm64-hang', 'arm64: a hang taken, after a FAIL line'), ('arm64-any-name', 'arm64: any failing name taken, not only one through `sqlite3_db_config`'),
 ('control-no-count', "the control without the runner's count"), ('control-no-fail-check', 'the control without the FAIL check'),
 ('control-no-status', 'the control without its status'), ('srfi-unchecked', '`build/scheme-libs/srfi` unchecked'),
 ('runs-in-tree', 'the suites run in the tree, not the copy'), ('no-timeout', 'the suites run without TIMEOUT'),
 ('other-fails', "another machine's failure failed, not reported"), ('machine-status-unread', "the machine question's status unread"),
 ('machine-loose', 'the machine read loosely, its last line'), ('usage-dropped', 'the usage check dropped'),
 ('last-exit-0', 'a failing run exiting 0'), ('mutation-not-written', 'the mutation not written to the copy'),
 ('static-runs-native', 'the static step running `test-native`'),
])
short = {'test-conventions': 'conventions', 'test-constants': 'constants', 'test-native': 'native',
         'test-library-loading-decoys': 'decoys', 'test-library-loading-real': 'real',
         'test-library-loading-missing': 'missing', 'test-check-ci': 'check-ci', 'test-check-variadic': 'check-variadic'}
res = collections.OrderedDict()
cells = collections.OrderedDict()
for path in sys.argv[1:]:
  for line in open(path):
    w = line.split()
    if len(w) < 4: continue
    name, what = w[0], w[1]
    if what.startswith('make-'):
        cell = '`make %s` exit %s' % (what[5:], w[3])
    else:
        cell = '%s %s%s, %s' % (short.get(what, what), w[7], '' if w[3] != '0' else ' (exit 0)', w[8])
    cells[(name, what)] = cell
for (name, what), cell in cells.items():
    res.setdefault(name, []).append(cell)
def row(i, prefix, name, text):
    cells = res.get(name, ['NOT RUN'])
    print('| %s%02d | %s | %s |' % (prefix, i, text, '; '.join(cells)))
print('| Mutation | Guards | Failed rows, and time |\n|---|---|---|')
for i, (k, t) in enumerate(D.items(), 1):
    row(i, 'M', k, t)
print()
print('| Mutation | Guards | Failed rows of check-variadic, and time |\n|---|---|---|')
for i, (k, t) in enumerate(V.items(), 1):
    row(i, 'V', 'cv-' + k, t)
missing = [n for n in res if n not in D and not (n.startswith('cv-') and n[3:] in V) and n != 'red-final']
print('unlisted:', missing, file=sys.stderr)
