# offtimer-probe.py TREE OUT: on the host (the container has no python3), from TREE's
# tests/test-transaction-engine.sps, a copy at OUT/tests/test-transaction-engine.sps whose
# exit-noted! counts, for each request handled while a forced section's is due inside a first
# slice whose ticks read spent, whether that section's callback saw the engine's timer running.
# The first form's credit took every such request; the copy prints the two counts last. Run it
# from TREE's root, inside scripts/guix-env:
#   $CHEZ --libdirs OUT/tests:src:tests:build/scheme-libs --program OUT/tests/test-transaction-engine.sps
# In M4's closing review it printed "timer running 1176, timer off 5115", every row passing:
# an expiry's unwinding forces sections with the timer off (.plans/traps.md).
import os
import sys

tree, out = sys.argv[1], sys.argv[2]
with open(os.path.join(tree, "tests", "test-transaction-engine.sps")) as f:
    s = f.read()

old = """(define (exit-noted!)
  (when forced-pending
    (set! forced-pending #f)"""
new = """(define offtimer-credits 0)
(define ontimer-credits 0)
(define (exit-noted!)
  (when forced-pending
    (when (and numbering (ticks-spent?))
      (if (number? forced-at)
          (set! ontimer-credits (+ ontimer-credits 1))
          (set! offtimer-credits (+ offtimer-credits 1))))
    (set! forced-pending #f)"""
end = "(exit (suite-exit-status runner))"
for anchor in (old, end):
    if s.count(anchor) != 1:
        sys.exit("offtimer-probe.py: an anchor is not in the suite exactly once: " + anchor[:40])
s = s.replace(old, new)
s = s.replace(end, '(display "probe: credits the old rule gave, timer running ")'
              '(write ontimer-credits)(display ", timer off ")(write offtimer-credits)(newline)\n'
              + end)
os.makedirs(os.path.join(out, "tests"))
with open(os.path.join(out, "tests", "test-transaction-engine.sps"), "w") as f:
    f.write(s)
