# plants.py: the loading mutants, planted against both layouts of the
# loading suites: main's three (old) and the closing review's nine (new).
#
#   python3 plants.py list
#   python3 plants.py prepare OLD-BASE NEW-BASE OUT
#
# Each plant is a name and its edits, (PATH, OLD, NEW[, COUNT]), OLD
# occurring COUNT times (1 by default) in the copy, else the plant is stale
# on that layout and is reported, never applied in part. A plant names its
# edits once for both layouts, or once per layout where the layouts' text
# differs. Each copy is a whole tree, OUT/LAYOUT/NAME, with a .plant file:
# its first line the suites to run, its second the make targets.
#
# The plants come from the records: M1 slice 3's load by behaviour, M2
# slice 2's list trap, M3 slice 2's partition, M4 slice 2's (round three),
# and M4 slices 3's and 4's, each its builder's and its lead's last round.
import importlib.util, json, os, subprocess, sys
sys.dont_write_bytecode = True  # the records' scripts are imported: leave no __pycache__ among them

WT = os.getcwd()  # run from the worktree's root
RESEARCH = os.path.join(WT, '.plans/research')

OLD_SUITES = ['test-library-loading-real', 'test-library-loading-decoys', 'test-library-loading-missing']
NEW_SUITES = ['test-library-loading-missing-1', 'test-library-loading-missing-2',
              'test-library-loading-missing-3', 'test-library-loading-missing-4',
              'test-library-loading-real', 'test-library-loading-preflight',
              'test-library-loading-extension', 'test-library-loading-decoys',
              'test-library-loading-combined']

N = 'src/chez-sqlite3/private/native.sls'
D = 'src/chez-sqlite3/private/discovery.sls'
LL = 'tests/library-loading.sls'
PROBE = 'tests/refusal-probe.sps'
DECOY = 'tests/decoy-libsqlite3.c'
PRE = 'tests/preflight.sps'
MK = 'Makefile'

PLANTS = []  # (name, source, {'old': edits or None, 'new': edits or None}, targets)

def plant(name, source, edits=None, old=None, new=None, targets=()):
    if edits is not None:
        old = new = edits
    PLANTS.append((name, source, {'old': old, 'new': new}, list(targets)))

# --- the control: no edit, so each layout must pass whole ----------------------------------

plant('C0-control', 'no plant', [])

# --- M1 slice 3: the load, by behaviour, rebuilt on today's code ---------------------------

VERSION_CHECKED = """  (define version-checked
    (load-step
     (check-version (libsqlite3-info-version report) (libsqlite3-info-version-number report)
                    libsqlite3-path libsqlite3-source report)))
"""
THREADSAFE_CHECKED = """  (define threadsafe-checked
    (load-step
     (check-threadsafe threadsafe libsqlite3-path libsqlite3-source report)))
"""
COMPILEOPTION_USED = """  (define sqlite3-compileoption-used
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_compileoption_used" (uptr) int))))
"""
ERRSTR = """  (define sqlite3-errstr
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errstr" (int) uptr))))
"""
INITIALIZED = """  (define initialized
    (load-step
     (let ((code (raw-initialize)))
       (unless (eqv? code 0)
         (raise-library-unavailable
          'load-failed libsqlite3-path libsqlite3-source code '() report
          "sqlite3_initialize did not answer SQLITE_OK, so this libsqlite3 cannot be used; name another with CHEZ_SQLITE3_LIBRARY"
          (list libsqlite3-path)))
       #t)))
"""
FREE = """  (define sqlite3-free
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_free" (uptr) void))))
"""

plant('N1-floor-after-threadsafe', 'M1 slice 3 N1', [
    (N, VERSION_CHECKED, ''), (N, THREADSAFE_CHECKED, THREADSAFE_CHECKED + '\n' + VERSION_CHECKED)])
plant('N2-rest-before-floor', 'M1 slice 3 N2', [
    (N, COMPILEOPTION_USED, ''), (N, VERSION_CHECKED, COMPILEOPTION_USED + '\n' + VERSION_CHECKED)])
plant('N3-errstr-bound-at-each-call', 'M1 slice 3 N3', [
    (N, ERRSTR, """  (define (sqlite3-errstr . args)
    (apply (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errstr" (int) uptr))) args))
""")])
plant('N19-initialize-after-rest', 'M1 slice 3 N19', [
    (N, INITIALIZED, ''), (N, FREE, FREE + '\n' + INITIALIZED)])
plant('N20-close-carries-no-report', 'M1 slice 3 N20', [
    (N, """     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_close" (uptr) int))))""",
     """     (bind-required #f
       (foreign-procedure __collect_safe "sqlite3_close" (uptr) int))))""")])
plant('N21-foreign-entry-never-asked', 'M1 slice 3 N21', [
    (N, '    (unless (foreign-entry? name)\n      (raise-library-unavailable\n       \'missing-api',
     '    (unless #t\n      (raise-library-unavailable\n       \'missing-api')])
plant('N26-initialize-code-taken-as-0', 'M1 slice 3 N26', [
    (N, '     (let ((code (raw-initialize)))', '     (let ((code (begin (raw-initialize) 0)))')])
plant('N27-threadsafe-handed-1', 'M1 slice 3 N27', [
    (N, '    (load-step (raw-threadsafe)))', '    (load-step (begin (raw-threadsafe) 1)))')])
plant('N10-override-hidden', 'M1 slice 3 N10', [
    (N, '(choose-libsqlite3 getenv (machine-type) (maps-text) file-exists?)',
     '(choose-libsqlite3 (lambda (n) (and (not (string=? n "CHEZ_SQLITE3_LIBRARY")) (getenv n))) (machine-type) (maps-text) file-exists?)')])
plant('L1-no-re-raise', 'M1 slice 3 L1', [(N, '(when failure (raise failure))', '(when #f (raise failure))')])
plant('L2-libversion-null-named-sourceid', 'M1 slice 3 L2', [
    (N, '(answered-null "sqlite3_libversion")))', '(answered-null "sqlite3_sourceid")))')])
plant('R4-floor-check-fed-a-literal', 'M1 slice 3 R4', [
    (N, '(check-version (libsqlite3-info-version report) (libsqlite3-info-version-number report)',
     '(check-version (libsqlite3-info-version report) 3045001')])
plant('R5-initialize-never-checked', 'M1 slice 3 R5', [
    (N, '       (unless (eqv? code 0)\n         (raise-library-unavailable\n          \'load-failed',
     '       (unless #t\n         (raise-library-unavailable\n          \'load-failed')])
plant('R6-libversion-null-dropped', 'M1 slice 3 R6', [
    (N, '(or (c-string->string (raw-libversion))\n                         (answered-null "sqlite3_libversion"))',
     '(or (c-string->string (raw-libversion)) "")')])
plant('R7-missing-api-library-f', 'M1 slice 3 R7', [
    (N, "       'missing-api path source name '() library", "       'missing-api path source name '() #f")])
plant('R8-threadsafe-never-checked', 'M1 slice 3 R8', [
    (N, '     (check-threadsafe threadsafe libsqlite3-path libsqlite3-source report)))', '     #t))')])
plant('R9-loader-raise-escapes', 'M1 slice 3 R9', [
    (N, "     (guard (e (#t (raise-library-unavailable\n                    'load-failed",
     "     (guard (e (#f (raise-library-unavailable\n                    'load-failed")])
plant('R10-any-override-taken', 'M1 slice 3 R10', [
    (D, "        ((absolute? override) (values override 'override))", "        (#t (values override 'override))")])
plant('R11-first-candidate-taken', 'M1 slice 3 R11', [
    (D, '        ((exists? (caar rest)) (values (caar rest) (cdar rest)))',
     '        (#t (values (caar rest) (cdar rest)))')])
plant('W2-guix-system-dropped', 'M1 slice 3 W2', [
    (D, "       (profile-candidate \"/run/current-system/profile\" 'guix-system))))", "       '())))")])
plant('P1-probe-imports-native', 'M1 slice 3 P1', [
    (PROBE, '        (chez-sqlite3 private counters))\n',
     '        (chez-sqlite3 private counters)\n        (only (chez-sqlite3 private native) loaded-libsqlite3))\n'),
    (PROBE, "    (cons 'loaded (eval '(loaded-libsqlite3) native))))", "    (cons 'loaded (loaded-libsqlite3))))")])
plant('P2-again-always-same', 'M1 slice 3 P2', [
    (PROBE, "  (cond ((eq? (cdr answer) (cdr first)) 'same)", "  (cond (#t 'same)")])
plant('D1-empty-switch-as-unset', 'M1 slice 3 D1', [(DECOY, '  if (!value) {', '  if (!value || !*value) {')])
plant('D2-below-floor-number-at-floor', 'M1 slice 3 D2', [
    (DECOY, 'return mode == BELOW_FLOOR ? DECOY_BELOW_NUMBER : DECOY_VERSION_NUMBER;', 'return DECOY_VERSION_NUMBER;')])
plant('F1-preflight-refusal-without-counts', 'M1 slice 3 F1', [
    (PRE, '             (say-counts err)\n             (exit 1)', '             (exit 1)')])
plant('F2b-preflight-remedy-own-text', 'M1 slice 3 F2b', [
    (PRE, '(say err "  remedy:     " (if (message-condition? e)', '(say err "  remedy:     " (if #f')])

# --- M2 slice 2's review: a list that makes rows makes no row for what it drops ---------

plant('T1-entry-dropped-from-list', 'M2 slice 2 review (traps.md)', [
    (LL, '"sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2" "sqlite3_close"',
     '"sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2"')])
plant('T2-entries-reordered', 'M2 slice 2 review (traps.md)', [
    (LL, '"sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2" "sqlite3_close"',
     '"sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_close" "sqlite3_open_v2"')])

# --- M3 slice 2: the partition, the same fault on each layout --------------------------------

plant('S1-entry-dropped-from-a-part', 'M3 slice 2, sqlite3_close dropped from its part',
      old=[(LL, '       "sqlite3_threadsafe" "sqlite3_close" "sqlite3_next_stmt" "sqlite3_reset"',
            '       "sqlite3_threadsafe" "sqlite3_next_stmt" "sqlite3_reset"')],
      new=[(LL, '       "sqlite3_libversion_number" "sqlite3_initialize" "sqlite3_close"\n',
            '       "sqlite3_libversion_number" "sqlite3_initialize"\n')])
plant('S2-entry-in-two-parts', 'M3 slice 2, sqlite3_close appended to a second part',
      old=[(LL, '"sqlite3_changes64" "sqlite3_db_config")', '"sqlite3_changes64" "sqlite3_db_config" "sqlite3_close")')],
      new=[(LL, '"sqlite3_total_changes64"\n       "sqlite3_db_config")', '"sqlite3_total_changes64"\n       "sqlite3_db_config" "sqlite3_close")')])
plant('S3-entry-moved-order-kept', 'M3 slice 2, sqlite3_libversion moved to the front of another part',
      old=[(LL, '       "sqlite3_libversion" "sqlite3_compileoption_get" "sqlite3_errcode" "sqlite3_finalize"',
            '       "sqlite3_compileoption_get" "sqlite3_errcode" "sqlite3_finalize"'),
           (LL, '       "sqlite3_threadsafe" "sqlite3_close" "sqlite3_next_stmt" "sqlite3_reset"',
            '       "sqlite3_libversion" "sqlite3_threadsafe" "sqlite3_close" "sqlite3_next_stmt" "sqlite3_reset"')],
      new=[(LL, '       "sqlite3_libversion" "sqlite3_compileoption_used" "sqlite3_errmsg" "sqlite3_next_stmt"',
            '       "sqlite3_compileoption_used" "sqlite3_errmsg" "sqlite3_next_stmt"'),
           (LL, '       "sqlite3_libversion_number" "sqlite3_initialize" "sqlite3_close"\n',
            '       "sqlite3_libversion_number" "sqlite3_libversion" "sqlite3_initialize" "sqlite3_close"\n')])
plant('S4-pattern-places-swapped', 'M3 slice 2, two of the pattern\'s places swapped',
      old=[(LL, '''    '("test-library-loading-missing.sps" "test-library-loading-decoys.sps"
      "test-library-loading-missing.sps" "test-library-loading-real.sps"
      "test-library-loading-missing.sps"))''', '''    '("test-library-loading-missing.sps" "test-library-loading-real.sps"
      "test-library-loading-missing.sps" "test-library-loading-decoys.sps"
      "test-library-loading-missing.sps"))''')],
      new=[(LL, '''    '("test-library-loading-missing-1.sps" "test-library-loading-missing-2.sps"
      "test-library-loading-missing-3.sps" "test-library-loading-missing-4.sps"))''',
            '''    '("test-library-loading-missing-1.sps" "test-library-loading-missing-4.sps"
      "test-library-loading-missing-3.sps" "test-library-loading-missing-2.sps"))''')])
plant('S5-part-found-by-another-name', 'M3 slice 2, a missing suite finds its part by another suite\'s name',
      old=[('tests/test-library-loading-missing.sps', '(define this-part (suite-part (command-line)))',
            '(define this-part (suite-part (list "tests/test-library-loading-real.sps")))')],
      new=[('tests/test-library-loading-missing-1.sps', '(define this-part (suite-part (command-line)))',
            '(define this-part (suite-part (list "tests/test-library-loading-missing-2.sps")))')])
plant('S6-exit-line-dropped', 'M3 slice 2, a loading suite\'s exit line dropped',
      old=[('tests/test-library-loading-missing.sps', '\n(exit (suite-exit-status runner))\n', '\n')],
      new=[('tests/test-library-loading-missing-1.sps', '\n(exit (suite-exit-status runner))\n', '\n')],
      targets=['check-suites'])
for s in NEW_SUITES[1:]:
    plant('S6-exit-line-dropped-' + s[len('test-library-loading-'):], 'M3 slice 2, the same, each new suite',
          old=None, new=[('tests/%s.sps' % s, '\n(exit (suite-exit-status runner))\n', '\n')],
          targets=['check-suites'])
for s in NEW_SUITES:
    plant('S7-left-out-of-the-shards-' + s[len('test-library-loading-'):], 'AGENTS.md: a suite in no shard fails make test',
          old=None, new=[(MK, '  tests/%s.sps \\\n' % s, '')], targets=['check-memory-shards'])
plant('S7-left-out-of-the-shards-missing', 'AGENTS.md: a suite in no shard fails make test',
      old=[(MK, '  tests/test-library-loading-missing.sps \\\n', '')], new=None, targets=['check-memory-shards'])

# --- the helpers that moved from -real into (library-loading): the same fault at each place --

RL = 'tests/test-library-loading-real.sps'
def moved(name, what, old_text, new_text, old_place=RL, new_place=LL):
    """OLD-TEXT and NEW-TEXT are each (OLD, NEW), the fault at the helper's
    place in that layout."""
    plant(name, 'E2: ' + what, old=[(old_place,) + old_text], new=[(new_place,) + new_text])

moved('H1-field-always-absent', 'field answers (KEY . absent) whatever the probe printed',
      ("(define (field answer key)\n  (or (and", "(define (field answer key)\n  (or (and #f"),
      ("  (define (field answer key)\n    (or (and", "  (define (field answer key)\n    (or (and #f"))
moved('H2-make-directory-never-checks', 'make-directory answers made whatever mkdir did',
      ("(if (and (eqv? (car answer) 0) (file-directory? path)) 'made (list 'not-made answer)))))",
       "(if #t 'made (list 'not-made answer)))))"),
      ("(if (and (eqv? (car answer) 0) (file-directory? path)) 'made (list 'not-made answer)))))",
       "(if #t 'made (list 'not-made answer)))))"))
moved('H3-platform-other', 'the platform is never linux',
      ("          (else 'other))))", "          (else 'other))\n    'other))"),
      ("            (else 'other))))", "            (else 'other))\n      'other))"))
moved('H4-world-always-fhs', 'the world is never guix',
      ("    (libsqlite3-world (if (string? real-maps) real-maps #f))))", "    (libsqlite3-world #f)))"),
      ("        (libsqlite3-world (if (string? maps) maps #f)))))", "        (libsqlite3-world #f))))"))
moved('H5-override-left-set', 'unset-override leaves CHEZ_SQLITE3_LIBRARY set',
      ('(define unset-override (cons* "-u" "CHEZ_SQLITE3_LIBRARY" (switch-args #f)))',
       '(define unset-override (switch-args #f))'),
      ('  (define unset-override (cons* "-u" "CHEZ_SQLITE3_LIBRARY" (switch-args #f)))',
       '  (define unset-override (switch-args #f))'))
moved('H6-guix-profile-left-set', 'no profile to search leaves GUIX_PROFILE set',
      ('(list "-u" "GUIX_ENVIRONMENT" "-u" "GUIX_PROFILE" (string-append "HOME=" empty-home))))',
       '(list "-u" "GUIX_ENVIRONMENT" (string-append "HOME=" empty-home))))'),
      ('(list "-u" "GUIX_ENVIRONMENT" "-u" "GUIX_PROFILE" (string-append "HOME=" home))))',
       '(list "-u" "GUIX_ENVIRONMENT" (string-append "HOME=" home))))'))
moved('H7-candidates-lack-guix-system', 'the expected not-found candidates lack /run/current-system',
      ('\n        "/run/current-system/profile/lib/libsqlite3.so.0"))', '))'),
      ('\n          "/run/current-system/profile/lib/libsqlite3.so.0"))', '))'))
moved('H8-lines-drop-the-last', 'lines-of drops a last line with no newline',
      ('           (reverse (if (> i start) (cons (substring text start i) found) found)))',
       '           (reverse found))'),
      ('             (reverse (if (> i start) (cons (substring text start i) found) found)))',
       '             (reverse found))'))
moved('H9-accepted-text-without-source', 'preflight\'s accepted text expected without its source',
      ('        "  path:       " path " (" source ")\\n"', '        "  path:       " path "\\n"'),
      ('          "  path:       " path " (" source ")\\n"', '          "  path:       " path "\\n"'))

# --- the records' scripts -------------------------------------------------------------------

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    try:
        spec.loader.exec_module(m)
    finally:
        sys.path.pop(0)
    return m

LOADING = ('tests/test-library-loading-decoys.sps', 'tests/test-library-loading-real.sps',
           'tests/test-library-loading-missing.sps')

def records():
    s2 = load(os.path.join(RESEARCH, 'm4-slice-2/scripts/mutants3.py'), 'mutants3')
    for name, suites, edits, targets in s2.M:
        if any(s in LOADING for s in suites):
            plant('M4s2-' + name, 'M4 slice 2, round three', [tuple(e) for e in edits])
    s3 = load(os.path.join(RESEARCH, 'm4-slice-3/scripts/mutants.py'), 's3mutants')
    for m in s3.MUTANTS:
        plant('M4s3-' + m['name'], 'M4 slice 3, the builder\'s', [tuple(e) for e in m['edits']])
    for m in json.load(open(os.path.join(RESEARCH, 'm4-slice-3/lead/plants-round3.json'))):
        plant('M4s3L-' + m['name'], 'M4 slice 3, the lead\'s round three', [tuple(e) for e in m['edits']])
    s4 = load(os.path.join(RESEARCH, 'm4-slice-4/scripts/mutants.py'), 's4mutants')
    for m in s4.MUTANTS:
        plant('M4s4-' + m['name'], 'M4 slice 4, the builder\'s', [tuple(e) for e in m['edits']])
    for m in json.load(open(os.path.join(RESEARCH, 'm4-slice-4/lead/plants-round3.json'))):
        plant('M4s4L-' + m['name'], 'M4 slice 4, the lead\'s round three', [tuple(e) for e in m['edits']])

records()

# The records' plants whose text differs on the new layout: the same fault
# in the new partition's text.
NEW_TEXT = {
    # sqlite3_db_config moved to another part, the merge's order kept
    'M4s2-decoy-parts-moved': [
        (LL, '"sqlite3_total_changes64"\n       "sqlite3_db_config")', '"sqlite3_total_changes64")'),
        (LL, '"sqlite3_last_insert_rowid" "sqlite3_free")',
         '"sqlite3_last_insert_rowid" "sqlite3_db_config" "sqlite3_free")')],
}
for i, (name, source, edits, targets) in enumerate(PLANTS):
    if name in NEW_TEXT:
        PLANTS[i] = (name, source, {'old': edits['old'], 'new': NEW_TEXT[name]}, targets)

# --- the gate's plants, run under make test-memory -------------------------------------------
# M1 slice 3's G1 and M3 slice 2's ungated child: each child row requires
# (valgrind . yes) exactly when the gate asked.
GATE_PLANTS = [
    ('G0-control', 'no plant: the gate passes', []),
    ('G1-gated-command-unchanged', 'M1 slice 3 G1', [
        ('tests/chez-sqlite3-testing.sls', '            (append words argv)))))', '            argv))))')]),
    ('G2-one-child-ungated', 'M3 slice 2: lacks-sqlite3_sourceid\'s child only', [
        (LL, '               (gated-command getenv (append (list chez "--libdirs" libdirs "--program" program)',
         '               ((if (exists (lambda (a) (string-suffix? "lacks-sqlite3_sourceid.so" a)) env-args)\n'
         '                    (lambda (getenv argv) argv)\n'
         '                    gated-command)\n'
         '                getenv (append (list chez "--libdirs" libdirs "--program" program)')]),
]

def prepare_gate(old_base, new_base, out):
    for name, source, edits in GATE_PLANTS:
        for layout, base in (('old', old_base), ('new', new_base)):
            dest = os.path.join(out, layout, name)
            if os.path.exists(dest):
                continue
            why = apply(base, dest, edits)
            print(layout, name, why or 'made')

def apply(base, dest, edits):
    """None when every edit applies; else why the plant is stale."""
    texts = {}
    for e in edits:
        path, old, new = e[0], e[1], e[2]
        count = e[3] if len(e) > 3 else 1
        if path not in texts:
            p = os.path.join(base, path)
            if not os.path.exists(p):
                return 'no file %s' % path
            texts[path] = open(p).read()
        n = texts[path].count(old)
        if n != count:
            return '%s: %r occurs %d times, not %d' % (path, old[:50], n, count)
        texts[path] = texts[path].replace(old, new)
    subprocess.check_call('mkdir -p "%s" && (cd "%s" && tar --exclude=./build --exclude=./.git --exclude=./.plans -cf - .) | (cd "%s" && tar xf -)'
                          % (dest, base, dest), shell=True)
    for path, text in texts.items():
        open(os.path.join(dest, path), 'w').write(text)
    return None

def prepare(old_base, new_base, out):
    stale = []
    made = 0
    for name, source, edits, targets in PLANTS:
        for layout, base, suites in (('old', old_base, OLD_SUITES), ('new', new_base, NEW_SUITES)):
            if edits[layout] is None:
                continue
            dest = os.path.join(out, layout, name)
            if os.path.exists(dest):
                continue
            why = apply(base, dest, edits[layout])
            if why:
                stale.append((layout, name, why))
                continue
            with open(os.path.join(dest, '.plant'), 'w') as f:
                f.write(' '.join(suites if not targets else []) + '\n' + ' '.join(targets) + '\n')
            made += 1
    with open(os.path.join(out, 'stale.txt'), 'w') as f:
        for layout, name, why in stale:
            f.write('%s %s %s\n' % (layout, name, why))
    print('made', made, 'stale', len(stale))

if __name__ == '__main__':
    if sys.argv[1] == 'list':
        for name, source, edits, targets in PLANTS:
            print(name, '|', source, '|', 'old' if edits['old'] else '-', 'new' if edits['new'] else '-', targets)
        print(len(PLANTS))
    elif sys.argv[1] == 'prepare':
        prepare(*sys.argv[2:5])
    elif sys.argv[1] == 'prepare-gate':
        prepare_gate(*sys.argv[2:5])
