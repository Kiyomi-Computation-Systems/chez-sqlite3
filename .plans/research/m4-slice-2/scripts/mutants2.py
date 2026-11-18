# mutants2.py: the second round's plants, after the review's fixes. It takes
# mutants.py's code and data plants whose text still stands, with the texts
# that moved patched, and adds the new script's, the review items' and
# sqlite3_stmt_busy's. `python3 mutants2.py make` makes every copy.
import os, sys
sys.argv_saved = sys.argv
import mutants as m1
from mutants import (WT, MUT, NATIVE, CONST, FC, LL, DECOY, PROBE, TC, CV,
                     CONV, CONS, NAT, DEC, REAL, MISS, CI, TCV, make)

keep = []
for x in m1.M + m1.M3:
    if not x[0].startswith('cv-') and x[0] not in [k[0] for k in keep]:
        keep.append(x)
M = []
for name, suites, edits, targets in keep:
    fixed = []
    for ed in edits:
        path, old, new = ed[0], ed[1], ed[2]
        if path == LL and old == '"sqlite3_db_config" "sqlite3_free"))':
            old = '"sqlite3_db_config" "sqlite3_free" "sqlite3_stmt_busy"))'
            new = new.replace('"sqlite3_free" "sqlite3_load_extension"))', '"sqlite3_free" "sqlite3_stmt_busy" "sqlite3_load_extension"))')
        if path == LL and old == '"sqlite3_last_insert_rowid")':
            old = '"sqlite3_last_insert_rowid" "sqlite3_stmt_busy")'
            new = '"sqlite3_last_insert_rowid" "sqlite3_stmt_busy" "sqlite3_db_config")'
        fixed.append((path, old, new) + tuple(ed[3:]))
    M.append((name, suites, fixed, targets))

def mutant(name, suites, edits, targets=(), env=None):
    M.append((name, suites, edits, targets))
    if env:
        ENV[name] = env
ENV = {}
HDR = 'export C_INCLUDE_PATH=$PWD/../../review-mut/apple-hdr${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}\n'

# --- sqlite3_stmt_busy ---------------------------------------------------------
BUSY = """  (define sqlite3-stmt-busy
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_stmt_busy" (uptr) int))))
"""
mutant('busy-safe', [CONV], [(NATIVE, '(foreign-procedure "sqlite3_stmt_busy" (uptr) int)', '(foreign-procedure __collect_safe "sqlite3_stmt_busy" (uptr) int)')])
mutant('busy-zero', [NAT], [(NATIVE, BUSY, """  (define sqlite3-stmt-busy
    (let ((raw (load-step
     (bind-required report
       (foreign-procedure "sqlite3_stmt_busy" (uptr) int)))))
      (lambda (s) (if #f (raw s) 0))))
""")])
mutant('decoy-busy-inverted', [DEC, REAL, MISS], [(DECOY, '#ifndef DECOY_LACKS_sqlite3_stmt_busy', '#ifdef DECOY_LACKS_sqlite3_stmt_busy')])
mutant('busy-dealt-missing', [DEC, REAL, MISS], [
    (LL, '"sqlite3_last_insert_rowid" "sqlite3_stmt_busy")', '"sqlite3_last_insert_rowid")'),
    (LL, '"sqlite3_interrupt" "sqlite3_free")))', '"sqlite3_interrupt" "sqlite3_free" "sqlite3_stmt_busy")))')])
mutant('busy-not-required', [NAT, CONV], [(NATIVE, BUSY, "")])

# --- the optional prototype's own compile (review item 2) ------------------------
mutant('optional-in-main', [CONS], [(TC, '(define prototype-asks (map prototype-ask required-rows))', '(define prototype-asks (map prototype-ask conventions-table))')])
mutant('optional-in-main-hdr', [CONS], [(TC, '(define prototype-asks (map prototype-ask required-rows))', '(define prototype-asks (map prototype-ask conventions-table))')], env=HDR)
mutant('control-hdr', [CONS], [], env=HDR)
mutant('rule-inverted', [CONS], [(TC, "((eq? r #t) (list 'compile-failed 'the-library-has-it (car facts)))", "((eq? r #t) '(unavailable))")])
mutant('rule-inverted-hdr', [CONS], [(TC, "((eq? r #t) (list 'compile-failed 'the-library-has-it (car facts)))", "((eq? r #t) '(unavailable))")], env=HDR)
mutant('rule-asks-always', [CONS], [(TC, """(define (optional-verdict name facts record)
  (if (eq? (car facts) 'facts)""", """(define (optional-verdict name facts record)
  (record)
  (if (eq? (car facts) 'facts)""")])

# --- the FIFO row's hung branch (review item 6) -----------------------------------
mutant('loader-steps-1', [NAT], [(NAT, '(define loader-steps 12000)', '(define loader-steps 1)')])
mutant('loader-steps-1-no-release', [NAT], [(NAT, '(define loader-steps 12000)', '(define loader-steps 1)'),
    (NAT, """                         (capture-command (list "sh" "-c" "exec 3<>\\"$1\\"" "sh" fifo))))
           (returned""", """                         'not-released))
           (returned""")])

# --- the list held to the tree (review item 3) --------------------------------------
mutant('rename-sweep', [TCV], [(CONV, '(test-equal "sweep: a row with no form fails, by name"', '(test-equal "sweep: a row without a form fails, by name"')])
mutant('marker-in-comment', [TCV], [(NATIVE, '  ;; M4\'s three required and its one optional', '  ;; The variadic one carries (__varargs_after 2).\n  ;; M4\'s three required and its one optional')])
mutant('list-stale', [TCV], [(CV, 'for each of the 76 arguments\nTEN', 'for each of the 75 arguments\nTEN')])

# --- the new script's own plants, each held by test-check-variadic ---------------------
def cv(name, old, new):
    mutant('cv-' + name, [TCV], [(CV, old, new)])
cv('once-dropped', '[ "$before" -eq 1 ] || give_up', '[ "$before" -ge 0 ] || give_up')
cv('left-dropped', 'if [ "$diffs" -eq 1 ] && [ "$after" -eq 0 ]; then', 'if [ "$diffs" -eq 1 ]; then')
cv('changed-dropped', 'if [ "$diffs" -eq 1 ] && [ "$after" -eq 0 ]; then', 'if [ "$after" -eq 0 ]; then')
cv('static-any-status', """if [ "$rc" -ne 1 ]; then
  printf '  it exited""", """if [ "$rc" -eq 0 ]; then
  printf '  it exited""")
cv('static-no-names', 'if ! cmp -s -- "$scratch/want.names" "$scratch/got.names"; then', 'if false; then')
cv('static-no-violations', 'if [ "$seen" != "$row_src_actual" ]; then', 'if false; then')
cv('uname', """for arm in arm64osx tarm64osx; do
  if [ "$machine" = "$arm" ]; then apple=yes; fi
done""", """if [ "$(uname -s)-$(uname -m)" = Darwin-arm64 ]; then apple=yes; fi""")
cv('no-tarm64osx', 'for arm in arm64osx tarm64osx; do', 'for arm in arm64osx; do')
cv('arm64-no-evidence', 'if [ "$through" -gt 0 ] || [ "$rc" -gt 128 ]; then shown=yes; fi', 'shown=yes')
cv('arm64-exit-0', """  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
    if [ "$through\"""", """  if [ "$rc" -ne 124 ]; then
    if [ "$through\"""")
cv('arm64-hang', """  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
    if [ "$through\"""", """  if [ "$rc" -ne 0 ]; then
    if [ "$through\"""")
cv('arm64-any-name', 'through=$(failures | grep -c -F -e sqlite3_db_config || :)', 'through=$(failures | grep -c -e . || :)')
cv('control-no-count', 'if [ "$rc" -eq 0 ] && [ -z "$(failures)" ] && counted; then', 'if [ "$rc" -eq 0 ] && [ -z "$(failures)" ]; then')
cv('control-no-fail-check', 'if [ "$rc" -eq 0 ] && [ -z "$(failures)" ] && counted; then', 'if [ "$rc" -eq 0 ] && counted; then')
cv('control-no-status', 'if [ "$rc" -eq 0 ] && [ -z "$(failures)" ] && counted; then', 'if [ -z "$(failures)" ] && counted; then')
cv('srfi-unchecked', 'if [ ! -d "$libs/srfi" ]; then', 'if false; then')
cv('runs-in-tree', '  (cd -- "$work" &&', '  (cd -- "$tree" &&')
cv('no-timeout', '    exec "$bound" --foreground "$limit" "$chez" --libdirs', '    exec "$chez" --libdirs')
cv('other-fails', '  passed "other: on $machine, $native_suite fails on the mutant', '  failed "other: on $machine, $native_suite fails on the mutant')
cv('machine-status-unread', 'if [ "$rc" -ne 0 ] || [ -z "$machine" ]; then', 'if [ -z "$machine" ]; then')
cv('machine-loose', """machine=$(awk 'NR == 1 && /^[a-z0-9]+$/ { type = $0 } END { if (NR == 1) print type }' "$log")""", """machine=$(awk 'END { print $0 }' "$log")""")
cv('usage-dropped', 'if [ "$#" -gt 0 ]; then', 'if false; then')
cv('last-exit-0', """  say "$oks ok, $fails FAILED" >&2
  exit 1""", """  say "$oks ok, $fails FAILED" >&2
  exit 0""")
cv('mutation-not-written', 'cp -- "$scratch/native.mut" "$work/$native_rel" ||', 'true ||')
cv('static-runs-native', """suite test-conventions
expected_failures""", """suite test-native
expected_failures""")

if __name__ == '__main__' and sys.argv[1] == 'make':
    m1.M[:] = M
    make(sys.argv[2:])
    for name, text in ENV.items():
        if not sys.argv[2:] or name in sys.argv[2:]:
            open(os.path.join(MUT, name, '.env'), 'w').write(text)

# --- round two's reruns and additions -------------------------------------------
M_EXTRA = [x for x in m1.M if x[0] == 'cv-mutant']
COLLECTOR_RELEASE = """                        (with-mutex m (set! collected #t))
                        (let ((released (capture-command
                                         (list "sh" "-c" "exec 3<>\\"$1\\"" "sh" fifo))))
                          (if (equal? released '(0 "" "")) 'collected (list 'release released))))"""
HUNG_RELEASE = """                         (capture-command (list "sh" "-c" "exec 3<>\\"$1\\"" "sh" fifo))))
           (returned"""
M_EXTRA.append(('loader-steps-1-silent-collector', [NAT], [
    (NAT, '(define loader-steps 12000)', '(define loader-steps 1)'),
    (NAT, COLLECTOR_RELEASE, """                        (with-mutex m (set! collected #t))
                        'collected)""")], ()))
M_EXTRA.append(('loader-steps-1-silent-collector-no-release', [NAT], [
    (NAT, '(define loader-steps 12000)', '(define loader-steps 1)'),
    (NAT, COLLECTOR_RELEASE, """                        (with-mutex m (set! collected #t))
                        'collected)"""),
    (NAT, HUNG_RELEASE, """                         'not-released))
           (returned""")], ()))
M_EXTRA += [x for x in M if x[0] in ('cv-arm64-exit-0', 'cv-arm64-hang')]
if __name__ == '__main__' and sys.argv[1] == 'extra':
    m1.MUT = os.path.join(os.getcwd(), 'build/mut2')
    m1.M[:] = M_EXTRA
    make([])
