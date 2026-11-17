# The second woken late: 700 ms after hearing the first's read, before RUN.
EDITS = [("tests/late-old-contention.sps",
"                        (hear b 'first-read)\n                        (let ((t0 (real-time)))",
"                        (hear b 'first-read)\n                        (sleep (duration 700))\n                        (let ((t0 (real-time)))")]
