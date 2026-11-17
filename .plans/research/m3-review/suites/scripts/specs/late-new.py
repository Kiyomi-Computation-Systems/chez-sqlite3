# The second woken late: 700 ms between hearing the first's read and saying it runs.
EDITS = [("tests/late-new-contention.sps",
"                        (hear b 'first-read)\n                        (say! b 'second-runs #t)",
"                        (hear b 'first-read)\n                        (sleep (duration 700))\n                        (say! b 'second-runs #t)")]
