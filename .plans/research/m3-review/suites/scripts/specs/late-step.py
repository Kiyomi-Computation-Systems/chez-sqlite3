# The watched call made 200 ms into the thunk, so the first round can end
# before the step begins: the transaction suite's execute! and the close
# suite's step!.
EDITS = [("tests/test-transaction-interrupt.sps",
"(interrupted db (lambda () (execute! db sql long-rows)))",
"(interrupted db (lambda () (sleep (duration 200)) (execute! db sql long-rows)))"),
("tests/test-interrupt-close.sps",
"(let ((w (watched db (lambda () (step! st)))))",
"(let ((w (watched db (lambda () (sleep (duration 200)) (step! st)))))")]
