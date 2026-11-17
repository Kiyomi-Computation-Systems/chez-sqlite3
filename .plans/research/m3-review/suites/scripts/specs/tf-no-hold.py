# The device without SQLite's mutex: plain rounds, 1 ms sleeps.
EDITS = [("tests/test-transaction-interrupt.sps", "                  (unless holding (mutex-enter memory-mutex) (set! holding #t))\n", "")]
