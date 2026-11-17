#!/usr/bin/env python3
# a2-plants.py NAME...: part A, follow-up 2's plants (the slice's mutation
# log). Each is a copy of the worktree in build/a2/final/NAME/, made by tar
# without build/ and .git, with build/m3-floor copied in, and its edits
# applied, each checked to match its file's text exactly once. With no NAME,
# every plant. a2-run.sh runs the suites in the copies.
import os, subprocess, sys
root = '/home/kishu/src/chez-sqlite3-wt-m3s6'
conn = 'src/chez-sqlite3/private/connection.sls'
correct = """    (interrupt-latch-interrupt! (unchecked-database-latch db)
                                (lambda () (interrupt (unchecked-database-handle db))))
    (if #f #f))"""
verb = """  (define (interrupt-database! db)
    (interrupt-database/with db sqlite3-interrupt))"""
plants = {
  # P-a: the thunk reads the handle into a local; the call after the latch returns.
  'pa': [(correct, """    (let ((h #f))
      (interrupt-latch-interrupt! (unchecked-database-latch db)
                                  (lambda () (set! h (unchecked-database-handle db))))
      (when h (interrupt h)))
    (if #f #f))""")],
  # P-a's shape at the real verb, interrupt-database/with left correct.
  'pa-verb': [(verb, """  (define (interrupt-database! db)
    (let ((h #f))
      (interrupt-database/with db (lambda (handle) (set! h handle)))
      (when h (sqlite3-interrupt h)))
    (if #f #f))""")],
  # The handle read before the latch, the call inside it.
  'handle-before': [(correct, """    (let ((h (unchecked-database-handle db)))
      (interrupt-latch-interrupt! (unchecked-database-latch db)
                                  (lambda () (interrupt h))))
    (if #f #f))""")],
  # The call made twice: once inside the latch, once after it.
  'twice': [(correct, """    (let ((h #f))
      (interrupt-latch-interrupt! (unchecked-database-latch db)
                                  (lambda ()
                                    (set! h (unchecked-database-handle db))
                                    (interrupt h)))
      (when h (interrupt h)))
    (if #f #f))""")],
  # The call after the latch, but inside one critical section with it: no
  # expiry splits them, and the latch's mutex is let go before the call.
  'section': [(correct, """    (critical-section
     (let ((h #f))
       (interrupt-latch-interrupt! (unchecked-database-latch db)
                                   (lambda () (set! h (unchecked-database-handle db))))
       (when h (interrupt h))))
    (if #f #f))""")],
  # The thunk calls nothing: the verb reaches no foreign call.
  'no-call': [(correct, """    (interrupt-latch-interrupt! (unchecked-database-latch db)
                                (lambda () (unchecked-database-handle db)))
    (if #f #f))""")],
  # No latch: the call made with whatever the record holds.
  'no-latch': [(correct, """    (interrupt (unchecked-database-handle db))
    (if #f #f))""")],
  # P5b of part A's log: the handle read before, the call when it is not #f,
  # no latch and no flag.
  'p5b': [(correct, """    (let ((h (unchecked-database-handle db)))
      (when h (interrupt h)))
    (if #f #f))""")],
  # M08 of part A's log, P5's plant: the latch's flag read made #t, in
  # slice 1's interrupt.sls, in the copy only.
  'm08': [("              (if (latch-interruptible latch)", "              (if #t", 'src/chez-sqlite3/private/interrupt.sls')],
  # The suite's sweeps start at fuel 100000: no trial expires.
  'suite-no-expiry': [("  (let* ((before (collections))\n         (trials (parameterize ((collect-trip-bytes (* 1024 1024 1024)))\n                   (let loop ((fuel 1) (trials '()))",
                       "  (let* ((before (collections))\n         (trials (parameterize ((collect-trip-bytes (* 1024 1024 1024)))\n                   (let loop ((fuel 100000) (trials '()))", 'tests/test-interrupt-database.sps')],
  # The suite's trials collect after the open, outside the engine.
  'suite-collecting': [("                   (set! db (open-database \":memory:\"))\n                   (let ((live (with-handle db (lambda (h) h))))\n                     ((make-engine",
                        "                   (set! db (open-database \":memory:\"))\n                   (collect)\n                   (let ((live (with-handle db (lambda (h) h))))\n                     ((make-engine", 'tests/test-interrupt-database.sps')],
}
for name in sys.argv[1:] or plants:
    dest = os.path.join(root, 'build/a2/final', name)
    if os.path.exists(dest):
        print('exists', dest); continue
    os.makedirs(dest)
    tar = subprocess.Popen(['tar', '-C', root, '--exclude=./build', '--exclude=./.git', '-cf', '-', '.'], stdout=subprocess.PIPE)
    subprocess.check_call(['tar', '-C', dest, '-xf', '-'], stdin=tar.stdout)
    tar.wait()
    os.makedirs(os.path.join(dest, 'build'), exist_ok=True)
    subprocess.check_call(['cp', '-a', os.path.join(root, 'build/m3-floor'), os.path.join(dest, 'build/m3-floor')])
    for edit in plants[name]:
        old, new = edit[0], edit[1]
        path = os.path.join(dest, edit[2] if len(edit) > 2 else conn)
        s = open(path).read()
        n = s.count(old)
        assert n == 1, (name, n)
        open(path, 'w').write(s.replace(old, new))
    print('made', name)
