# Each suite's grain read with no lock held, so the waiter is not busy and
# the grain is unread.
EDITS = [
 ("tests/test-open-locks.sps", "           (hold! holder 'reserved)\n", "           (hold! holder 'idle)\n"),
 ("tests/test-open-settings.sps",
  "           (execute! holder \"begin immediate\")\n           (execute! holder \"insert into t values (1)\")\n           (let ((waiter",
  "           (execute! holder \"insert into t values (1)\")\n           (let ((waiter"),
 ("tests/test-contention.sps",
  "              (execute! holder \"begin immediate\")\n              (execute! holder \"insert into t values (4)\")\n              (let ((ms",
  "              (execute! holder \"insert into t values (4)\")\n              (let ((ms"),
 ("tests/test-interrupt-reach.sps",
  "           (execute! holder \"begin immediate\")\n           (execute! holder \"insert into t values (1)\")\n           (set! waiter",
  "           (execute! holder \"insert into t values (1)\")\n           (set! waiter"),
]
