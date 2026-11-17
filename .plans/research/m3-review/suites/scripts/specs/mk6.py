# Writes the item-6 plant specs: each file F among the suites, with an
# old copy tests/old-NAME.sps where named.
import os
ENTER_OLD = '(define mutex-enter (bound \'sqlite3_mutex_enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void)))'
ENTER_NEW = '''(define mutex-enter
  (let ((real (bound 'sqlite3_mutex_enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void)))
        (calls 0))
    (lambda (m)
      (set! calls (+ calls 1))
      (if (odd? calls) (error 'mutex-enter "planted: raises on every odd call") (real m)))))'''
PS = '''(define planted-sleep
  (let ((calls 0))
    (lambda (t)
      (set! calls (+ calls 1))
      (if (odd? calls) (error 'sleep "planted: raises on every odd call") (sleep t)))))'''
def w(name, edits):
    with open(f"specs/{name}.py", "w") as f:
        f.write("EDITS = " + repr(edits) + "\n")
for f in ["tests/test-interrupt-reach.sps", "tests/test-interrupt-close.sps", "tests/test-transaction-interrupt.sps",
          "tests/old-interrupt-reach.sps", "tests/old-interrupt-close.sps"]:
    tag = os.path.basename(f)[:-4]
    w(f"enter-{tag}", [(f, ENTER_OLD, ENTER_NEW)])
# the hold's sleep
w("sleep-test-interrupt-reach", [
  ("tests/test-interrupt-reach.sps", "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
  ("tests/test-interrupt-reach.sps", "                (when hold? (sleep one-ms))", "                (when hold? (planted-sleep one-ms))")])
w("sleep-old-interrupt-reach", [
  ("tests/old-interrupt-reach.sps", "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
  ("tests/old-interrupt-reach.sps", "                   (when hold? (sleep one-ms))", "                   (when hold? (planted-sleep one-ms))")])
for f in ["tests/test-interrupt-close.sps", "tests/test-transaction-interrupt.sps"]:
    tag = os.path.basename(f)[:-4]
    w(f"sleep-{tag}", [
      (f, "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
      (f, "                  (start!)\n                  (sleep one-ms)", "                  (start!)\n                  (planted-sleep one-ms)")])
w("sleep-old-interrupt-close", [
  ("tests/old-interrupt-close.sps", "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
  ("tests/old-interrupt-close.sps", "                   (unless started (set! started #t) (condition-broadcast c)))\n                 (sleep one-ms)",
   "                   (unless started (set! started #t) (condition-broadcast c)))\n                 (planted-sleep one-ms)")])
# the race's sleep
w("race-test-interrupt-close", [
  ("tests/test-interrupt-close.sps", "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
  ("tests/test-interrupt-close.sps", "(when (= burst 9) (sleep one-microsecond))", "(when (= burst 9) (planted-sleep one-microsecond))")])
w("race-old-interrupt-close", [
  ("tests/old-interrupt-close.sps", "(define one-ms (duration 1))", "(define one-ms (duration 1))\n" + PS),
  ("tests/old-interrupt-close.sps", "(begin (sleep one-microsecond) (loop 0))", "(begin (planted-sleep one-microsecond) (loop 0))")])
print("written")
