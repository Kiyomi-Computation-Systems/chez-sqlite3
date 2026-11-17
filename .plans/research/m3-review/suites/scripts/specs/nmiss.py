# A check-out that misses evicts the least recently used.
EDITS = [("src/chez-sqlite3/private/statement-cache.sls",
"            (list 'hit (entry-statement e)))\n          (list 'miss))))",
"            (list 'hit (entry-statement e)))\n          (let ((o (cache-oldest cache)))\n            (when o (hashtable-delete! (cache-table cache) (entry-key o)) (unlink! cache o))\n            (list 'miss)))))")]
