#!/usr/bin/env python3
"""M4 slice 5's mutants: each a copy of the worktree under build/mut/NAME,
made without .git and build/, with a list of edits, each checked to match its
file exactly once, and a list of runs. Writes build/mut/NAME/RUN.sh, which
the container runs from the worktree's root.

  python3 -I mutants.py WORKTREE [NAME ...]

The builder wrote it against the tree before the rebase onto the close fix.
The lead moved FV01, FV02, FV07, FV08, FV10 and J03 to the rows as the
review left them, each planting a value a wrong rule would give, and
retired F10, F11, X01 and X02, which planted the workaround and the
candidate fix: with no NAME they are skipped, and named, their edits match
nothing (the slice's log, "After the close fix" and "The review's fixes").
"""
import os, subprocess, sys

WT = sys.argv[1]
ONLY = set(sys.argv[2:])

LIBS = {
    'guix': None,
    'floor': 'build/m3-floor',
    'current': 'build/m4-current',
    'fts5': 'build/m4-current-fts5',
    'badlib': 'build/no-such-library',
}
ALL = ['guix', 'floor', 'current', 'fts5']
FTS = 'tests/test-fts5.sps'
JSON = 'tests/test-json.sps'
CIS = 'tests/test-ci-sqlite.sps'

def suite(s, libs=ALL):
    return [('suite', s, l) for l in libs]

M = []
def mut(name, guards, edits, runs):
    M.append((name, guards, edits, runs))

# --- FTS5: the brief's plants ------------------------------------------------------------
mut('F01', "the FTS5 rows run only where the check says yes (run whatever it says)",
    [(FTS, "(case path\n  ((rows) (fts5-rows))\n  ((refusal) (fts5-refusal))\n  (else 'neither))",
      "(fts5-rows)")],
    suite(FTS))
mut('F02', "the check's choice (inverted: the rows where it says no, the refusal where yes)",
    [(FTS, "  ((rows) (fts5-rows))\n  ((refusal) (fts5-refusal))", "  ((refusal) (fts5-rows))\n  ((rows) (fts5-refusal))")],
    suite(FTS))
mut('F03', "the refusal's code (expected misuse, not error)",
    [(FTS, """    (step-error "create virtual table probe using fts5(body)")
    (answer""", """    (list 'prepared 'step-raised (list 'sqlite-error 'step! 'misuse 'misuse "create virtual table probe using fts5(body)" #f))
    (answer""")],
    suite(FTS, ['floor', 'current']))
mut('F04', "the refusal comes at step (expected at prepare, from call-with-statement)",
    [(FTS, """    (step-error "create virtual table probe using fts5(body)")
    (answer""", """    (list 'sqlite-error 'call-with-statement 'error 'error "create virtual table probe using fts5(body)" #f)
    (answer""")],
    suite(FTS, ['floor', 'current']))
mut('F05', "the option and module check reads both (the option alone)",
    [(FTS, "  (if (or (and (eq? option #t) (eqv? module 1))\n          (and (eq? option #f) (eqv? module 0)))",
      "  (if (or (eq? option #t) (eq? option #f))")],
    suite(FTS))
mut('F06', "the option and module check reads both (the module alone)",
    [(FTS, "  (if (or (and (eq? option #t) (eqv? module 1))\n          (and (eq? option #f) (eqv? module 0)))",
      "  (if (or (eqv? module 1) (eqv? module 0))")],
    suite(FTS))
mut('F07', "the path is chosen only where they agree (by the option alone)",
    [(FTS, "  (cond ((not (eq? (agreement fts5-option fts5-module) 'agree)) 'neither)\n        ((eq? fts5-option #t) 'rows)",
      "  (cond ((eq? fts5-option #t) 'rows)")],
    suite(FTS))
mut('F08', "the module probe names fts5 (fts4)",
    [(FTS, "pragma_module_list where name = 'fts5'\")", "pragma_module_list where name = 'fts4'\")")],
    suite(FTS))
mut('F09', "the option probe names ENABLE_FTS5 (ENABLE_FTS4)",
    [(FTS, '(answer (lambda () (sqlite-compile-option? "ENABLE_FTS5"))))', '(answer (lambda () (sqlite-compile-option? "ENABLE_FTS4"))))')],
    suite(FTS))
mut('F10', "each row's drop of its FTS5 tables (dropped nothing)",
    [(FTS, '(execute! db (string-append "drop table if exists " table))', "'kept")],
    suite(FTS, ['guix', 'fts5']))
mut('F11', "the close's expected failure is marked (the mark dropped)",
    [(FTS, "  (test-expect-fail 1)\n", "")],
    suite(FTS, ['guix', 'fts5']))

# The library's close made to let sqlite3_close judge first, counting untracked
# statements only when it fails: a candidate fix, in the copy, for the lead.
CLOSE_OLD = """                    (let* ((failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db)))
                           (untracked (statements-on handle)))
                      (if (> untracked 0)
                          (list 'untracked untracked)
                          (let ((rc (sqlite3-close handle)))
                            (if (eqv? rc sqlite-ok)
                                (begin
                                  (set-database-handle! db #f)
                                  (let ((double-free (guard (c (#t c))
                                                       (count-down! 'connection)
                                                       #f)))
                                    (cond (failure (list 'finalize-failed failure))
                                          (double-free (list 'double-free double-free))
                                          (else '(closed)))))
                                (cons 'failed (details-of rc handle)))))))))"""
CLOSE_NEW = """                    (let* ((failure (finalize-tracked! db handle))
                           (emptied (statement-cache-clear! (unchecked-database-cache db)))
                           (rc (sqlite3-close handle)))
                      (if (eqv? rc sqlite-ok)
                          (begin
                            (set-database-handle! db #f)
                            (let ((double-free (guard (c (#t c))
                                                 (count-down! 'connection)
                                                 #f)))
                              (cond (failure (list 'finalize-failed failure))
                                    (double-free (list 'double-free double-free))
                                    (else '(closed)))))
                          (let ((untracked (statements-on handle)))
                            (if (> untracked 0)
                                (list 'untracked untracked)
                                (cons 'failed (details-of rc handle)))))))))"""
CONN = 'src/chez-sqlite3/private/connection.sls'
mut('X01', "the expected failure flips once the close closes a connection FTS5 used (candidate fix: sqlite3_close first, untracked counted after a failure)",
    [(CONN, CLOSE_OLD, CLOSE_NEW)],
    suite(FTS, ['guix', 'fts5']) + [('suite', s, 'guix') for s in
        ['tests/test-connection.sps', 'tests/test-connection-cache.sps', 'tests/test-open-settings.sps',
         'tests/test-interrupt-close.sps', 'tests/test-statement.sps', 'tests/test-interrupt-database.sps']])
mut('X02', "X01's fix with the mark and the drops gone: every FTS5 row passes",
    [(CONN, CLOSE_OLD, CLOSE_NEW),
     (FTS, "  (test-expect-fail 1)\n", ""),
     (FTS, '(execute! db (string-append "drop table if exists " table))', "'kept")],
    suite(FTS, ['guix', 'fts5']))

# --- FTS5: each row's value planted --------------------------------------------------------
def fv(name, guards, old, new, libs=['guix', 'fts5']):
    mut(name, guards, [(FTS, old, new)], suite(FTS, libs))
fv('FV01', "MATCH ordered by rank (expected rowid order, 2 then 3)",
   """    '(#(3) #(2))
    (answer
     (lambda ()
       (with-docs
        (lambda (db) (query db "select rowid from docs where docs match 'sqlite OR rank' order by rank"))))))""",
   """    '(#(2) #(3))
    (answer
     (lambda ()
       (with-docs
        (lambda (db) (query db "select rowid from docs where docs match 'sqlite OR rank' order by rank"))))))""")
fv('FV02', "bm25's order is rank's (expected rowid order, 2 then 3)", "    '((3 2) #t)", "    '((2 3) #t)")
fv('FV03', "unicode61 folds creme to crème (expected no match)", "    '((#(1)) (#(1)) (#(1)))", "    '((#(1)) (#(1)) ())")
fv('FV04', "remove_diacritics 0 keeps them (expected cafe to match)", "    '(#(0) #(1))", "    '(#(1) #(1))")
fv('FV05', "highlight() answers the text as stored (expected the folded cafe)",
   """    '(#("the [café] serves crème brûlée")""", """    '(#("the [cafe] serves crème brûlée")""")
fv('FV06', "a prefix query (expected searc* as a whole term: nothing)",
   """    '(#(2) #(3))
    (answer (lambda () (with-docs (lambda (db) (matching db "searc*"))))))""",
   """    '()
    (answer (lambda () (with-docs (lambda (db) (matching db "searc*"))))))""")
fv('FV07', "a phrase query (expected an AND's answer: the reversed phrase matching 2)",
   """    '((#(2)) ())
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((phrase""",
   """    '((#(2)) (#(2)))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((phrase""")
fv('FV08', "a column filter (expected title:sqlite to match the bodies' 2 and 3)",
   """    '((#(2)) ())
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((second""",
   """    '((#(2)) (#(2) #(3)))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((second""")
fv('FV09', "NOT (expected it ignored: 2 and 3)", "    '(#(3))\n    (answer (lambda () (with-docs (lambda (db) (matching db \"sqlite NOT fts5\"))))))",
   "    '(#(2) #(3))\n    (answer (lambda () (with-docs (lambda (db) (matching db \"sqlite NOT fts5\"))))))")
fv('FV10', "a bound MATCH reaches FTS5 whole (expected café lost: 2 and 3)",
   """    '(#(1 "text") #(2 "text") #(3 "text"))""", """    '(#(2 "text") #(3 "text"))""")
fv('FV11', "a query's syntax error names query (expected step!)",
   "    (list 'sqlite-error 'query 'error 'error (caddr syntax-errors) #f)",
   "    (list 'sqlite-error 'step! 'error 'error (caddr syntax-errors) #f)")
fv('FV12', "a query's syntax error is code error (expected misuse)",
   "    (map step-error syntax-errors)",
   "    (map (lambda (sql) (list 'prepared 'step-raised (list 'sqlite-error 'step! 'misuse 'misuse sql #f))) syntax-errors)")
fv('FV13', "delete and update reach the index (expected neither applied)", "    '((#(3)) #(2))", "    '((#(2)) #(3))")
fv('FV14', "the create's step answers done (expected a row)", "    '(prepared done)\n", "    '(prepared row)\n")

# --- both suites: the load row and the counts row -------------------------------------------
mut('P01', "the load row reads the load (CHEZ_SQLITE3_LIBRARY naming no file)", [],
    [('suite', FTS, 'badlib'), ('suite', JSON, 'badlib')])
mut('P02', "the counts row at the load reads the counts (a connection opened before it)",
    [(FTS, '(test-begin "fts5")\n', '(test-begin "fts5")\n(define leaked (eval \'(open-database ":memory:") (environment \'(chez-sqlite3))))\n'),
     (JSON, '(test-begin "json")\n', '(test-begin "json")\n(define leaked (eval \'(open-database ":memory:") (environment \'(chez-sqlite3))))\n')],
    [('suite', FTS, 'guix'), ('suite', JSON, 'guix')])

# --- the lane ------------------------------------------------------------------------------
BUILD = 'scripts/ci/build-sqlite.sh'
CHECK = 'scripts/ci/check-sqlite.sh'
mut('L01', "the current lane compiles FTS5 in (the flag dropped from its line)",
    [(BUILD, '"$cc" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -Wl,-z,defs \\',
      '"$cc" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs \\')],
    [('suite', CIS, 'guix'), ('build-current',)])
mut('L02', "the floor's line keeps SQLite's defaults (FTS5 added to it too)",
    [(BUILD, '  "$cc" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs -o "$prefix/lib/libsqlite3.so.0" \\',
      '  "$cc" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -Wl,-z,defs -o "$prefix/lib/libsqlite3.so.0" \\')],
    [('suite', CIS, 'guix')])
mut('L03', "check-sqlite.sh's current list holds ENABLE_FTS5 (the line dropped)",
    [(CHECK, "DIRECT_OVERFLOW_READ\nENABLE_FTS5\nMALLOC_SOFT_LIMIT=1024", "DIRECT_OVERFLOW_READ\nMALLOC_SOFT_LIMIT=1024")],
    [('suite', CIS, 'guix'), ('check-current', 'm4-current'), ('check-current', 'm4-current-fts5')])
mut('L04', "ENABLE_FTS5 in its place in SQLite's order (moved before DIRECT_OVERFLOW_READ)",
    [(CHECK, "DIRECT_OVERFLOW_READ\nENABLE_FTS5\nMALLOC_SOFT_LIMIT=1024", "ENABLE_FTS5\nDIRECT_OVERFLOW_READ\nMALLOC_SOFT_LIMIT=1024")],
    [('suite', CIS, 'guix'), ('check-current', 'm4-current-fts5')])
mut('L05', "the floor's list keeps SQLite's defaults (ENABLE_FTS5 added to it)",
    [(CHECK, "DIRECT_OVERFLOW_READ\nMALLOC_SOFT_LIMIT=1024\nMAX_ATTACHED=10\nMAX_COLUMN=2000\nMAX_COMPOUND_SELECT=500\nMAX_DEFAULT_PAGE_SIZE=8192\nMAX_EXPR_DEPTH=1000\nMAX_FUNCTION_ARG=127",
      "DIRECT_OVERFLOW_READ\nENABLE_FTS5\nMALLOC_SOFT_LIMIT=1024\nMAX_ATTACHED=10\nMAX_COLUMN=2000\nMAX_COMPOUND_SELECT=500\nMAX_DEFAULT_PAGE_SIZE=8192\nMAX_EXPR_DEPTH=1000\nMAX_FUNCTION_ARG=127")],
    [('suite', CIS, 'guix'), ('check-floor',)])
mut('L06', "the flag goes to the current role (given when the role is the floor)",
    [(BUILD, 'if [ "$role" = current ]; then\n  "$cc"', 'if [ "$role" = floor ]; then\n  "$cc"')],
    [('suite', CIS, 'guix')])

# --- JSON: each row's value planted ---------------------------------------------------------
def jv(name, guards, old, new, libs=['guix', 'floor']):
    mut(name, guards, [(JSON, old, new)], suite(JSON, libs))
jv('J01', "OMIT_JSON's row reads the predicate (expected #f for both, as a predicate answering #f to all)",
   "  '(#f #t)\n", "  '(#f #f)\n")
jv('J02', "json() minifies (expected the literal as written)",
   """  '#("{\\"a\\":[1,2.5,\\"x\\",null,true]}")""", """  '#(" { \\"a\\" : [1, 2.5, \\"x\\", null, true] } ")""")
jv('J03', "json() minifies a bound string (expected it unchanged)",
   """  '#("[1,2]" 1 "text")""", """  '#("[1, 2]" 1 "text")""")
jv('J04', "malformed JSON fails at step (expected at prepare)",
   """  (step-error "select json('{')")""", """  '(sqlite-error call-with-statement error error "select json('{')" #f)""")
jv('J05', "malformed JSON through query-row names query-row (expected step!)",
   """  '(sqlite-error query-row error error "select json('{')" #f)""", """  '(sqlite-error step! error error "select json('{')" #f)""")
jv('J06', "a bound BLOB that is no JSONB is refused at step (expected read, a row)",
   """  (step-error "select json(?1)")""", """  '(prepared row)""")
jv('J07', "-> answers JSON text (expected the SQL value, as ->> answers)",
   """  '#("\\"é\\"" "é")""", """  '#("é" "é")""")
jv('J08', "->> answers a REAL as a flonum (expected the exact 5/2)",
   """  '#(2.5 8)""", """  '#(5/2 8)""")
jv('J09', "json_each's values keep their types (expected x's 1 as the flonum 1.0)",
   """  '(#("x" 1 "integer")""", """  '(#("x" 1.0 "integer")""")
jv('J10', "jsonb() answers a BLOB as a bytevector (expected its last byte one more)",
   """  '#(#vu8(76 23 97 19 49) "blob" "text")""", """  '#(#vu8(76 23 97 19 50) "blob" "text")""")
jv('J11', "a bound bytevector binds as a BLOB (expected it bound as TEXT)",
   """  '#("{}" 1 "blob")""", """  '#("{}" 1 "text")""")
jv('J12', "1e400 and -1e400 answer +inf.0 and -inf.0 (expected swapped)",
   """  '#(+inf.0 -inf.0)""", """  '#(-inf.0 +inf.0)""")
jv('J13', "9223372036854775808 answers a flonum (expected the exact integer)",
   """  (vector 9223372036854775807 (inexact 9223372036854775808))""", """  (vector 9223372036854775807 9223372036854775808)""")

# --- the docs' note --------------------------------------------------------------------------
REF = 'docs/reference.md'
mut('D01', "the note's block is one Chez can read (a parenthesis dropped)",
    [(REF, """    (error 'setup "this SQLite has no FTS5"))""", """    (error 'setup "this SQLite has no FTS5")""")],
    [('suite', 'tests/test-docs.sps', 'guix')])
mut('D02', "the note's block is a plain scheme block (marked scheme run)",
    [(REF, """```scheme
(if (sqlite-compile-option? "ENABLE_FTS5")""", """```scheme run
(if (sqlite-compile-option? "ENABLE_FTS5")""")],
    [('suite', 'tests/test-docs.sps', 'guix')])

# --- the values' path, planted in the library (the copy's src) ---------------------------------
SV = 'src/chez-sqlite3/private/statement-values.sls'
mut('V01', "a REAL reads as its flonum (rounded to an integer's)",
    [(SV, "                   (values #f (list 'value (sqlite3-column-double handle column)))",
      "                   (values #f (list 'value (round (sqlite3-column-double handle column))))")],
    [('suite', FTS, 'guix'), ('suite', JSON, 'guix')])
mut('V02', "a string binds as TEXT (bound as a BLOB)",
    [(SV, """             (sqlite3-bind-text64 handle index block (bytevector-length bytes)
                                  sqlite-transient sqlite-utf8)))))""",
      """             (sqlite3-bind-blob64 handle index block (bytevector-length bytes)
                                  sqlite-transient)))))""")],
    [('suite', FTS, 'guix'), ('suite', JSON, 'guix')])
mut('V03', "a bytevector binds as a BLOB (bound as TEXT)",
    [(SV, """             (sqlite3-bind-blob64 handle index block (bytevector-length bytes)
                                  sqlite-transient)))))))""",
      """             (sqlite3-bind-text64 handle index block (bytevector-length bytes)
                                  sqlite-transient sqlite-utf8)))))))""")],
    [('suite', FTS, 'guix'), ('suite', JSON, 'guix')])
mut('V04', "TEXT decodes as UTF-8 (each byte a character, as Latin-1)",
    [(SV, "       (let ((decoded (strict-utf8->string (caddr outcome))))",
      "       (let ((decoded (list->string (map integer->char (bytevector->u8-list (caddr outcome))))))")],
    [('suite', FTS, 'guix'), ('suite', JSON, 'guix')])

def run_lines(name, runs):
    lines = ['#!/bin/sh', '# ' + name, 'wt=$1', 'cd "$wt/build/mut/%s" || exit 2' % name]
    for r in runs:
        if r[0] == 'suite':
            _, s, lib = r
            tag = '%s %s' % (s, lib)
            env = ''
            if LIBS[lib]:
                env = ('CHEZ_SQLITE3_LIBRARY="$wt/%s/lib/libsqlite3.so.0" C_INCLUDE_PATH="$wt/%s/include" '
                       % (LIBS[lib], LIBS[lib]))
            lines.append('echo "@@@ run %s"' % tag)
            lines.append('%stimeout 300 "$CHEZ" --libdirs src:tests:"$wt/build/scheme-libs" --program %s 2>&1; echo "@@@ exit $?"'
                         % (env, s))
        elif r[0] == 'check-current':
            d = r[1]
            lines.append('echo "@@@ run check-sqlite.sh --current build/%s"' % d)
            lines.append('CHEZ_SQLITE3_LIBRARY="$wt/build/%s/lib/libsqlite3.so.0" C_INCLUDE_PATH="$wt/build/%s/include" sh scripts/ci/check-sqlite.sh "$wt/build/%s" --current 2>&1; echo "@@@ exit $?"' % (d, d, d))
        elif r[0] == 'check-floor':
            lines.append('echo "@@@ run check-sqlite.sh build/m3-floor"')
            lines.append('CHEZ_SQLITE3_LIBRARY="$wt/build/m3-floor/lib/libsqlite3.so.0" C_INCLUDE_PATH="$wt/build/m3-floor/include" sh scripts/ci/check-sqlite.sh "$wt/build/m3-floor" 2>&1; echo "@@@ exit $?"')
        elif r[0] == 'build-current':
            lines.append('echo "@@@ run build-sqlite.sh --current, through the replay shims"')
            lines.append('rm -rf "$wt/build/mut/%s.built"' % name)
            lines.append('out=$(SHIM_DL="$wt/build/m4-dl" SHIM_DIGESTS="$wt/build/m4s5-probe/digests" SHIM_X="$wt/build/m4s5-probe/x" '
                         'PATH="$wt/build/m4s5-probe/shim:$PATH" CC=gcc sh scripts/ci/build-sqlite.sh "$wt/build/mut/%s.built" --current 2>&1); rc=$?' % name)
            lines.append('printf "%s\\n" "$out" | grep -v "^  [A-Z]"; echo "@@@ exit $rc"')
    return '\n'.join(lines) + '\n'

def make(name, edits, runs):
    d = os.path.join(WT, 'build', 'mut', name)
    if os.path.exists(d):
        subprocess.run(['rm', '-rf', d], check=True)
    os.makedirs(d)
    tar = subprocess.Popen(['tar', '--exclude=./build', '--exclude=./.git', '-C', WT, '-cf', '-', '.'],
                           stdout=subprocess.PIPE)
    subprocess.run(['tar', '-xf', '-', '-C', d], stdin=tar.stdout, check=True)
    tar.wait()
    for f, old, new in edits:
        p = os.path.join(d, f)
        text = open(p, encoding='utf-8').read()
        n = text.count(old)
        if n != 1:
            raise SystemExit('%s: %s: the edit matches %d times, not once: %r' % (name, f, n, old[:80]))
        open(p, 'w', encoding='utf-8').write(text.replace(old, new))
    open(os.path.join(d, 'RUN.sh'), 'w').write(run_lines(name, runs))

RETIRED = {'F10', 'F11', 'X01', 'X02'}
names = []
for name, guards, edits, runs in M:
    if ONLY and name not in ONLY:
        continue
    if not ONLY and name in RETIRED:
        continue
    make(name, edits, runs)
    names.append(name)
with open(os.path.join(WT, 'build', 'mut', 'GUARDS.txt'), 'w') as g:
    for name, guards, edits, runs in M:
        g.write('%s\t%s\n' % (name, guards))
print(' '.join(names))
