# N3, the reviewer's: keys compared by their first 4096 characters.
EDITS = [("src/chez-sqlite3/private/statement-cache.sls",
"    (new-statement-cache capacity (make-hashtable string-hash string=?) #f #f))",
"    (let ((head (lambda (s) (if (> (string-length s) 4096) (substring s 0 4096) s))))\n"
"      (new-statement-cache capacity (make-hashtable (lambda (s) (string-hash (head s)))\n"
"                                                    (lambda (a b) (string=? (head a) (head b))))\n"
"                           #f #f)))")]
