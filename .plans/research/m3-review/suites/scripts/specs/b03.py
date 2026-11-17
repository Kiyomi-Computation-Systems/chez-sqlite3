# B03, slice 6's: with-transaction's default made deferred.
EDITS = [("src/chez-sqlite3/private/transaction.sls",
"      ((db body) (transaction 'with-transaction db 'immediate body))",
"      ((db body) (transaction 'with-transaction db 'deferred body))")]
