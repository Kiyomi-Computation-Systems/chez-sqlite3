#!/usr/bin/env python3
# drive-a.py NAME...: the lead's part A mutants, each written into
# build/lead-mut/A, the suites run there, the file put back.
import subprocess, sys
WT = '/home/kishu/src/chez-sqlite3-wt-m3s6'
COPY = WT + '/build/lead-mut/A'
CONN = 'src/chez-sqlite3/private/connection.sls'
MUT = {
  # a close whose finalize failed, the connection closed, sets the flag again
  'K1': [(CONN, "(and (memq (car outcome) '(untracked failed)) #t)",
          "(and (memq (car outcome) '(untracked failed finalize-failed)) #t)")],
  # a close of a closed connection sets the flag again
  'K2': [(CONN, "(and (memq (car outcome) '(untracked failed)) #t)",
          "(and (memq (car outcome) '(untracked failed already-closed)) #t)")],
  # the verb answers the latch's answer
  'K4': [(CONN, """    (interrupt-latch-interrupt! (unchecked-database-latch db)
                                (lambda () (sqlite3-interrupt (unchecked-database-handle db))))
    (if #f #f))""", """    (interrupt-latch-interrupt! (unchecked-database-latch db)
                                (lambda () (sqlite3-interrupt (unchecked-database-handle db)))))""")],
  # the open sets the flag after its section, in opened-database
  'K5': [(CONN, """                          (interrupt-latch-open! (unchecked-database-latch db))
""", ""),
         (CONN, """      ((opened) (cadr outcome))""",
          """      ((opened) (interrupt-latch-open! (unchecked-database-latch (cadr outcome))) (cadr outcome))""")],
}
SUITES = ['test-interrupt-database', 'test-interrupt-reach', 'test-interrupt-close',
          'test-interrupt', 'test-connection', 'test-open-settings', 'test-open-engines',
          'test-open-interleave']
for name in sys.argv[1:]:
    edits = MUT[name]
    files = {}
    for f, old, new in edits:
        if f not in files:
            files[f] = open(WT + '/' + f).read()
    muts = dict(files)
    for f, old, new in edits:
        assert muts[f].count(old) == 1, (name, old[:50], muts[f].count(old))
        muts[f] = muts[f].replace(old, new)
    for f, s in muts.items():
        open(COPY + '/' + f, 'w').write(s)
    cmd = ' ; '.join(
        'echo "=== %s"; timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/%s.sps'
        ' > build/out.txt 2>&1; echo "rc=$?"; grep -E "^(# of unexpected|FAIL|Exception)" build/out.txt'
        ' | cut -c1-180' % (s, s) for s in SUITES)
    out = subprocess.run(['scripts/guix-env', 'sh', '-c', cmd], cwd=COPY,
                         capture_output=True, text=True).stdout
    for f, s in files.items():
        open(COPY + '/' + f, 'w').write(s)
    print('##########', name)
    for block in out.split('=== ')[1:]:
        lines = block.strip().split('\n')
        if any(l.startswith(('FAIL', 'Exception', '# of unexpected')) for l in lines) or 'rc=0' not in lines:
            print('\n'.join(lines))
    sys.stdout.flush()
