# M4 slice 1's mutants, each a list of (file, old, new) edits applied to a copy
# of the tree by mut.py prepare. The slice's base is 87e762c, main, whose tree
# is fd4831c's, e2e99d2: slice 0's head, on which the slice was built.
SET = "src/chez-sqlite3/private/settings.sls"
CON = "src/chez-sqlite3/private/conditions.sls"
TOP = "src/chez-sqlite3.sls"

DEFAULT_SUITES = ["test-settings", "test-conditions", "test-open-settings"]

MUTANTS = [
    # The red run: the base's libraries with the new exports stubbed, every
    # one present and wrong: the table and names empty, the sentinel 0, the
    # step and the verdict raising, the condition under &error, its raise a
    # symbol.
    {"name": "RED",
     "edits": [
         (SET, "raise-setting-refusal read-back-value read-back-comparison)",
          "raise-setting-refusal read-back-value read-back-comparison\n"
          "          db-config-settings db-config-setting-names db-config-sentinel db-config-step\n"
          "          db-config-verdict)"),
         (SET, "  ;; setting-names : (Listof Symbol)\n",
          "  (define db-config-settings '())\n"
          "  (define db-config-setting-names '())\n"
          "  (define db-config-sentinel 0)\n"
          "  (define (db-config-step name value) (error 'db-config-step \"stub\"))\n"
          "  (define (db-config-verdict name value code cell) (error 'db-config-verdict \"stub\"))\n"
          "  ;; setting-names : (Listof Symbol)\n"),
         (CON, "          raise-transaction-ended\n",
          "          raise-transaction-ended\n"
          "          &sqlite-extensions-unavailable make-sqlite-extensions-unavailable\n"
          "          sqlite-extensions-unavailable? raise-extensions-unavailable\n"),
         (CON, "  ;; sqlite-busy? : Any -> Boolean\n  ;; sqlite-constraint? : Any -> Boolean\n  ;; sqlite-read-only?",
          "  (define-condition-type &sqlite-extensions-unavailable &error\n"
          "    make-sqlite-extensions-unavailable sqlite-extensions-unavailable?)\n"
          "  (define (raise-extensions-unavailable who) (raise 'stub))\n"
          "  ;; sqlite-busy? : Any -> Boolean\n  ;; sqlite-constraint? : Any -> Boolean\n  ;; sqlite-read-only?"),
     ]},
]

TS = "tests/test-settings.sps"

TABLE = """    '((enable-load-extension 1005 (#t #f))
      (defensive 1010 (#t #f))
      (dqs-dml 1013 (#t #f))
      (dqs-ddl 1014 (#t #f))))"""

STEP_DOMAIN = "            ((not (memv value (caddr setting))) 'out-of-domain)\n"
STEP_NOCALL = "            ((and (eq? name 'enable-load-extension) (eq? value #f)) 'no-call)\n"
STEP_ELSE = "            (else (list name (cadr setting) (if value 1 0) value)))))"
V_CODE = "    (cond ((not (eqv? code 0)) (list 'error code))\n"
V_MATCH = "          ((and (boolean? expected) (eqv? cell (if expected 1 0))) 'match)\n"
V_ACTUAL = """                 (cond ((eqv? cell db-config-sentinel) '())
                       ((eqv? cell 1) #t)
                       ((eqv? cell 0) #f)
                       (else cell)))))))"""
V_MISMATCH = "           (list 'mismatch name expected\n"
TYPE = """  (define-condition-type &sqlite-extensions-unavailable &chez-sqlite3-error
    make-sqlite-extensions-unavailable sqlite-extensions-unavailable?)"""
RAISE_BODY = """    (check-raise-who 'raise-extensions-unavailable who)
    (raise (condition (make-sqlite-extensions-unavailable) (make-who-condition who)
                      (make-message-condition"""
NAMES = "    '(busy-timeout foreign-keys journal-mode synchronous temp-store trusted-schema statement-cache))"


def m(name, edits, suites=None):
    d = {"name": name, "edits": edits}
    if suites:
        d["suites"] = suites
    return d


MUTANTS += [
    # --- the brief's plants ---
    m("D1", [(SET, TABLE, TABLE.replace("(#t #f)", "(#t #f 0 1)"))]),
    m("D2", [(SET, STEP_DOMAIN, "")]),
    m("S1", [(SET, STEP_NOCALL, "")]),
    m("V1", [(SET, V_CODE, "    (cond\n")]),
    m("V2", [(SET, V_MATCH, "          ((eqv? code 0) 'match)\n")]),
    m("Z0", [(SET, "(define db-config-sentinel -1)", "(define db-config-sentinel 0)")]),
    m("Z1", [(SET, "(define db-config-sentinel -1)", "(define db-config-sentinel 1)")]),
    m("J1", [(SET, NAMES, NAMES[:-2] + "\n      enable-load-extension defensive dqs-dml dqs-ddl))")]),
    m("C1", [(CON, TYPE, """  (define-condition-type &sqlite-extensions-unavailable &sqlite-error
    unchecked-make-sqlite-extensions-unavailable sqlite-extensions-unavailable?)
  (define (make-sqlite-extensions-unavailable)
    (unchecked-make-sqlite-extensions-unavailable 'error 'error "m" #f #f))""")]),
    m("C2", [(CON, TYPE, """  (define-condition-type &sqlite-extensions-unavailable &sqlite-library-unavailable
    unchecked-make-sqlite-extensions-unavailable sqlite-extensions-unavailable?)
  (define (make-sqlite-extensions-unavailable)
    (unchecked-make-sqlite-extensions-unavailable 'missing-api #f #f "sqlite3_load_extension" '() #f))""")]),
    # --- the table ---
    m("T1", [(SET, TABLE, TABLE.replace("1013", "XXXX").replace("1014", "1013").replace("XXXX", "1014"))]),
    m("T2", [(SET, TABLE, TABLE.replace("1005", "1017"))]),
    m("T3", [(SET, TABLE, """    '((defensive 1010 (#t #f))
      (enable-load-extension 1005 (#t #f))
      (dqs-dml 1013 (#t #f))
      (dqs-ddl 1014 (#t #f))))""")]),
    m("T4", [(SET, TABLE, TABLE[:-2] + "\n      (trusted-schema 1017 (#t #f))))")]),
    m("T5", [(SET, TABLE, TABLE.replace("(enable-load-extension 1005", "(enable-load-extensions 1005"))]),
    m("T6", [(SET, TABLE, TABLE.replace("(defensive 1010 (#t #f))", "(defensive 1010 (#t))"))]),
    # --- the names ---
    m("N1", [(SET, "(define db-config-setting-names (map car db-config-settings))",
              "(define db-config-setting-names '(enable-load-extension defensive dqs-dml))")]),
    # --- the step ---
    m("S2", [(SET, STEP_NOCALL, "            ((eq? value #f) 'no-call)\n")]),
    m("S3", [(SET, STEP_NOCALL, "            ((eq? name 'enable-load-extension) 'no-call)\n")]),
    m("S4", [(SET, STEP_ELSE, STEP_ELSE.replace("(if value 1 0)", "(if value 0 1)"))]),
    m("S5", [(SET, STEP_ELSE, "            (else (list name (cadr setting) (if value 1 0) (if value 1 0))))))")]),
    m("S6", [(SET, "      (cond ((not setting) 'not-db-config)\n", "      (cond ((not setting) 'out-of-domain)\n")]),
    m("S7", [(SET, STEP_DOMAIN, "            ((not (memv value (caddr setting))) 'no-call)\n")]),
    m("S8", [(SET, STEP_ELSE, STEP_ELSE.replace("(cadr setting)", "1005"))]),
    m("S9", [(SET, STEP_DOMAIN + STEP_NOCALL,
              "            ((and (eq? name 'enable-load-extension) (not (eq? value #t))) 'no-call)\n" + STEP_DOMAIN)]),
    # --- the sentinel ---
    m("Z2", [(SET, "(define db-config-sentinel -1)", "(define db-config-sentinel 2147483648)")]),
    m("Z3", [(SET, "(define db-config-sentinel -1)", "(define db-config-sentinel -1.0)")]),
    m("Z4", [(SET, "                 (cond ((eqv? cell db-config-sentinel) '())\n",
              "                 (cond ((eqv? cell -2) '())\n")]),
    # --- the verdict ---
    m("V3", [(SET, V_CODE, "    (cond ((not (= code 0)) (list 'error code))\n")]),
    m("V4", [(SET, V_CODE, "    (cond ((not (and (integer? code) (exact? code) (= (bitwise-and code 255) 0))) (list 'error code))\n")]),
    m("V5", [(SET, V_MATCH, "          ((eqv? cell (if expected 1 0)) 'match)\n")]),
    m("V6", [(SET, V_MATCH, "          ((eqv? cell expected) 'match)\n")]),
    m("V7", [(SET, V_ACTUAL, V_ACTUAL.replace("(cond ((eqv? cell db-config-sentinel) '())\n                       ", "(cond "))]),
    m("V8", [(SET, V_ACTUAL, V_ACTUAL.replace("((eqv? cell 1) #t)\n                       ((eqv? cell 0) #f)\n                       ", ""))]),
    m("V9", [(SET, V_ACTUAL, V_ACTUAL.replace("((eqv? cell 1) #t)", "((eqv? cell 1) #f)").replace("((eqv? cell 0) #f)", "((eqv? cell 0) #t)"))]),
    m("V10", [(SET, V_ACTUAL, V_ACTUAL.replace("(else cell)", "(else '())"))]),
    m("V11", [(SET, V_MISMATCH, "           (list 'mismatch name (if expected 1 0)\n")]),
    m("V12", [(SET, V_MISMATCH, "           (list 'mismatch 'db-config expected\n")]),
    m("V13", [(SET, V_CODE, "    (cond ((not (eqv? code 0)) (list 'error cell))\n")]),
    m("V14", [(SET, V_CODE + V_MATCH, V_MATCH + V_CODE)]),
    m("V15", [(SET, V_ACTUAL, """                 (cond ((eqv? cell 1) #t)
                       ((eqv? cell 0) #f)
                       ((eqv? cell db-config-sentinel) '())
                       (else cell)))))))""")]),
    # --- the join ---
    m("J2", [(SET, NAMES, NAMES[:-2] + "\n      enable-load-extension defensive dqs-dml dqs-ddl))"),
             (SET, "      (trusted-schema \"trusted_schema\" ((#t \"1\" 1) (#f \"0\" 0)))))",
              "      (trusted-schema \"trusted_schema\" ((#t \"1\" 1) (#f \"0\" 0)))\n"
              "      (enable-load-extension \"enable_load_extension\" ((#t \"1\" 1) (#f \"0\" 0)))\n"
              "      (defensive \"defensive\" ((#t \"1\" 1) (#f \"0\" 0)))\n"
              "      (dqs-dml \"dqs_dml\" ((#t \"1\" 1) (#f \"0\" 0)))\n"
              "      (dqs-ddl \"dqs_ddl\" ((#t \"1\" 1) (#f \"0\" 0)))))")]),
    m("J3", [(SET, "                        ((memq name seen) (list 'refused 'setting-given-twice name))\n",
              "                        ((memq name seen) (list 'refused 'setting-given-twice name))\n"
              "                        ((memq name db-config-setting-names) (loop (cdr rest) (cons name seen) capacity first steps))\n"),
             (SET, "                  (cond ((not (memq name setting-names)) (list 'refused 'unknown-setting name))",
              "                  (cond ((not (or (memq name setting-names) (memq name db-config-setting-names))) (list 'refused 'unknown-setting name))")]),
    m("J4", [(SET, NAMES, NAMES[:-2] + " enable-fkey))")]),
    # --- the condition ---
    m("C3", [(CON, TYPE, TYPE.replace("&sqlite-extensions-unavailable &chez-sqlite3-error", "&sqlite-extensions-unavailable &error"))]),
    m("C4", [(CON, TYPE, TYPE.replace("sqlite-extensions-unavailable?)", "unchecked-sqlite-extensions-unavailable?)")
              + "\n  (define sqlite-extensions-unavailable? chez-sqlite3-error?)")]),
    m("C5", [(CON, TYPE, """  (define-condition-type &sqlite-extensions-unavailable &chez-sqlite3-error
    unchecked-make-sqlite-extensions-unavailable sqlite-extensions-unavailable?
    (library unchecked-sqlite-extensions-unavailable-library))
  (define (make-sqlite-extensions-unavailable) (unchecked-make-sqlite-extensions-unavailable #f))""")]),
    m("C6", [(CON, RAISE_BODY, """    (check-raise-who 'raise-extensions-unavailable who)
    (raise (condition (make-sqlite-extensions-unavailable) (make-who-condition who)
                      (make-irritants-condition""")]),
    m("C7", [(CON, RAISE_BODY, RAISE_BODY.replace("(make-who-condition who)", "(make-sqlite-extensions-unavailable)"))]),
    m("C8", [(CON, RAISE_BODY, RAISE_BODY.replace("(make-who-condition who)", "(make-who-condition 'open-database)"))]),
    m("C9", [(CON, RAISE_BODY, RAISE_BODY.replace("    (check-raise-who 'raise-extensions-unavailable who)\n", ""))]),
    m("C10", [(CON, RAISE_BODY, RAISE_BODY.replace("(raise (condition", "(raise-continuable (condition"))]),
    m("C11", [(CON, "\"this libsqlite3 has no", "(string-append (symbol->string who) \": this libsqlite3 has no"),
              (CON, "that has it\"))))", "that has it\")))))")]),
    m("C12", [(CON, RAISE_BODY, RAISE_BODY.replace("(make-who-condition who)", "(make-who-condition who) (make-irritants-condition (list who))"))]),
    m("C13", [(CON, RAISE_BODY, RAISE_BODY.replace("(raise (condition (make-sqlite-extensions-unavailable)", "(raise (condition (make-sqlite-transaction-ended)"))]),
    # --- the exports ---
    m("E1", [(TOP, "   sqlite-transaction-ended?\n\n",
              "   sqlite-transaction-ended?\n   ;; sqlite-extensions-unavailable? : Any -> Boolean\n   sqlite-extensions-unavailable?\n\n"),
             (TOP, "(only (chez-sqlite3 private conditions) sqlite-transaction-ended?)",
              "(only (chez-sqlite3 private conditions) sqlite-transaction-ended? sqlite-extensions-unavailable?)")],
      ["test-public", "test-reference"]),
    m("E2", [(SET, "          db-config-verdict)", "          db-config-verdict step-for)")], ["test-settings"]),
    m("E3", [(CON, "          sqlite-extensions-unavailable? raise-extensions-unavailable\n",
              "          sqlite-extensions-unavailable? raise-extensions-unavailable check-raise-who\n")], ["test-conditions"]),
    # --- the suite's own fixture ---
    m("F1", [(TS, " (enable-comments . 1022) (fp-digits . 1023)))", " (enable-comments . 1022)))")], ["test-settings"]),
]

MUTANTS += [
    # the domain checked before the name, against a fixed (#t #f)
    m("S10", [(SET, "      (cond ((not setting) 'not-db-config)\n" + STEP_DOMAIN,
               "      (cond ((not (memv value '(#t #f))) 'out-of-domain)\n"
               "            ((not setting) 'not-db-config)\n")]),
]

OPEN = "src/chez-sqlite3/private/open.sls"
MUTANTS += [
    # the open made before the checks' refusal, and closed before it is
    # raised: a copy of open.sls, never the tree's
    m("J5", [(OPEN, "(checked who filename arguments)))\n        (let ((db (opened-database",
              "(guard (e (#t (close-connection who (opened-database who (connection-outcome who filename 65542 32 #f)))\n"
              "                                   (raise e)))\n"
              "                    (checked who filename arguments))))\n        (let ((db (opened-database")],
      ["test-open-settings"]),
]

MUTANTS += [
    # the predicate holds of any condition
    m("C14", [(CON, TYPE, TYPE.replace("sqlite-extensions-unavailable?)", "unchecked-sqlite-extensions-unavailable?)")
               + "\n  (define sqlite-extensions-unavailable? condition?)")]),
]

# The red runs with the final suites, made by mut.py red BASE, never by
# prepare: a copy of the tree with the base's settings.sls and conditions.sls
# (REDA), and that copy with RED's stubs (REDB).
MUTANTS += [m("REDA", []), m("REDB", [])]

EXT_MSG = ('"this libsqlite3 has no sqlite3_load_extension, so no connection of it can load an '
           'extension; CHEZ_SQLITE3_LIBRARY can name one that has it"')
TXN_MSG = '"the body returned after its transaction had ended under it"'
CLOSED_MSG = '"the connection or statement is closed"'

MUTANTS += [
    # The slice's review's (Opus): setting-names made improper, read at the
    # suite's top level; the new type's fixed message made "", and made
    # &sqlite-closed's. Byte for byte the review's build/review-mut copies.
    m("P-TOP", [(SET, NAMES, NAMES.replace("trusted-schema statement-cache", "trusted-schema . statement-cache"))]),
    m("P-MSG", [(CON, EXT_MSG, '""')]),
    m("P-MSG2", [(CON, EXT_MSG, CLOSED_MSG)]),
    # raise-transaction-ended's message, held by the same row: made "", and
    # made &sqlite-closed's
    m("P-MSG3", [(CON, TXN_MSG, '""')]),
    m("P-MSG4", [(CON, TXN_MSG, CLOSED_MSG)]),
]
