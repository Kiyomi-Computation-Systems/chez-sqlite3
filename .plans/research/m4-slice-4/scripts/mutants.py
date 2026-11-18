"""M4 slice 4's plants, each one or more edits (PATH, OLD, NEW) applied to a
copy of the tree, OLD matching its file's text exactly once. Each runs
DEFAULT_SUITES unless it names its own. The plan's section 4.7 names the
load's plants; the rest are the builder's, one at least at every site of
(chez-sqlite3 private extension)."""

E = "src/chez-sqlite3/private/extension.sls"
C = "src/chez-sqlite3/private/connection.sls"
N = "src/chez-sqlite3/private/native.sls"
P = "src/chez-sqlite3.sls"

DEFAULT_SUITES = ["test-load-extension", "test-load-extension-engines", "test-public", "test-reference",
                  "test-never-loads", "test-docs", "test-library-loading-real"]

CHECKED_OPEN_CALL = "      (checked-open db)\n"
LET_FILE_PROC = """      (let* ((file (checked-path path))
             (proc (and (pair? entries) (checked-entry (car entries)))))
        (checked-opt-in db)
"""
CLAIM_LINE = "    (let ((claim (made-claim)))\n"
SECTION_CLAIM = """     (if (not (claim 0 #t))
         '(refused)"""
FREE_BLOCK = """                       (let ((read (guard (c (#t (list 'raised c)))
                                     (list 'copied (copy message)))))
                         (sqlite3-free message)
                         read))))"""
BASE = """               (let ((base (if (eq? (car text) 'copied)
                               (cadr text)
                               (or (c-string->string (sqlite3-errstr code)) "")))"""
MORE = """                     (more (and (not (eqv? (cadr codes) (caddr codes)))
                                (c-string->string (sqlite3-errmsg handle)))))"""
CODES = """                      (let* ((before (sqlite3-extended-errcode handle))
                             (code (load handle file proc slot))
                             (after (sqlite3-extended-errcode handle)))
                        (list code before after))))))"""

MUTANTS = [
    # --- the first three checks ---------------------------------------------------------
    {"name": "C01-open-check-dropped",
     "edits": [(E, CHECKED_OPEN_CALL, "")]},
    {"name": "C02-open-check-after-arguments",
     "edits": [(E, CHECKED_OPEN_CALL, ""),
               (E, "        (checked-opt-in db)\n", "        (checked-open db)\n        (checked-opt-in db)\n")]},
    {"name": "C03-open-check-raises-inside",
     "edits": [(E, """    (let ((outcome (critical-section
                    (guard (c (#t (list 'raised c)))
                      (call-with-open-handle who db (lambda (handle) '(open)))))))""",
                """    (let ((outcome (critical-section
                      (call-with-open-handle who db (lambda (handle) '(open))))))""")]},
    {"name": "O01-both-owner-checks-dropped",
     "edits": [(C, """    (check-owned who db)
    (let* ((finished #f)""", """    (unless (database? db)
      (assertion-violation who "not a database" 'not-a-database (shown-value db)))
    (let* ((finished #f)""")]},
    # --- the path ---------------------------------------------------------------------------
    {"name": "C19-open-check-outside-a-section",
     "edits": [(E, """    (let ((outcome (critical-section
                    (guard (c (#t (list 'raised c)))
                      (call-with-open-handle who db (lambda (handle) '(open)))))))""",
                """    (let ((outcome (begin
                    (guard (c (#t (list 'raised c)))
                      (call-with-open-handle who db (lambda (handle) '(open)))))))""")]},
    {"name": "C04-path-string-check-dropped",
     "edits": [(E, """    (unless (string? path)
      (assertion-violation who "the extension's path is a string" 'path-not-a-string
                           (shown-value path)))
""", "")]},
    {"name": "C05-path-nul-check-dropped",
     "edits": [(E, """      (when (holds-nul? copy)
        (assertion-violation who "the extension's path holds U+0000, where C would read its end"
                             'path-holds-nul (shown-value copy)))
""", "")]},
    {"name": "C06-absolute-check-dropped",
     "edits": [(E, """      (unless (and (> (string-length copy) 0) (char=? (string-ref copy 0) #\\/))""",
                """      (unless #t""")]},
    {"name": "C07-absolute-lets-a-dot-through",
     "edits": [(E, """(char=? (string-ref copy 0) #\\/))""",
                """(memv (string-ref copy 0) '(#\\/ #\\.)))""")]},
    {"name": "C08-path-copy-unused",
     "edits": [(E, """                             'path-not-absolute (shown-value copy)))
      copy))""", """                             'path-not-absolute (shown-value copy)))
      path))""")]},
    {"name": "C09-empty-path-let-through",
     "edits": [(E, """(unless (and (> (string-length copy) 0) (char=? (string-ref copy 0) #\\/))""",
                """(unless (or (= (string-length copy) 0) (char=? (string-ref copy 0) #\\/))""")]},
    {"name": "C09b-nul-after-absolute",
     "edits": [(E, """      (when (holds-nul? copy)
        (assertion-violation who "the extension's path holds U+0000, where C would read its end"
                             'path-holds-nul (shown-value copy)))
      (unless (and (> (string-length copy) 0) (char=? (string-ref copy 0) #\\/))
        (assertion-violation who
                             "the extension's path is absolute, as /opt/app/lib/ext.so is: a relative path or a bare name would be the working directory's or the loader's own search's choice"
                             'path-not-absolute (shown-value copy)))""",
                """      (unless (and (> (string-length copy) 0) (char=? (string-ref copy 0) #\\/))
        (assertion-violation who
                             "the extension's path is absolute, as /opt/app/lib/ext.so is: a relative path or a bare name would be the working directory's or the loader's own search's choice"
                             'path-not-absolute (shown-value copy)))
      (when (holds-nul? copy)
        (assertion-violation who "the extension's path holds U+0000, where C would read its end"
                             'path-holds-nul (shown-value copy)))""")]},
    {"name": "C09c-nul-scan-skips-the-last",
     "edits": [(E, """      (and (< i (string-length s))""", """      (and (< (+ i 1) (string-length s))""")]},
    {"name": "C18-path-refusal-who",
     "edits": [(E, """      (assertion-violation who "the extension's path is a string" 'path-not-a-string""",
                """      (assertion-violation 'load-extension "the extension's path is a string" 'path-not-a-string""")]},
    # --- the entry point ----------------------------------------------------------------------
    {"name": "C10-entry-string-check-dropped",
     "edits": [(E, """    (unless (string? entry)
      (assertion-violation who "the entry point is a string, its C name" 'entry-point-not-a-string
                           (shown-value entry)))
""", "")]},
    {"name": "C11-entry-nul-check-dropped",
     "edits": [(E, """      (when (holds-nul? copy)
        (assertion-violation who "the entry point holds U+0000, where C would read its end"
                             'entry-point-holds-nul (shown-value copy)))
""", "")]},
    {"name": "C12-non-string-entry-ignored",
     "edits": [(E, "(proc (and (pair? entries) (checked-entry (car entries)))))",
                "(proc (and (pair? entries) (string? (car entries)) (checked-entry (car entries)))))")]},
    {"name": "O02-entry-before-path",
     "edits": [(E, LET_FILE_PROC, """      (let* ((proc (and (pair? entries) (checked-entry (car entries))))
             (file (checked-path path)))
        (checked-opt-in db)
""")]},
    # --- the opt-in ---------------------------------------------------------------------------
    {"name": "C13-opt-in-check-dropped",
     "edits": [(E, "        (checked-opt-in db)\n", "")]},
    {"name": "C14-opt-in-before-arguments",
     "edits": [(E, CHECKED_OPEN_CALL, "      (checked-open db)\n      (checked-opt-in db)\n"),
               (E, "        (checked-opt-in db)\n", "")]},
    {"name": "C15-opt-in-raised-inside-a-section",
     "edits": [(E, "        (checked-opt-in db)\n", "        (critical-section (checked-opt-in db))\n")]},
    {"name": "C16-opt-in-message-without-the-fix",
     "edits": [(E, "open it with (enable-load-extension . #t) in its settings list",
                "open it with the opt-in in its settings list")]},
    {"name": "C17-opt-in-rule-renamed",
     "edits": [(E, "                           'extension-loading-not-enabled)))",
                "                           'extensions-not-enabled)))")]},
    # --- the claim and the section ---------------------------------------------------------------
    {"name": "S01-claim-dropped",
     "edits": [(E, SECTION_CLAIM, """     (if #f
         '(refused)""")]},
    {"name": "S02-claim-outside-the-section",
     "edits": [(E, """    (critical-section
     (if (not (claim 0 #t))
         '(refused)
         (guard (c (#t (list 'raised c)))""", """    (if (not (claim 0 #t))
         '(refused)
     (critical-section
         (guard (c (#t (list 'raised c)))""")]},
    {"name": "S03-flag-set-after-the-section",
     "edits": [(E, CLAIM_LINE, "    (let* ((claimed #f) (claim (lambda (n last?) (not claimed))))\n"),
               (E, "        (let ((outcome (load-section claim db file proc load copy)))\n",
                "        (let ((outcome (load-section claim db file proc load copy)))\n          (set! claimed #t)\n")]},
    {"name": "S04-claim-made-after-the-checks",
     "edits": [(E, CLAIM_LINE, "    (let ()\n"),
               (E, "        (let ((outcome (load-section claim db file proc load copy)))\n",
                "        (let ((outcome (load-section (made-claim) db file proc load copy)))\n")]},
    {"name": "S05-call-outside-the-claims-section",
     "edits": [(E, """    (critical-section
     (if (not (claim 0 #t))
         '(refused)
         (guard (c (#t (list 'raised c)))""", """    (if (not (critical-section (claim 0 #t)))
         '(refused)
         (guard (c (#t (list 'raised c)))"""),
               (E, "                       (called load copy handle c-file 0))))))))))",
                "                       (called load copy handle c-file 0)))))))))")]},
    {"name": "S10-claim-section-unwrapped",
     "edits": [(E, """    (critical-section
     (if (not (claim 0 #t))
         '(refused)""", """    (begin
     (if (not (claim 0 #t))
         '(refused)""")]},
    {"name": "S06-claim-at-position-1",
     "edits": [(E, "     (if (not (claim 0 #t))", "     (if (not (claim 1 #t))")]},
    {"name": "S07-claim-not-last",
     "edits": [(E, "     (if (not (claim 0 #t))", "     (if (not (claim 0 #f))")]},
    {"name": "S08-refused-answers-nothing",
     "edits": [(E, "            ((refused) (raise-closed who))", "            ((refused) (if #f #f))")]},
    {"name": "S09-refused-another-condition",
     "edits": [(E, "            ((refused) (raise-closed who))",
                "            ((refused) (assertion-violation who \"refused\" 'refused))")]},
    # --- the call -------------------------------------------------------------------------------
    {"name": "K01-entry-null-always",
     "edits": [(E, "                         (lambda (c-proc) (called load copy handle c-file c-proc)))",
                "                         (lambda (c-proc) (called load copy handle c-file 0)))")]},
    {"name": "K02-entry-given-when-absent",
     "edits": [(E, "                       (called load copy handle c-file 0))))))))))",
                "                       (called load copy handle c-file c-file))))))))))")]},
    {"name": "K03-code-from-the-connection",
     "edits": [(E, "                        (list code before after))))))",
                "                        (list (if (eqv? code 0) code after) before after))))))")]},
    {"name": "K04-before-read-after-the-call",
     "edits": [(E, CODES, """                      (let* ((code (load handle file proc slot))
                             (before (sqlite3-extended-errcode handle))
                             (after (sqlite3-extended-errcode handle)))
                        (list code before after))))))""")]},
    {"name": "K05-connection-message-dropped",
     "edits": [(E, MORE, "                     (more #f))")]},
    {"name": "K06-connection-message-always",
     "edits": [(E, MORE, """                     (more (c-string->string (sqlite3-errmsg handle))))""")]},
    {"name": "K07-message-from-errmsg",
     "edits": [(E, BASE, """               (let ((base (or (c-string->string (sqlite3-errmsg handle)) ""))""")]},
    {"name": "K08-no-errstr-for-an-empty-slot",
     "edits": [(E, """                               (or (c-string->string (sqlite3-errstr code)) "")))""",
                """                               ""))""")]},
    {"name": "K09-joined-always-direct",
     "edits": [(E, """          (else (string-append base ": " more))))""",
                """          (else (string-append base more))))""")]},
    {"name": "K10-joined-always-colon",
     "edits": [(E, """           (string-append base more))
          (else""", """           (string-append base ": " more))
          (else""")]},
    {"name": "K11-not-an-error-unchecked",
     "edits": [(E, "              ((not (names-error? code)) (list 'not-an-error code))\n", "")]},
    {"name": "K12-no-error-taken-as-success",
     "edits": [(E, "              ((eqv? code sqlite-ok) '(loaded))",
                "              ((not (names-error? code)) '(loaded))")]},
    # --- the message's free ---------------------------------------------------------------------------
    {"name": "F01-message-never-freed",
     "gate": True,
     "suites": ["test-load-extension"],
     "edits": [(E, "                         (sqlite3-free message)\n", "")]},
    {"name": "F02-freed-only-on-failure",
     "gate": True,
     "suites": ["test-load-extension"],
     "edits": [(E, "                         (sqlite3-free message)\n",
                "                         (unless (eqv? code sqlite-ok) (sqlite3-free message))\n")]},
    {"name": "F03-not-freed-when-the-copy-raises",
     "gate": True,
     "suites": ["test-load-extension"],
     "edits": [(E, FREE_BLOCK, """                       (guard (c (#t (list 'raised c)))
                         (let ((read (list 'copied (copy message))))
                           (sqlite3-free message)
                           read)))))""")]},
    {"name": "F04-copy-unguarded",
     "edits": [(E, FREE_BLOCK, """                       (let ((read (list 'copied (copy message))))
                         (sqlite3-free message)
                         read))))""")]},
    {"name": "F05-freed-before-the-copy",
     "gate": True,
     "suites": ["test-load-extension"],
     "edits": [(E, FREE_BLOCK, """                       (begin
                         (sqlite3-free message)
                         (guard (c (#t (list 'raised c)))
                           (list 'copied (copy message)))))))""")]},
    # --- the raise ------------------------------------------------------------------------------
    {"name": "R02-failure-raised-inside",
     "edits": [(E, "                 (list 'failed code (joined base more))))))))",
                "                 (raise-sqlite-error who code (joined base more) #f #f)))))))")]},
    # --- the binding and the library -------------------------------------------------------------------
    {"name": "N01-load-bound-plain",
     "suites": ["test-native"],
     "edits": [(N, """(foreign-procedure __collect_safe "sqlite3_load_extension" (uptr uptr uptr uptr) int)""",
                """(foreign-procedure "sqlite3_load_extension" (uptr uptr uptr uptr) int)""")]},
    {"name": "D01-binding-used-at-the-librarys-load",
     "edits": [(E, "  (define who 'load-extension!)\n",
                "  (define who 'load-extension!)\n\n  (define bound (if (procedure? sqlite3-load-extension) sqlite3-load-extension (car sqlite3-load-extension)))\n")]},
    {"name": "P01-verb-not-exported",
     "edits": [(P, """   ;; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))
   load-extension!
""", ""),
               (P, "          (only (chez-sqlite3 private extension) load-extension!)\n", "")]},
    {"name": "P02-signature-comment-changed",
     "edits": [(P, ";; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))",
                ";; load-extension! : Database String -> Void")]},
    # --- SQL's load_extension() -----------------------------------------------------------------
    {"name": "Q01-sql-loading-turned-on",
     "edits": [(C, "(only (chezscheme) critical-section dynamic-wind get-thread-id)",
                "(only (chezscheme) critical-section dynamic-wind get-thread-id foreign-procedure)"),
               (C, "(let ((db (make-database handle (get-thread-id) capacity opt-in)))",
                "(let ((db (make-database handle (get-thread-id) capacity opt-in)))\n"
                "                          (when opt-in ((foreign-procedure \"sqlite3_enable_load_extension\" (uptr int) int) handle 1))")]},
    # --- the build -------------------------------------------------------------------------------
    {"name": "X02-no-header",
     "env": "env -u C_INCLUDE_PATH -u CPATH",
     "suites": ["test-load-extension", "test-load-extension-engines"],
     "edits": []},
    {"name": "X01-no-compiler",
     "env": "CC=false",
     "suites": ["test-load-extension", "test-load-extension-engines"],
     "edits": []},
]
