#!/usr/bin/env python3
# plants.py NAME...: the close fix's plants (.plans/m4-close-fix-mutation-log.md).
# Each is a copy of the worktree in build/mut/NAME/, made by tar without
# build/ and .git, with the libraries under build/ that run-plants.sh names
# copied in, and its edits applied, each checked to match its file's text
# exactly once. With no NAME, every plant; --refresh, below, makes them again. Run from the worktree's root, on
# the host; run-plants.sh runs the suites in the copies, in the container.
import os, subprocess, sys

root = os.getcwd()
conn = 'src/chez-sqlite3/private/connection.sls'
suite = 'tests/test-connection-close.sps'

# The close's work as the fix writes it, and as it stood before.
fixed = """                    (let* ((failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db)))
                           (rc (sqlite3-close handle)))
                      (if (eqv? rc sqlite-ok)
                          (begin
                            (set-database-handle! db #f)
                            (let ((double-free (guard (c (#t c))
                                                 (count-down! 'connection)
                                                 #f)))
                              (cond (failure (list 'finalize-failed failure))
                                    (double-free (list 'double-free double-free))
                                    (else '(closed)))))
                          (let ((untracked (statements-on handle)))
                            (if (> untracked 0)
                                (list 'untracked untracked)
                                (cons 'failed (details-of rc handle)))))))))"""
before = """                    (let* ((failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db)))
                           (untracked (statements-on handle)))
                      (if (> untracked 0)
                          (list 'untracked untracked)
                          (let ((rc (sqlite3-close handle)))
                            (if (eqv? rc sqlite-ok)
                                (begin
                                  (set-database-handle! db #f)
                                  (let ((double-free (guard (c (#t c))
                                                       (count-down! 'connection)
                                                       #f)))
                                    (cond (failure (list 'finalize-failed failure))
                                          (double-free (list 'double-free double-free))
                                          (else '(closed)))))
                                (cons 'failed (details-of rc handle)))))))))"""

count = "                          (let ((untracked (statements-on handle)))"
close = "                           (rc (sqlite3-close handle)))"
ok = "                      (if (eqv? rc sqlite-ok)"
left_open = "    (and (memq (car outcome) '(untracked failed)) #t))"

plants = {
  # The brief's six.
  # P01: the old order, counting before sqlite3_close.
  'p01-count-first': [(fixed, before)],
  # P02: close first, never counting: every failure is &sqlite-error.
  'p02-never-count': [(count, "                          (let ((untracked 0))")],
  # P03: counting on success too: sqlite3_next_stmt on the handle
  # sqlite3_close has just freed, and a count above 0 taken as untracked.
  'p03-count-on-success': [(ok, "                      (if (and (eqv? rc sqlite-ok) (not (> (statements-on handle) 0)))")],
  # P04: the latch left shut on the BUSY path: neither outcome sqlite3_close's
  # refusal gives sets the flag again.
  'p04-latch-shut-busy': [(left_open, "    (and (memq (car outcome) '()) #t))")],
  # P05: the connection's handle cleared on a failed close.
  'p05-handle-cleared': [(count, "                          (let ((untracked (begin (set-database-handle! db #f) (statements-on handle))))")],
  # P06: the counter counted down on a failed close.
  'p06-counted-down': [(count, "                          (let ((untracked (begin (count-down! 'connection) (statements-on handle))))")],
  # The builder's own.
  # P07: the latch shut after a refusal that found untracked statements only.
  'p07-latch-shut-untracked': [(left_open, "    (and (memq (car outcome) '(failed)) #t))")],
  # P08: the latch shut after sqlite3_close's own failure only.
  'p08-latch-shut-failed': [(left_open, "    (and (memq (car outcome) '(untracked)) #t))")],
  # P09: every refusal named untracked, a count of 0 among them.
  'p09-zero-untracked': [("                            (if (> untracked 0)", "                            (if (>= untracked 0)")],
  # P10: one statement left taken for none.
  'p10-one-not-counted': [("                            (if (> untracked 0)", "                            (if (> untracked 1)")],
  # P11: counted before sqlite3_close, that count named after it fails.
  'p11-count-before-named-after': [(close, "                           (before (statements-on handle))\n" + close),
                                   (count, "                          (let ((untracked before))")],
  # P12: the tracked statements finalized after sqlite3_close.
  'p12-finalize-after-close': [("""                    (let* ((failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db)))
                           (rc (sqlite3-close handle)))""",
                                """                    (let* ((rc (sqlite3-close handle))
                           (failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db))))""")],
  # P13: the cache left full.
  'p13-cache-kept': [("                           (emptied (statement-cache-clear! (unchecked-database-cache db)))",
                      "                           (emptied #f)")],
  # P14: sqlite3_close tried again on a refusal, before the count.
  'p14-close-twice': [(close, "                           (rc (let ((rc (sqlite3-close handle))) (if (eqv? rc sqlite-ok) rc (sqlite3-close handle)))))")],
  # P15: busy taken for success.
  'p15-busy-closes': [(ok, "                      (if (memv rc (list sqlite-ok 5))")],
  # P16: the failure's details read before the count.
  'p16-details-first': [("""                          (let ((untracked (statements-on handle)))
                            (if (> untracked 0)
                                (list 'untracked untracked)
                                (cons 'failed (details-of rc handle)))))))))""",
                         """                          (let* ((details (details-of rc handle))
                                 (untracked (statements-on handle)))
                            (if (> untracked 0)
                                (list 'untracked untracked)
                                (cons 'failed details))))))))""")],
  # P17: the failure's details read with no handle: errstr of the answer.
  'p17-details-no-handle': [("                                (cons 'failed (details-of rc handle)))))))))",
                             "                                (cons 'failed (details-of rc 0)))))))))")],
  # P18: the count down dropped from a close that closed.
  'p18-no-count-down': [("""                            (let ((double-free (guard (c (#t c))
                                                 (count-down! 'connection)
                                                 #f)))""",
                         """                            (let ((double-free (guard (c (#t c))
                                                 #f)))""")],
  # The suite's own: each row that the code as it stood passes, watched
  # failing against a plant of the suite.
  # T1: rtree's option read as ENABLE_FTS5: the option and the listing disagree.
  't1-option-disagrees': [("""  (make-vtab 'rtree "ENABLE_RTREE\"""", """  (make-vtab 'rtree "ENABLE_FTS5\"""", suite)],
  # T2: every module taken for unavailable: the refusal rows run where the
  # library has the module, whose create answers done.
  # T3: fts5's create broken, a syntax error: where the library lacks fts5,
  # the refusal rows' prepare raises, where they assert it succeeds.
  't3-create-broken': [('''               "create virtual table v using fts5(body)"''',
                        '''               "create virtual table v using fts5(body"''', suite)],
  't2-never-available': [("""  (equal? (cdr (assq (vtab-name m) reports)) '(option 1)))""",
                          """  (and #f (equal? (cdr (assq (vtab-name m) reports)) '(option 1))))""", suite)],
}

# --refresh, first: a copy that exists already has the worktree's files
# written over it again, then its edits applied again, so a suite changed
# since the copy was made runs in it.
refresh = sys.argv[1:2] == ['--refresh']
names = sys.argv[2:] if refresh else sys.argv[1:]
for name in names or sorted(plants):
    dest = os.path.join(root, 'build/mut', name)
    if os.path.exists(dest) and not refresh:
        print('exists', dest)
        continue
    os.makedirs(dest, exist_ok=True)
    tar = subprocess.Popen(['tar', '-C', root, '--exclude=./build', '--exclude=./.git', '-cf', '-', '.'],
                           stdout=subprocess.PIPE)
    subprocess.check_call(['tar', '-C', dest, '-xf', '-'], stdin=tar.stdout)
    tar.wait()
    os.makedirs(os.path.join(dest, 'build'), exist_ok=True)
    for lib in ['m3-floor', 'm4-current', 'm4-current-fts5', 'm4cf-floor-vtab', 'm4cf-current-vtab']:
        src = os.path.join(root, 'build', lib)
        if os.path.exists(src) and not os.path.exists(os.path.join(dest, 'build', lib)):
            subprocess.check_call(['cp', '-a', src, os.path.join(dest, 'build', lib)])
    for edit in plants[name]:
        old, new = edit[0], edit[1]
        path = os.path.join(dest, edit[2] if len(edit) > 2 else conn)
        s = open(path).read()
        n = s.count(old)
        assert n == 1, (name, path, n)
        open(path, 'w').write(s.replace(old, new))
    print('made', name)
