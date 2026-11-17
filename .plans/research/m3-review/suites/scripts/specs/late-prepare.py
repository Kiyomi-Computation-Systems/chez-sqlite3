# The long prepare called 200 ms into the watched thunk, so the first round
# can end before the call begins.
EDITS = [("tests/test-interrupt-reach.sps",
"(watched db (lambda () (prepare-statement db long-prepare)) #t)",
"(watched db (lambda () (sleep (duration 200)) (prepare-statement db long-prepare)) #t)")]
