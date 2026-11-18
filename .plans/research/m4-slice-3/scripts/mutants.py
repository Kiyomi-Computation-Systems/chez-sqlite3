"""M4 slice 3's plants: each a name, its edits as (path, old, new), the old
text matching its file exactly once, and the suites it runs, DEFAULT_SUITES
unless named. The M4 plan's section 4.7 names the first thirteen; the rest
are the builder's, at every site the slice changed."""

OPEN = "src/chez-sqlite3/private/open.sls"
SET = "src/chez-sqlite3/private/settings.sls"
CONN = "src/chez-sqlite3/private/connection.sls"
PUB = "src/chez-sqlite3.sls"
DOCS = "docs/reference.md"

DEFAULT_SUITES = ["test-settings", "test-open-settings", "test-open-db-config",
                  "test-open-db-config-engines", "test-public", "test-reference", "test-docs",
                  "test-library-loading-real"]

VERDICT = "(let ((verdict (db-config-verdict (car step) (cadddr step) code cell)))"
FILL = "(call-with-int-cell who db-config-sentinel"
NATIVE = """          (only (chez-sqlite3 private native) sqlite3-db-config sqlite3-errstr c-string->string
                call-with-int-cell load-extension-available?)"""
FAILED = """(list 'failed code (or (c-string->string (sqlite3-errstr code)) ""))"""
VALUES = "(values name flags (cadr plan) (caddr plan) opt-in)"
DB_BRANCH = """                                 ((pair? step)
                                  (loop (cdr rest) (cons name seen) capacity first (cons step steps)))"""
CONFIGURED = "  (define (configured who db step claim n db-config)\n"


def unasked(step):
    return [(OPEN, VALUES, "(values name flags (cadr plan) (cons '%s (caddr plan)) opt-in)" % step)]


MUTANTS = [
    # --- the M4 plan, section 4.7 ---------------------------------------------------------
    {"name": "P-nocell", "edits": [(OPEN, VERDICT,
        "(let ((verdict (db-config-verdict (car step) (cadddr step) code "
        "(if (eqv? code 0) (if (cadddr step) 1 0) cell))))")]},
    {"name": "P-nocode", "edits": [(OPEN, VERDICT,
        "(let ((verdict (db-config-verdict (car step) (cadddr step) 0 cell)))")]},
    {"name": "P-fill0", "edits": [(OPEN, FILL, "(call-with-int-cell who 0")]},
    {"name": "P-fill1", "edits": [(OPEN, FILL, "(call-with-int-cell who 1")]},
    {"name": "P-literal", "edits": [(OPEN, FILL, "(call-with-int-cell who -1"),
                                   (SET, "(define db-config-sentinel -1)", "(define db-config-sentinel -3)")]},
    {"name": "P-code-conn", "edits": [
        (OPEN, NATIVE, NATIVE.replace("load-extension-available?)",
                                      "load-extension-available? sqlite3-extended-errcode)")),
        (OPEN, FAILED, FAILED.replace("(list 'failed code", "(list 'failed (sqlite3-extended-errcode handle)"))]},
    {"name": "P-errmsg", "edits": [
        (OPEN, NATIVE, NATIVE.replace("load-extension-available?)", "load-extension-available? sqlite3-errmsg)")),
        (OPEN, FAILED, FAILED.replace("(sqlite3-errstr code)", "(sqlite3-errmsg handle)"))]},
    {"name": "P-unasked-defensive", "edits": unasked("(defensive 1010 1 #t)")},
    {"name": "P-unasked-load", "edits": unasked("(enable-load-extension 1005 1 #t)")},
    {"name": "P-unasked-dqs-dml", "edits": unasked("(dqs-dml 1013 0 #f)")},
    {"name": "P-unasked-dqs-ddl", "edits": unasked("(dqs-ddl 1014 0 #f)")},
    {"name": "P-defensive-skipped", "edits": [(SET, DB_BRANCH, DB_BRANCH.replace(
        "(cons step steps)", "(if (eq? name 'defensive) steps (cons step steps))"))]},
    {"name": "P-opt-in-check", "edits": [(OPEN, "(when (and opt-in (not load-extension-available?))",
                                          "(when (and opt-in #f)")]},
    {"name": "P-opt-in-inverted", "edits": [(OPEN, "(when (and opt-in (not load-extension-available?))",
                                             "(when (and opt-in load-extension-available?)")]},
    {"name": "P-false-call", "edits": [(OPEN, VALUES,
        "(values name flags (cadr plan) (if (member '(enable-load-extension . #f) (caddr split))"
        " (cons '(enable-load-extension 1005 0 #f) (caddr plan)) (caddr plan)) opt-in)")]},
    # --- the join, settings.sls -----------------------------------------------------------
    {"name": "J-order", "edits": [(SET, DB_BRANCH, DB_BRANCH.replace(
        "(cons step steps)", "(append steps (list step))"))]},
    {"name": "J-seen", "edits": [(SET,
        "                                  (loop (cdr rest) (cons name seen) capacity first steps))\n"
        "                                 ((pair? step)",
        "                                  (loop (cdr rest) seen capacity first steps))\n"
        "                                 ((pair? step)")]},
    {"name": "J-unknown", "edits": [(SET,
        """                                 (else
                                  (list 'refused 'setting-out-of-domain name (shown-value value))))))""",
        """                                 (else
                                  (list 'refused 'unknown-setting name)))))""")]},
    {"name": "J-names", "edits": [(SET, "      enable-load-extension defensive dqs-dml dqs-ddl))",
                                   "      enable-load-extension defensive dqs-dml))")]},
    {"name": "J-step-loose", "edits": [(SET, "         (integer? (cadr step)) (exact? (cadr step))\n",
                                        "         #t\n")]},
    {"name": "J-opt-in-name", "edits": [(SET, "(and (list? steps) (member opt-in-step steps) #t)",
        "(and (list? steps) (exists (lambda (s) (and (pair? s) (eq? (car s) 'enable-load-extension))) steps) #t)")]},
    {"name": "J-opt-in-list", "edits": [(OPEN, "(let ((opt-in (steps-opt-in? (caddr plan))))",
        "(let ((opt-in (and (assq 'enable-load-extension (caddr split)) #t)))")]},
    {"name": "J-messages", "edits": [(SET,
        "trusted-schema, statement-cache, enable-load-extension, defensive, dqs-dml or dqs-ddl\")",
        "trusted-schema or statement-cache\")")]},
    {"name": "J-messages-domain", "edits": [(SET,
        "statement-cache an exact integer from 0 to 1024; enable-load-extension, defensive, dqs-dml and dqs-ddl #t or #f\")))",
        "statement-cache an exact integer from 0 to 1024\")))")]},
    {"name": "J-names-order", "edits": [(SET, "      enable-load-extension defensive dqs-dml dqs-ddl))",
                                         "      enable-load-extension defensive dqs-ddl dqs-dml))")]},
    {"name": "J-extra-op", "edits": [(SET, "      enable-load-extension defensive dqs-dml dqs-ddl))",
                                      "      enable-load-extension defensive dqs-dml dqs-ddl enable-fkey))")]},
    {"name": "J-no-row", "edits": [(SET, "    (if (not (row-answer? answer))\n        '()",
                                    "    (if (not (row-answer? answer))\n        (if (assq name db-config-settings) 'nothing '())")]},
    {"name": "F-join-sample", "edits": [("tests/test-settings.sps",
        "    (dqs-ddl . #f) (statement-cache . 7)))", "    (dqs-ddl . #f)))")]},
    {"name": "J-op-wrong", "edits": [(SET, "(list 'dqs-ddl sqlite-dbconfig-dqs-ddl '(#t #f))",
                                      "(list 'dqs-ddl 1015 '(#t #f))")]},
    {"name": "J-sentinel", "edits": [(SET, "(define db-config-sentinel -1)", "(define db-config-sentinel -3)")]},
    # --- the sets, open.sls ---------------------------------------------------------------
    {"name": "O-noclaim", "edits": [(OPEN, "    (let ((s (in-section claim n\n               (lambda ()\n                 (call-with-open-handle who db",
                                     "    (let ((s (in-section (lambda (k) #t) n\n               (lambda ()\n                 (call-with-open-handle who db")]},
    {"name": "O-claim-unchecked", "edits": [(OPEN, "    (let ((s (in-section claim n\n               (lambda ()\n                 (call-with-open-handle who db",
                                             "    (let ((s (in-section (lambda (k) (claim k) #t) n\n               (lambda ()\n                 (call-with-open-handle who db")]},
    {"name": "O-split-claim", "edits": [(OPEN, CONFIGURED,
        "  (define (configured who db step claim n db-config)\n"
        "    (let ((c (in-section claim n (lambda () 'claimed))))\n"
        "      (if (eq? (car c) 'answered)\n"
        "          (configured* who db step (lambda (k) #t) n db-config)\n"
        "          c)))\n"
        "  (define (configured* who db step claim n db-config)\n")]},
    {"name": "O-all-errors", "edits": [(OPEN, "                               ((names-error? code)\n",
                                        "                               (#t\n")]},
    {"name": "O-low-zero", "edits": [(OPEN, "(not (memv (bitwise-and code 255) '(0 100 101)))))",
                                      "(not (memv (bitwise-and code 255) '(0)))))")]},
    {"name": "O-whole-code", "edits": [(OPEN, "(not (memv (bitwise-and code 255) '(0 100 101)))))",
                                        "(not (memv code '(0 100 101)))))")]},
    {"name": "O-not-error-who", "edits": [(OPEN,
        "(assertion-violation who \"a db_config set answered a code that names no error\"",
        "(assertion-violation 'settled \"a db_config set answered a code that names no error\"")]},
    {"name": "O-no-close", "edits": [(OPEN,
        "             (let ((closed (in-section claim (cadr r) (lambda () (close-connection who db)))))",
        "             (let ((closed (if (memq (car r) '(failed not-an-error mismatch)) '(answered 0)"
        " (in-section claim (cadr r) (lambda () (close-connection who db))))))")]},
    {"name": "O-value-bool", "edits": [(OPEN, "(db-config handle (cadr step) (caddr step) address)",
                                        "(db-config handle (cadr step) (if (cadddr step) 1 1) address)")]},
    {"name": "O-expected-written", "edits": [(OPEN, VERDICT,
        "(let ((verdict (db-config-verdict (car step) (caddr step) code cell)))")]},
    {"name": "O-opt-in-f", "edits": [(OPEN, "(opened-database who (connection-outcome who name flags capacity opt-in",
                                      "(opened-database who (connection-outcome who name flags capacity #f")]},
    {"name": "O-cwd-opt-in-f", "edits": [(OPEN,
        "(connection-outcome\n                                                         who name flags capacity opt-in",
        "(connection-outcome\n                                                         who name flags capacity #f")]},
    {"name": "O-errstr-1", "edits": [(OPEN, FAILED, FAILED.replace("(sqlite3-errstr code)", "(sqlite3-errstr 1)"))]},
    {"name": "O-steps-dropped", "edits": [(OPEN, VALUES,
        "(values name flags (cadr plan) (filter (lambda (s) (not (db-config-step? s))) (caddr plan)) opt-in)")]},
    {"name": "O-check-first", "edits": [(OPEN,
        "        (let ((plan (settings-plan (caddr split))))\n          (unless (eq? (car plan) 'settings)",
        "        (let ((plan (settings-plan (caddr split))))\n"
        "          (when (and (list? (caddr split)) (member '(enable-load-extension . #t) (caddr split))\n"
        "                     (not load-extension-available?))\n"
        "            (raise-extensions-unavailable who))\n"
        "          (unless (eq? (car plan) 'settings)")]},
    {"name": "O-check-before-m2", "edits": [(OPEN,
        "      (let-values (((name flags) (prepared-open who filename (cadr split))))",
        "      (when (and (list? (caddr split)) (member '(enable-load-extension . #t) (caddr split))\n"
        "                 (not load-extension-available?))\n"
        "        (raise-extensions-unavailable who))\n"
        "      (let-values (((name flags) (prepared-open who filename (cadr split))))")]},
    {"name": "O-export-extra", "edits": [(OPEN,
        "(export open-database call-with-database applied-settings! applied-settings/with made-claim)",
        "(export open-database call-with-database applied-settings! applied-settings/with made-claim configured)")]},
    # --- the record, connection.sls -------------------------------------------------------
    {"name": "C-unchecked", "edits": [(CONN,
        "    (check-owned 'database-extension-loading? db)\n    (unchecked-database-opt-in db))",
        "    (unchecked-database-opt-in db))")]},
    {"name": "C-field-f", "edits": [(CONN, "(make-interrupt-latch) (and opt-in #t))", "(make-interrupt-latch) #f)")]},
    # --- the surface -----------------------------------------------------------------------
    {"name": "X-export", "edits": [(PUB,
        "   sqlite-setting-mismatch-actual\n   ;; sqlite-extensions-unavailable? : Any -> Boolean\n   sqlite-extensions-unavailable?)",
        "   sqlite-setting-mismatch-actual)")]},
    {"name": "X-docs", "edits": [(DOCS,
        "    (query-row db \"PRAGMA writable_schema\")))\n;; => #(0)",
        "    (query-row db \"PRAGMA writable_schema\")))\n;; => #(1)")]},
]
