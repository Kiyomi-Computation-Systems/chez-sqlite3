#!/usr/bin/env python3
# plants.py [--refresh] NAME...: the code part's plants for M4's closing
# review (.plans/m4-closing-review-code-log.md). Each is a copy of the
# worktree in build/cr-code/NAME/, made by tar without build/ and .git, with
# the libraries under build/ copied in, and its edits applied, each checked
# to match its file's text exactly once. With no NAME, every plant.
# --refresh writes the worktree's files over a copy that exists, then
# applies its edits again. Run from the worktree's root, on the host;
# run-plants.sh runs the suites in the copies, in the container.
import os, subprocess, sys

root = os.getcwd()
conn = 'src/chez-sqlite3/private/connection.sls'
ext = 'src/chez-sqlite3/private/extension.sls'
native = 'src/chez-sqlite3/private/native.sls'

# call-with-open-handle's section as the fix writes it.
section = """                        (let ((owner (unchecked-database-owner db))
                              (caller (get-thread-id))
                              (handle (unchecked-database-handle db)))
                          (cond ((not (eqv? owner caller)) (list 'wrong-thread owner caller))
                                ((not handle) '(closed))"""

# The db_config binding as native writes it.
binding = """  (define sqlite3-db-config
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int))))"""

def wrapped(body):
    # The binding wrapped: BODY sees REAL, the binding, and DB OP V CELL.
    return ("""  (define sqlite3-db-config
    (let ((real (load-step
                 (bind-required report
                   (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int)))))
      (lambda (db op v cell) """ + body + ")))")

plants = {
  # F2: the owner check before the section alone, as main had it.
  'f2-before-only': [(section, """                        (let ((owner (unchecked-database-owner db))
                              (caller (unchecked-database-owner db))
                              (handle (unchecked-database-handle db)))
                          (cond ((not (eqv? owner caller)) (list 'wrong-thread owner caller))
                                ((not handle) '(closed))""")],
  # F2: inside the section, the open check before the owner's.
  'f2-closed-first': [(section, """                        (let ((owner (unchecked-database-owner db))
                              (caller (get-thread-id))
                              (handle (unchecked-database-handle db)))
                          (cond ((not handle) '(closed))
                                ((not (eqv? owner caller)) (list 'wrong-thread owner caller))""")],
  # F2: the caller's id read before the section, compared inside it.
  'f2-caller-before': [("    (let* ((finished #f)\n           (outcome\n",
                        "    (let* ((finished #f)\n           (early (get-thread-id))\n           (outcome\n"),
                       ("                              (caller (get-thread-id))\n                              (handle",
                        "                              (caller early)\n                              (handle")],
  # F2: the wrong thread raised inside the section, not answered as data.
  'f2-raise-inside': [("                          (cond ((not (eqv? owner caller)) (list 'wrong-thread owner caller))",
                       "                          (cond ((not (eqv? owner caller)) (raise-wrong-thread who owner caller))")],
  # F2: the section's refusal named for call-with-open-handle, not the who.
  'f2-who-lost': [("        ((wrong-thread) (raise-wrong-thread who (cadr outcome) (caddr outcome)))",
                   "        ((wrong-thread) (raise-wrong-thread 'call-with-open-handle (cadr outcome) (caddr outcome)))")],
  # The close: its owner check before its section alone, as 776e644 had it.
  'c-close-before-only': [("              (if (not (eqv? owner caller))\n                  (list 'wrong-thread owner caller)\n                  (guard (c (#t (list 'raised c)))\n                    (interrupt-latch-close!",
                           "              (if #f\n                  (list 'wrong-thread owner caller)\n                  (guard (c (#t (list 'raised c)))\n                    (interrupt-latch-close!")],
  # The close: the wrong thread raised inside its section.
  'c-close-raise-inside': [("              (if (not (eqv? owner caller))\n                  (list 'wrong-thread owner caller)\n                  (guard (c (#t (list 'raised c)))\n                    (interrupt-latch-close!",
                            "              (if (not (eqv? owner caller))\n                  (raise-wrong-thread who owner caller)\n                  (guard (c (#t (list 'raised c)))\n                    (interrupt-latch-close!")],
  # The close: its section's refusal named for close-connection.
  'c-close-who-lost': [("        ((wrong-thread) (raise-wrong-thread who (cadr outcome) (caddr outcome)))\n        ((raised) (raise (cadr outcome)))",
                        "        ((wrong-thread) (raise-wrong-thread 'close-connection (cadr outcome) (caddr outcome)))\n        ((raised) (raise (cadr outcome)))")],
  # F3: load-extension!'s opt-in read without its who, as main had it.
  'f3-no-who': [("    (unless (database-extension-loading? who db)", "    (unless (database-extension-loading? db)", ext)],
  # F3: the reader taking a who and naming itself all the same.
  'f3-who-dropped': [("       (check-owned who db)\n       (unchecked-database-opt-in db))))",
                      "       (check-owned 'database-extension-loading? db)\n       (unchecked-database-opt-in db))))")],
  # F3: the reader's who taken unchecked.
  'f3-who-unchecked': [("       (check-who 'database-extension-loading? who)\n", "")],
  # m1: ENABLE_LOAD_EXTENSION answering 21 and leaving the cell, as
  # Apple's does: the 21 branch, run green here.
  'm1-misuse-left': [(binding, wrapped("(if (= op 1005) 21 (real db op v cell))"), native)],
  # m1: answering 21 and writing the cell.
  'm1-misuse-writes': [(binding, wrapped("(if (= op 1005) (begin (foreign-set! 'int cell 0 0) 21) (real db op v cell))"), native)],
  # m1: a set of ENABLE_LOAD_EXTENSION answering 0 and setting nothing.
  'm1-set-ignored': [(binding, wrapped("(if (and (= op 1005) (not (= v -1))) 0 (real db op v cell))"), native)],
}

refresh = sys.argv[1:2] == ['--refresh']
names = sys.argv[2:] if refresh else sys.argv[1:]
for name in names or sorted(plants):
    dest = os.path.join(root, 'build/cr-code', name)
    if os.path.exists(dest) and not refresh:
        print('exists', dest)
        continue
    os.makedirs(dest, exist_ok=True)
    tar = subprocess.Popen(['tar', '-C', root, '--exclude=./build', '--exclude=./.git', '-cf', '-', '.'],
                           stdout=subprocess.PIPE)
    subprocess.check_call(['tar', '-C', dest, '-xf', '-'], stdin=tar.stdout)
    tar.wait()
    os.makedirs(os.path.join(dest, 'build'), exist_ok=True)
    for lib in ['m3-floor', 'm4-current', 'm4-noload']:
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
