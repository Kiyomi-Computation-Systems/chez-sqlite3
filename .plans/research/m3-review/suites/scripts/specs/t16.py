# T16, the reviewer's: test-transaction-nomem's memory-kept forced to #f.
EDITS = [("tests/test-transaction-nomem.sps",
"      (close-database! db)\n      (> used 0))))",
"      (close-database! db)\n      #f)))")]
