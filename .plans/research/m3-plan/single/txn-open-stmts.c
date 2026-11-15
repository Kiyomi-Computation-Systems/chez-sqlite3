/* B1: statements still open when their transaction ends, and DDL rolled
 * back.
 *
 *   txn-open-stmts DIR       DIR: a fresh directory for this run's databases
 *
 *   O1  a SELECT that has answered a row, then COMMIT; its next steps
 *   O2  the same, then ROLLBACK, on the table the transaction wrote
 *   O3  the same, then ROLLBACK, on a table the transaction didn't write
 *   O4  the same, then ROLLBACK, when the transaction changed the schema;
 *       with a sorter (ORDER BY, no index) and with a rowid scan
 *   O5  in autocommit: a SELECT that has answered a row, then an INSERT
 *   O6  a write stepped to DONE and not reset, then COMMIT
 *   O7  INSERT ... RETURNING stepped once, then COMMIT
 *   O8  a reset of a SELECT after ROLLBACK ended its read
 *   D1  DDL inside a transaction, rolled back
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n",
            SQLITE_VERSION_NUMBER, SQLITE_SOURCE_ID,
            sqlite3_libversion_number(), sqlite3_sourceid());
    exit(2);
  }
  printf("libversion: %s\n", sqlite3_libversion());
  printf("sourceid: %s\n", sqlite3_sourceid());
}

static sqlite3 *open_at(const char *name) {
  char path[4096];
  sqlite3 *db = NULL;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open %s: rc %d\n", name, rc); exit(2); }
  return db;
}

static void close_db(sqlite3 *db) {
  int rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

static void must(sqlite3 *db, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static const char *code_name(int rc) {
  switch (rc & 0xff) {
  case 0: return "OK"; case 1: return "ERROR"; case 4: return "ABORT";
  case 5: return "BUSY"; case 6: return "LOCKED"; case 7: return "NOMEM";
  case 8: return "READONLY"; case 9: return "INTERRUPT"; case 10: return "IOERR";
  case 13: return "FULL"; case 17: return "SCHEMA"; case 18: return "TOOBIG";
  case 19: return "CONSTRAINT"; case 20: return "MISMATCH"; case 21: return "MISUSE";
  case 25: return "RANGE"; case 100: return "ROW"; case 101: return "DONE";
  default: return "?";
  }
}

static void print_value(sqlite3_stmt *st, int i) {
  switch (sqlite3_column_type(st, i)) {
  case SQLITE_INTEGER: printf("%lld", (long long)sqlite3_column_int64(st, i)); break;
  case SQLITE_FLOAT: printf("%.17g", sqlite3_column_double(st, i)); break;
  case SQLITE_TEXT: printf("'%s'", (const char *)sqlite3_column_text(st, i)); break;
  case SQLITE_BLOB: printf("blob(%d)", sqlite3_column_bytes(st, i)); break;
  default: printf("NULL"); break;
  }
}

static void print_failure(const char *what, sqlite3 *db, int rc) {
  printf("    %s: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
         what, rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

static int run(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("prepare", db, rc); return rc; }
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
    printf("    row:");
    for (int i = 0; i < sqlite3_column_count(st); i++) { printf(" "); print_value(st, i); }
    printf("\n");
  }
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE\n");
  else print_failure("step", db, rc);
  printf("    finalize: rc %d\n", sqlite3_finalize(st));
  return rc;
}

static const char *txn_name(int s) {
  switch (s) {
  case SQLITE_TXN_NONE: return "NONE"; case SQLITE_TXN_READ: return "READ";
  case SQLITE_TXN_WRITE: return "WRITE"; default: return "-1";
  }
}

static void state(sqlite3 *db) {
  printf("    state: autocommit %d, txn_state(main) %s\n",
         sqlite3_get_autocommit(db), txn_name(sqlite3_txn_state(db, "main")));
}

static void seen(sqlite3 *db, const char *who, const char *table) {
  char sql[256];
  sqlite3_stmt *st = NULL;
  snprintf(sql, sizeof sql,
           "SELECT coalesce(group_concat(x, ','), '(none)') FROM (SELECT x FROM %s ORDER BY x)", table);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("seen: prepare", db, rc); return; }
  rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) printf("    rows of %s %s sees: %s\n", table, who, sqlite3_column_text(st, 0));
  else print_failure("seen: step", db, rc);
  sqlite3_finalize(st);
}

static sqlite3_stmt *prep(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "prepare %s: %d\n", sql, rc); exit(2); }
  printf("  held: %s\n", sql);
  return st;
}

static int step_print(sqlite3_stmt *st, sqlite3 *db, const char *label) {
  int rc = sqlite3_step(st);
  printf("  %s: step rc %d %s", label, rc, code_name(rc));
  if (rc == SQLITE_ROW) {
    printf(", row");
    for (int i = 0; i < sqlite3_column_count(st); i++) { printf(" "); print_value(st, i); }
  } else if (rc != SQLITE_DONE) {
    printf(", extended_errcode %d, errmsg \"%s\"", sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  }
  printf(", stmt_busy %d\n", sqlite3_stmt_busy(st));
  return rc;
}

/* step_rest: step until DONE or an error, at most 10 more times. */
static void step_rest(sqlite3_stmt *st, sqlite3 *db) {
  for (int i = 0; i < 10; i++) {
    char l[32];
    snprintf(l, sizeof l, "next step %d", i + 1);
    int rc = step_print(st, db, l);
    if (rc != SQLITE_ROW) return;
  }
}

static sqlite3 *fresh(const char *name) {
  sqlite3 *db = open_at(name);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3);"
           "CREATE TABLE u(x); INSERT INTO u VALUES (100), (200), (300);");
  return db;
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: txn-open-stmts DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  sqlite3 *db, *db2;
  sqlite3_stmt *st, *w;

  printf("\nO1. A SELECT that has answered a row, then COMMIT\n");
  db = fresh("o1.db"); db2 = open_at("o1.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4)");
  st = prep(db, "SELECT x FROM t ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "COMMIT");
  state(db);
  seen(db2, "db2", "t");
  step_rest(st, db);
  state(db);
  printf("  reset: rc %d\n", sqlite3_reset(st));
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db2); close_db(db);

  printf("\nO2. A SELECT on the table the transaction wrote, one row answered, then ROLLBACK\n");
  db = fresh("o2.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4), (5)");
  st = prep(db, "SELECT x FROM t ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  state(db);
  printf("  reset: rc %d\n", sqlite3_reset(st));
  step_print(st, db, "step after reset");
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  seen(db, "db", "t");
  close_db(db);

  printf("\nO2b. The same, a rowid scan with no ORDER BY\n");
  db = fresh("o2b.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4), (5)");
  st = prep(db, "SELECT x FROM t");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO3. A SELECT on a table the transaction didn't write, one row answered, then ROLLBACK\n");
  db = fresh("o3.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4)");
  st = prep(db, "SELECT x FROM u ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO3b. A SELECT, one row answered, in a transaction that wrote nothing, then ROLLBACK\n");
  db = fresh("o3b.db");
  run(db, "BEGIN");
  st = prep(db, "SELECT x FROM u ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO4. A SELECT, one row answered, in a transaction that created a table, then ROLLBACK\n");
  db = fresh("o4.db");
  run(db, "BEGIN");
  run(db, "CREATE TABLE v(x)");
  st = prep(db, "SELECT x FROM u ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO4b. The same, a rowid scan with no ORDER BY\n");
  db = fresh("o4b.db");
  run(db, "BEGIN");
  run(db, "CREATE TABLE v(x)");
  st = prep(db, "SELECT x FROM u");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  reset: rc %d\n", sqlite3_reset(st));
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO4c. A rowid scan of the table the transaction wrote and altered, then ROLLBACK\n");
  db = fresh("o4c.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4), (5)");
  run(db, "ALTER TABLE t ADD COLUMN y");
  st = prep(db, "SELECT x FROM t");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(st, db);
  printf("  reset: rc %d\n", sqlite3_reset(st));
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nO5. In autocommit: a SELECT that has answered a row, then an INSERT\n");
  db = fresh("o5.db"); db2 = open_at("o5.db");
  st = prep(db, "SELECT x FROM t ORDER BY x");
  step_print(st, db, "step 1");
  state(db);
  run(db, "INSERT INTO t VALUES (4)");
  state(db);
  seen(db2, "db2", "t");
  step_rest(st, db);
  state(db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db2); close_db(db);

  printf("\nO6. A write stepped to DONE and not reset, then COMMIT\n");
  db = fresh("o6.db"); db2 = open_at("o6.db");
  run(db, "BEGIN");
  w = prep(db, "INSERT INTO t VALUES (5)");
  step_print(w, db, "step 1");
  run(db, "COMMIT");
  state(db);
  seen(db2, "db2", "t");
  printf("  reset: rc %d\n", sqlite3_reset(w));
  printf("  finalize: rc %d\n", sqlite3_finalize(w));
  close_db(db2); close_db(db);

  printf("\nO7. INSERT ... RETURNING stepped once, then COMMIT\n");
  db = fresh("o7.db"); db2 = open_at("o7.db");
  run(db, "BEGIN");
  w = prep(db, "INSERT INTO t VALUES (6), (7) RETURNING x");
  step_print(w, db, "step 1");
  run(db, "COMMIT");
  state(db);
  seen(db, "db", "t");
  seen(db2, "db2", "t");
  step_rest(w, db);
  state(db);
  run(db, "COMMIT");
  state(db);
  seen(db2, "db2", "t");
  printf("  reset: rc %d\n", sqlite3_reset(w));
  printf("  finalize: rc %d\n", sqlite3_finalize(w));
  close_db(db2); close_db(db);

  printf("\nO7b. INSERT ... RETURNING stepped once, then ROLLBACK\n");
  db = fresh("o7b.db");
  run(db, "BEGIN");
  w = prep(db, "INSERT INTO t VALUES (6), (7) RETURNING x");
  step_print(w, db, "step 1");
  run(db, "ROLLBACK");
  state(db);
  step_rest(w, db);
  printf("  reset: rc %d\n", sqlite3_reset(w));
  printf("  finalize: rc %d\n", sqlite3_finalize(w));
  seen(db, "db", "t");
  close_db(db);

  printf("\nO7c. UPDATE ... RETURNING stepped once, then COMMIT\n");
  db = fresh("o7c.db");
  run(db, "BEGIN");
  w = prep(db, "UPDATE t SET x = x + 10 RETURNING x");
  step_print(w, db, "step 1");
  run(db, "COMMIT");
  state(db);
  printf("  reset: rc %d\n", sqlite3_reset(w));
  state(db);
  run(db, "COMMIT");
  printf("  finalize: rc %d\n", sqlite3_finalize(w));
  seen(db, "db", "t");
  close_db(db);

  printf("\nO7d. INSERT ... RETURNING stepped once, then reset, inside BEGIN: does the reset commit?\n");
  db = fresh("o7d.db"); db2 = open_at("o7d.db");
  run(db, "BEGIN");
  w = prep(db, "INSERT INTO t VALUES (6), (7) RETURNING x");
  step_print(w, db, "step 1");
  printf("  reset: rc %d\n", sqlite3_reset(w));
  state(db);
  seen(db, "db", "t");
  seen(db2, "db2", "t");
  printf("  finalize: rc %d\n", sqlite3_finalize(w));
  state(db);
  run(db, "ROLLBACK");
  seen(db, "db", "t");
  seen(db2, "db2", "t");
  close_db(db2); close_db(db);

  printf("\nO8. A SELECT answered a row, then ROLLBACK; reset it before its next step\n");
  db = fresh("o8.db");
  run(db, "BEGIN");
  run(db, "INSERT INTO t VALUES (4)");
  st = prep(db, "SELECT x FROM t ORDER BY x");
  step_print(st, db, "step 1");
  run(db, "ROLLBACK");
  {
    int r = sqlite3_reset(st);
    printf("  reset: rc %d, then extended_errcode %d\n", r, sqlite3_extended_errcode(db));
  }
  step_print(st, db, "step after reset");
  printf("  finalize: rc %d\n", sqlite3_finalize(st));
  close_db(db);

  printf("\nD1. DDL inside a transaction, rolled back\n");
  db = fresh("d1.db");
  run(db, "BEGIN");
  run(db, "CREATE TABLE n(x)");
  run(db, "INSERT INTO n VALUES (1)");
  run(db, "ALTER TABLE t ADD COLUMN y DEFAULT 7");
  run(db, "CREATE INDEX ti ON t(x)");
  run(db, "DROP TABLE u");
  run(db, "CREATE VIEW vw AS SELECT x FROM t");
  run(db, "SELECT type, name FROM sqlite_schema ORDER BY name");
  run(db, "ROLLBACK");
  run(db, "SELECT type, name FROM sqlite_schema ORDER BY name");
  run(db, "SELECT x FROM n");
  run(db, "SELECT y FROM t");
  run(db, "SELECT count(*) FROM u");
  run(db, "SELECT name FROM pragma_table_info('t')");
  close_db(db);

  printf("\nD2. DDL inside a savepoint, rolled back to it\n");
  db = fresh("d2.db");
  run(db, "SAVEPOINT a");
  run(db, "CREATE TABLE n(x)");
  run(db, "SAVEPOINT b");
  run(db, "ALTER TABLE t ADD COLUMN y");
  run(db, "ROLLBACK TO b");
  run(db, "SELECT name FROM pragma_table_info('t')");
  run(db, "RELEASE a");
  run(db, "SELECT type, name FROM sqlite_schema ORDER BY name");
  close_db(db);
  return 0;
}
