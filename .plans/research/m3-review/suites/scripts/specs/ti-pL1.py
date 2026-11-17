EDITS = [('src/chez-sqlite3/private/transaction.sls', "(let ((p (exit-plan 'return begun ended (sqlite3-get-autocommit handle) level)))", "(let ((p (exit-plan 'return begun ended 0 level)))")]
