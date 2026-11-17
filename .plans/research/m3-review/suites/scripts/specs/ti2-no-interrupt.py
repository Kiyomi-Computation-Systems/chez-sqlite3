# The device sends nothing: sqlite3_interrupt never called.
EDITS = [("tests/test-transaction-interrupt.sps", "                        (sqlite3-interrupt handle)\n                        'void)))", "                        #f\n                        'void)))")]
