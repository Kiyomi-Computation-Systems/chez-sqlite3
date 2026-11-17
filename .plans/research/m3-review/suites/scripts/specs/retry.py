# A retry in Scheme, slice 6's B02 widened to the prepare: a step that
# answers 5 is reset and stepped once more, and a prepare that answers 5 is
# made once more.
EDITS = [("src/chez-sqlite3/private/statement.sls",
"               (let* ((answer (sqlite3-step handle))",
"               (let* ((answer (let ((a (sqlite3-step handle)))\n                                (if (eqv? a 5) (begin (sqlite3-reset handle) (sqlite3-step handle)) a)))"),
("src/chez-sqlite3/private/statement.sls",
"""                                        (let ((rc (sqlite3-prepare-v3 connection address nbyte
                                                                      flags statement-slot tail-slot)))""",
"""                                        (let ((rc (let ((r (sqlite3-prepare-v3 connection address nbyte
                                                                               flags statement-slot tail-slot)))
                                                    (if (eqv? r 5)
                                                        (sqlite3-prepare-v3 connection address nbyte
                                                                            flags statement-slot tail-slot)
                                                        r))))""")]
