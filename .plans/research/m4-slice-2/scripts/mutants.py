# mutants.py: M4 slice 2's plants. Each mutant is a copy of the worktree under
# build/mut/NAME (tar, excluding build/, .git and .plans/research), with exact
# text edits, each checked to occur the expected number of times before it is
# written. `python3 mutants.py make NAME...` makes copies (all with no NAME);
# the runner, run-mutants.sh, runs each mutant's suites inside the container.
import os, subprocess, sys

WT = os.getcwd()  # run from the worktree's root
MUT = os.path.join(WT, 'build/mut')

NATIVE = 'src/chez-sqlite3/private/native.sls'
CONST = 'src/chez-sqlite3/private/constants.sls'
FC = 'tests/foreign-conventions.sls'
LL = 'tests/library-loading.sls'
DECOY = 'tests/decoy-libsqlite3.c'
PROBE = 'tests/refusal-probe.sps'
TC = 'tests/test-constants.sps'
CV = 'tests/check-variadic.sh'

CONV = 'tests/test-conventions.sps'
CONS = 'tests/test-constants.sps'
NAT = 'tests/test-native.sps'
DEC = 'tests/test-library-loading-decoys.sps'
REAL = 'tests/test-library-loading-real.sps'
MISS = 'tests/test-library-loading-missing.sps'
CI = 'tests/test-check-ci.sps'
TCV = 'tests/test-check-variadic.sps'

BO_TEMPLATE = """         #'(and (foreign-entry? entry)
                (fp convention ... entry (arg ...) result))))))"""

DBC_BLOCK = """  (define sqlite3-db-config
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int))))
"""
FREE_BLOCK = """  (define sqlite3-free
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_free" (uptr) void))))
"""
LOAD_BLOCK = """  (define sqlite3-load-extension
    (load-step
     (bind-optional
       (foreign-procedure __collect_safe "sqlite3_load_extension" (uptr uptr uptr uptr) int))))
"""

M = []
def mutant(name, suites, edits, targets=()):
    M.append((name, suites, edits, targets))

# --- the brief's plants -------------------------------------------------------
mutant('cv-mutant', [CONV, NAT, CONS], [(NATIVE,
    '(foreign-procedure (__varargs_after 2) "sqlite3_db_config"', '(foreign-procedure "sqlite3_db_config"')])
mutant('table-dbc-plain', [CONV, CONS], [(FC, '(uptr int int uptr) int variadic', '(uptr int int uptr) int plain')])
mutant('table-dbc-safe', [CONV, CONS], [(FC, '(uptr int int uptr) int variadic', '(uptr int int uptr) int collect-safe')])
mutant('load-plain', [CONV, NAT], [(NATIVE,
    '(foreign-procedure __collect_safe "sqlite3_load_extension"', '(foreign-procedure "sqlite3_load_extension"')])
mutant('load-plain-both', [CONV, NAT], [(NATIVE,
    '(foreign-procedure __collect_safe "sqlite3_load_extension"', '(foreign-procedure "sqlite3_load_extension"'),
    (FC, '(uptr uptr uptr uptr) int collect-safe', '(uptr uptr uptr uptr) int plain')])
mutant('bind-optional-refuses', [REAL, NAT], [(NATIVE, BO_TEMPLATE,
    """         #'(begin (required-entry entry libsqlite3-path libsqlite3-source report)
                (fp convention ... entry (arg ...) result))))))""")])
mutant('available-true', [REAL, NAT], [(NATIVE, '(if (procedure? sqlite3-load-extension) #t #f)', '#t')])
mutant('available-false', [REAL, NAT], [(NATIVE, '(if (procedure? sqlite3-load-extension) #t #f)', '#f')])
mutant('decoy-dbc-inverted', [DEC, REAL, MISS], [(DECOY, '#ifndef DECOY_LACKS_sqlite3_db_config', '#ifdef DECOY_LACKS_sqlite3_db_config')])
mutant('decoy-free-inverted', [DEC, REAL, MISS], [(DECOY, '#ifndef DECOY_LACKS_sqlite3_free', '#ifdef DECOY_LACKS_sqlite3_free')])
mutant('decoy-load-inverted', [REAL], [(DECOY, '#ifndef DECOY_LACKS_sqlite3_load_extension', '#ifdef DECOY_LACKS_sqlite3_load_extension')])
mutant('optional-moved', [CONV, DEC, REAL, MISS], [
    (LL, '"sqlite3_db_config" "sqlite3_free"))', '"sqlite3_db_config" "sqlite3_free" "sqlite3_load_extension"))'),
    (LL, "(define optional-entries '(\"sqlite3_load_extension\"))", "(define optional-entries '())")])
mutant('optional-appended', [CONV, DEC, REAL, MISS], [
    (LL, '"sqlite3_db_config" "sqlite3_free"))', '"sqlite3_db_config" "sqlite3_free" "sqlite3_load_extension"))')])

# --- the code's own sites ------------------------------------------------------
mutant('const-defensive-1011', [CONS, NAT], [(CONST, '(define sqlite-dbconfig-defensive 1010)', '(define sqlite-dbconfig-defensive 1011)')])
mutant('const-ele-1006', [CONS, NAT], [(CONST, '(define sqlite-dbconfig-enable-load-extension 1005)', '(define sqlite-dbconfig-enable-load-extension 1006)')])
mutant('const-dml-ddl-swapped', [CONS, NAT], [
    (CONST, '(define sqlite-dbconfig-dqs-dml 1013)', '(define sqlite-dbconfig-dqs-dml 1014)'),
    (CONST, '(define sqlite-dbconfig-dqs-ddl 1014)', '(define sqlite-dbconfig-dqs-ddl 1013)')])
mutant('dbc-args', [CONV, NAT], [(NATIVE, '"sqlite3_db_config" (uptr int int uptr) int', '"sqlite3_db_config" (uptr int uptr uptr) int')])
mutant('dbc-after-3', [CONV, NAT], [(NATIVE, '(__varargs_after 2) "sqlite3_db_config"', '(__varargs_after 3) "sqlite3_db_config"')])
mutant('dbc-after-3-both', [CONV, CONS], [
    (NATIVE, '(__varargs_after 2) "sqlite3_db_config"', '(__varargs_after 3) "sqlite3_db_config"'),
    (FC, "(variadic (__varargs_after 2))))", "(variadic (__varargs_after 3))))")])
mutant('dbc-safe', [CONV, NAT], [(NATIVE, '(foreign-procedure (__varargs_after 2) "sqlite3_db_config"', '(foreign-procedure __collect_safe (__varargs_after 2) "sqlite3_db_config"')])
mutant('free-safe', [CONV], [(NATIVE, '(foreign-procedure "sqlite3_free" (uptr) void)', '(foreign-procedure __collect_safe "sqlite3_free" (uptr) void)')])
mutant('free-noop', [NAT], [(NATIVE, FREE_BLOCK, """  (define sqlite3-free
    (let ((raw (load-step
     (bind-required report
       (foreign-procedure "sqlite3_free" (uptr) void)))))
      (lambda (p) (if #f (raw p)))))
""")])
mutant('bind-optional-no-check', [REAL, NAT], [(NATIVE, BO_TEMPLATE,
    """         #'(fp convention ... entry (arg ...) result)))))""")])
mutant('available-by-entry', [NAT, REAL], [(NATIVE, '(if (procedure? sqlite3-load-extension) #t #f)', '(foreign-entry? "sqlite3_load_extension")')])
mutant('order-free-first', [NAT], [(NATIVE, DBC_BLOCK + """
  ;; sqlite3-free : Natural -> Void
  ;; void sqlite3_free(void*): frees a block SQLite allocated, a load's
  ;; message, the one such block chez-sqlite3 is handed; NULL does nothing
  ;; (ADR-0021, decision 9).
""" + FREE_BLOCK, FREE_BLOCK + "\n" + DBC_BLOCK)])
mutant('order-optional-first', [NAT, REAL], [(NATIVE, DBC_BLOCK, LOAD_BLOCK + "\n" + DBC_BLOCK),
    (NATIVE, """  ;; a library without it, as Apple's is.
""" + LOAD_BLOCK, """  ;; a library without it, as Apple's is.
""")])
mutant('table-optional-record', [CONV], [(FC, '"ADR-0002 M4 amendment: an optional entry point,', '"ADR-0002 M4 amendment: an entry point,')])
mutant('table-proto-tail', [CONS, CONV], [(FC, '("sqlite3_db_config" ("int" ("sqlite3*" "int" "..."))', '("sqlite3_db_config" ("int" ("sqlite3*" "int" "int" "int*"))')])
mutant('table-proto-3', [CONS, CONV], [(FC, '("sqlite3_db_config" ("int" ("sqlite3*" "int" "..."))', '("sqlite3_db_config" ("int" ("sqlite3*" "int" "int" "..."))')])
mutant('forms-no-variadic', [CONV, CONS], [(FC, "'((plain) (collect-safe __collect_safe) (variadic (__varargs_after 2))))", "'((plain) (collect-safe __collect_safe)))")])
mutant('convention-of-membership', [CONV], [
    (FC, """  (define (convention-of conventions)
    (let loop ((rest convention-forms))""", """  (define (convention-of conventions)
    (if (exists (lambda (c) (and (pair? c) (eq? (car c) '__varargs_after))) conventions)
        'variadic
    (let loop ((rest convention-forms))"""),
    (FC, """            (else (loop (cdr rest))))))""", """            (else (loop (cdr rest)))))))""")])
mutant('convention-of-safe-ignored', [CONV], [(FC, "((equal? (cdar rest) conventions) (caar rest))",
    "((equal? (cdar rest) (filter (lambda (c) (not (and (eq? c '__collect_safe) (exists pair? conventions)))) conventions)) (caar rest))")])
mutant('fender-required-only', [CONV], [(FC, "(define binders '(bind-required bind-optional))", "(define binders '(bind-required))")])
mutant('fender-two-each', [CONV], [(FC, "(min 1 (apply + (map (lambda (d) (fender-allowance binder d))",
    "((lambda (x) (* 2 x)) (apply + (map (lambda (d) (fender-allowance binder d))")])
mutant('reader-skips-optional', [CONV], [(FC, "    (cond ((and (pair? x) (eq? (car x) 'foreign-procedure)) (list x))",
    "    (cond ((and (pair? x) (eq? (car x) 'bind-optional)) '())\n          ((and (pair? x) (eq? (car x) 'foreign-procedure)) (list x))")])
mutant('violations-skip-plain', [CONV], [(FC, "(if (equal? (convention-of conventions) (row-convention row))",
    "(if (or (eq? (row-convention row) 'plain) (equal? (convention-of conventions) (row-convention row)))")])
mutant('violations-skip-variadic', [CONV], [(FC, "(if (equal? (convention-of conventions) (row-convention row))",
    "(if (or (eq? (row-convention row) 'variadic) (equal? (convention-of conventions) (row-convention row)))")])
mutant('map-no-convention', [CONS], [(TC, """(if (and (eq? (row-convention row) 'variadic)
                                       (eqv? after n)""", """(if (and (eqv? after n)""")])
mutant('map-no-after', [CONS], [(TC, """                                       (eqv? after n)
""", """                                       #t
""")])
mutant('map-no-without-ellipsis', [CONS], [(TC, """                                    ((eq? (row-convention row) 'variadic)
                                     (list (row-name row) 'variadic-without-ellipsis))""",
    """                                    (#f
                                     (list (row-name row) 'variadic-without-ellipsis))""")])
mutant('map-no-tail-argument', [CONS], [(TC, "(> (length (row-arguments row)) n)", "#t")])
mutant('map-inverted', [CONS], [(TC, """                                    ((eq? (row-convention row) 'variadic)
                                     (list (row-name row) 'variadic-without-ellipsis))""",
    """                                    ((not (eq? (row-convention row) 'variadic))
                                     (list (row-name row) 'variadic-without-ellipsis))""")])
mutant('generic-default-1', [CONS], [(TC, "t: 1, default: 0))", "t: 1, default: 1))")])
mutant('constant-row-dropped', [CONS], [(TC, """    (sqlite-dbconfig-dqs-ddl . "SQLITE_DBCONFIG_DQS_DDL")
""", "")])
mutant('decoy-parts-moved', [DEC, REAL, MISS], [
    (LL, '"sqlite3_changes64" "sqlite3_db_config")', '"sqlite3_changes64")'),
    (LL, '"sqlite3_last_insert_rowid")', '"sqlite3_last_insert_rowid" "sqlite3_db_config")')])
mutant('probe-always-true', [REAL], [(PROBE, "(eval 'load-extension-available? native)", "#t")])
mutant('decoy-dbc-not-variadic', [DEC], [(DECOY, """int sqlite3_db_config(sqlite3 *db, int op, ...)
{
  va_list args;
  int value;
  int *cell;
  va_start(args, op);
  value = va_arg(args, int);
  cell = va_arg(args, int *);
  va_end(args);""", """int sqlite3_db_config(sqlite3 *db, int op, int value, int *cell)
{""")])

# --- the workflow and the Makefile ---------------------------------------------
LINE = 'test check-test-fails check-variadic check-dev check-clean'
mutant('ci-dropped', [], [('.github/workflows/ci.yml', LINE, 'test check-test-fails check-dev check-clean')], ['check-ci'])
mutant('ci-and-check-ci-dropped', [CI], [('.github/workflows/ci.yml', LINE, 'test check-test-fails check-dev check-clean'),
    ('tests/check-ci.sh', LINE, 'test check-test-fails check-dev check-clean')], ['check-ci'])
mutant('ci-order', [], [('.github/workflows/ci.yml', 'check-test-fails check-variadic', 'check-variadic check-test-fails')], ['check-ci'])
mutant('make-phony', [], [('Makefile', 'check-test-fails check-variadic test-memory', 'check-test-fails test-memory')], ['check-help'])
mutant('make-no-help', [], [('Makefile', "check-variadic: deps ## Remove sqlite3_db_config's variadic convention in a copy; test-conventions must fail on it, by name, and on Apple arm64 test-native too",
    'check-variadic: deps')], ['check-help'])
mutant('make-no-shard', [], [('Makefile', '  tests/test-check-variadic.sps \\\n', '')], ['check-memory-shards'])

# --- check-variadic.sh's plants, each held by test-check-variadic -----------------
def cv(name, old, new, count=1):
    mutant('cv-' + name, [TCV], [(CV, old, new, count)])
cv('once-dropped', '[ "$found" = 1 ] || stop', '[ "$found" -ge 0 ] || stop')
cv('left-dropped', 'if [ "$changed" = 1 ] && [ "$left" = 0 ]; then', 'if [ "$changed" = 1 ]; then')
cv('changed-dropped', 'if [ "$changed" = 1 ] && [ "$left" = 0 ]; then', 'if [ "$left" = 0 ]; then')
cv('static-any-status', '[ "$status" -eq 1 ] || problems=', '[ "$status" -ne 0 ] || problems=')
cv('static-no-names', '[ "$got_named" = "$want_named" ] || problems=', 'true || problems=')
cv('static-no-violations', '[ "$got_violations" = "$want_violations" ] || problems=', 'true || problems=')
cv('uname', """case $machine in
  arm64osx | tarm64osx) apple_arm64=1 ;;""", """case $(uname -s)-$(uname -m) in
  Darwin-arm64) apple_arm64=1 ;;""")
cv('no-tarm64osx', 'arm64osx | tarm64osx) apple_arm64=1 ;;', 'arm64osx) apple_arm64=1 ;;')
cv('arm64-no-evidence', '{ [ -n "$(named)" ] || [ "$status" -gt 128 ]; }', '{ true; }')
cv('arm64-exit-0', 'if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] && {', 'if [ "$status" -ne 124 ] && {')
cv('arm64-hang', 'if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] && {', 'if [ "$status" -ne 0 ] && {')
cv('control-no-count', 'if [ "$status" -eq 0 ] && [ -z "$(named)" ] && passes; then', 'if [ "$status" -eq 0 ] && [ -z "$(named)" ]; then')
cv('control-no-fail-check', 'if [ "$status" -eq 0 ] && [ -z "$(named)" ] && passes; then', 'if [ "$status" -eq 0 ] && passes; then')
cv('control-no-status', 'if [ "$status" -eq 0 ] && [ -z "$(named)" ] && passes; then', 'if [ -z "$(named)" ] && passes; then')
cv('srfi-unchecked', '[ -d "$srfi/srfi" ] || stop', 'true || stop')
cv('runs-in-root', '  ( cd "$copy" &&', '  ( cd "$root" &&')
cv('no-timeout', '"$TIMEOUT" --foreground "$TEST_TIMEOUT" "$CHEZ" --libdirs', '"$CHEZ" --libdirs')
cv('other-fails', """  ok "other: on $machine, $native_suite fails on the mutant (exit $status), $(how); reported, never failed""",
    """  bad "other: on $machine, $native_suite fails on the mutant (exit $status), $(how); reported, never failed""")
cv('machine-status-unread', 'if [ "$status" -ne 0 ] || [ -z "$machine" ]; then', 'if [ -z "$machine" ]; then')
cv('machine-loose', "NR == 1 && line ~ /^[a-z0-9]+$/", "line != \"\"")
cv('usage-dropped', '[ $# -eq 0 ] || usage', 'true')
cv('last-exit-0', """printf 'check-variadic: %d ok, %d FAILED\\n' "$pass" "$fail" >&2
exit 1""", """printf 'check-variadic: %d ok, %d FAILED\\n' "$pass" "$fail" >&2
exit 0""")
cv('mutation-not-written', 'cp "$tmp/native.sls" "$native" || stop', 'true || stop')
cv('static-runs-native', """run "$conventions"
got_named=$(named)""", """run "$native_suite"
got_named=$(named)""")

def make(names):
    os.makedirs(MUT, exist_ok=True)
    for name, suites, edits, targets in M:
        if names and name not in names:
            continue
        dest = os.path.join(MUT, name)
        if os.path.exists(dest):
            subprocess.check_call(['rm', '-rf', dest])
        os.makedirs(dest)
        subprocess.check_call('tar --exclude=./build --exclude=./.git --exclude=./.plans/research -cf - . | (cd "%s" && tar xf -)' % dest,
                              shell=True, cwd=WT)
        for edit in edits:
            path, old, new = edit[0], edit[1], edit[2]
            count = edit[3] if len(edit) > 3 else 1
            p = os.path.join(dest, path)
            s = open(p).read()
            n = s.count(old)
            if n != count:
                raise SystemExit('%s: %s: %r occurs %d times, not %d' % (name, path, old[:60], n, count))
            open(p, 'w').write(s.replace(old, new))
        with open(os.path.join(dest, '.mutant'), 'w') as f:
            f.write(' '.join(suites) + '\n' + ' '.join(targets) + '\n')
    print('made', len([m for m in M if not names or m[0] in names]))

if __name__ == '__main__':
    if sys.argv[1] == 'make':
        make(sys.argv[2:])
    elif sys.argv[1] == 'list':
        for m in M:
            print(m[0])

# --- call-with-int-cell's plants (the coordinator's item) ------------------------
INTCELL_BODY = """    (call-with-block who (foreign-sizeof 'int)
      (lambda (cell) (foreign-set! 'int cell 0 fill))
      (lambda (cell)
        (let ((answer (proc cell)))
          (values answer (foreign-ref 'int cell 0))))))"""
M2 = []
def mutant2(name, suites, edits):
    M2.append((name, suites, edits, ()))
mutant2('int-fill-zero', [NAT], [(NATIVE, "(lambda (cell) (foreign-set! 'int cell 0 fill))", "(lambda (cell) (foreign-set! 'int cell 0 0))")])
mutant2('int-never-freed', [NAT], [(NATIVE, INTCELL_BODY, """    (let ((cell (foreign-block (foreign-sizeof 'int))))
      (foreign-set! 'int cell 0 fill)
      (let ((answer (proc cell)))
        (values answer (foreign-ref 'int cell 0)))))""")])
mutant2('int-read-before', [NAT], [(NATIVE, """        (let ((answer (proc cell)))
          (values answer (foreign-ref 'int cell 0))))))""", """        (let* ((value (foreign-ref 'int cell 0))
               (answer (proc cell)))
          (values answer value)))))""")])
mutant2('int-range-chez', [NAT], [(NATIVE, "(and (integer? x) (exact? x) (>= x (- half)) (< x half))", "(and (integer? x) (exact? x) (>= x (- half)) (< x (* 2 half)))")])
mutant2('int-range-dropped', [NAT], [(NATIVE, "(unless (c-int? fill)", "(unless #t")])
mutant2('int-range-inexact', [NAT], [(NATIVE, "(and (integer? x) (exact? x) (>= x (- half)) (< x half))", "(and (integer? x) (>= x (- half)) (< x half))")])
mutant2('int-check-in-section', [NAT], [(NATIVE, """    (unless (c-int? fill)
      (assertion-violation who "a cell's fill is an exact integer a C int holds" (shown-value fill)))
""", ""), (NATIVE, "      (lambda (cell) (foreign-set! 'int cell 0 fill))", """      (lambda (cell)
        (unless (c-int? fill)
          (assertion-violation who "a cell's fill is an exact integer a C int holds" (shown-value fill)))
        (foreign-set! 'int cell 0 fill))""")])
mutant2('red-intcell', [NAT], [])
if __name__ == '__main__' and sys.argv[1] == 'make2':
    M[:] = M2
    make(sys.argv[2:])

M3 = [m for m in M2 if m[0] != 'red-intcell']
def mutant3(name, suites, edits):
    M3.append((name, suites, edits, ()))
mutant3('table-optional-record', [CONV], [(FC, '"ADR-0002 M4 amendment: an optional entry point,', '"ADR-0002 M4 amendment: an entry point,')])
mutant3('cv-control-no-status', [TCV], [(CV, 'if [ "$status" -eq 0 ] && [ -z "$(named)" ] && passes; then', 'if [ -z "$(named)" ] && passes; then')])
mutant3('all-builds-no-optional', [REAL], [(LL, """            (map (lambda (entry) (list (lacks-build entry) (lacks entry)))
                 (append every-entry optional-entries))))""", """            (map (lambda (entry) (list (lacks-build entry) (lacks entry)))
                 every-entry)))""")])
mutant3('probe-flag-ignored', [REAL], [(PROBE, '(when (option "--extension-loading")', '(when #f')])
if __name__ == '__main__' and sys.argv[1] == 'make3':
    M[:] = M3
    make(sys.argv[2:])
