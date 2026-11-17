# Writes item 1's plant specs for tests/test-transaction-interrupt.sps.
T = "src/chez-sqlite3/private/transaction.sls"
S = "tests/test-transaction-interrupt.sps"
def w(name, edits):
    with open(f"specs/{name}.py", "w") as f:
        f.write("EDITS = " + repr(edits) + "\n")
w("ti-stub", [(T, "      (run-level who db (cadr plan) (caddr plan) body)))", "      (body)))")])
w("ti-no-rollback", [(T, "              (when (and begun (not ended))\n                (set! rollback-failure", "              (when #f\n                (set! rollback-failure")])
w("ti-depth-plus-one", [(T, "(begin-plan (sqlite3-get-autocommit handle) (database-depth db) mode)", "(begin-plan (sqlite3-get-autocommit handle) (+ (database-depth db) 1) mode)")])
w("ti-no-return", [(T, "             (guard (c (#t #f)) (returned who st))\n             stepped)))))", "             stepped)))))")])
w("ti-pL1", [(T, "(let ((p (exit-plan 'return begun ended (sqlite3-get-autocommit handle) level)))", "(let ((p (exit-plan 'return begun ended 0 level)))")])
w("ti-watchdog-silent", [
  (S, "(define bound-ms 120000)", "(define bound-ms 2000)"),
  (S, "             (with-mutex m\n               (set! started #t)\n               (set! ended #t)\n               (condition-broadcast c)))))",
      "             (with-mutex m\n               (set! started #t)\n               (condition-broadcast c)))))")])
w("ti-no-interrupt", [(S, "                                (sqlite3-interrupt handle)\n                                'void)))", "                                #f\n                                'void)))")])
w("ti-cold", [(S, "     (let* ((cached (execute! db sql 1))\n            (recorded #f)", "     (let* ((recorded #f)")])
w("ti-no-hold", [(S, "                  (mutex-enter memory-mutex)\n                  (set! holding #t)\n", "")])
w("ti-no-randomblob", [
  (S, "select i from k where length(randomblob(16)) = 16\")", "select i from k\")"),
  (S, "select count(*) from k, src where length(randomblob(16)) = 16\")", "select count(*) from k, src\")")])
print("ok")
