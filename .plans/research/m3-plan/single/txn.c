/* B1: transactions and savepoints, step by step.
 *
 *   txn DIR       DIR: a fresh directory for this run's databases
 *
 * After every statement: sqlite3_get_autocommit, sqlite3_txn_state(db, NULL)
 * and sqlite3_txn_state(db, "main"). A second connection, db2, reads what
 * has been committed. Its reads finish before the next statement, so it
 * never holds a lock while db writes.
 *
 *   T1-T7  BEGIN, BEGIN IMMEDIATE, BEGIN EXCLUSIVE, a read, a write, COMMIT,
 *          ROLLBACK; an unfinished SELECT; a temp table
 *   S1-S12 savepoints: outside a transaction, RELEASE, ROLLBACK TO, names
 *   X1-X3  the errors: BEGIN in a transaction, COMMIT or ROLLBACK with none,
 *          RELEASE or ROLLBACK TO with no savepoint. Each line says whether
 *          the error came from prepare or from step.
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

/* must: setup that has to succeed. */
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

static void print_row(sqlite3_stmt *st) {
  printf("    row:");
  for (int i = 0; i < sqlite3_column_count(st); i++) { printf(" "); print_value(st, i); }
  printf("\n");
}

static void print_failure(const char *what, sqlite3 *db, int rc) {
  printf("    %s: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
         what, rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

/* run: prepare one statement, step it to the end, finalize it. */
static int run(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("prepare", db, rc); return rc; }
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) print_row(st);
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE\n");
  else print_failure("step", db, rc);
  int f = sqlite3_finalize(st);
  printf("    finalize: rc %d\n", f);
  return rc;
}

static const char *txn_name(int s) {
  switch (s) {
  case SQLITE_TXN_NONE: return "NONE"; case SQLITE_TXN_READ: return "READ";
  case SQLITE_TXN_WRITE: return "WRITE"; default: return "-1";
  }
}

static void state(sqlite3 *db) {
  int a = sqlite3_get_autocommit(db);
  int s0 = sqlite3_txn_state(db, NULL);
  int s1 = sqlite3_txn_state(db, "main");
  printf("    state: autocommit %d, txn_state(NULL) %s, txn_state(main) %s\n",
         a, txn_name(s0), txn_name(s1));
}

static void runs(sqlite3 *db, const char *sql) { run(db, sql); state(db); }

/* seen: the rows of t as connection db sees them, in order. */
static void seen(sqlite3 *db, const char *who) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db,
    "SELECT coalesce(group_concat(x, ','), '(none)') FROM (SELECT x FROM t ORDER BY x)",
    -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("seen: prepare", db, rc); return; }
  rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) printf("    rows %s sees: %s\n", who, sqlite3_column_text(st, 0));
  else print_failure("seen: step", db, rc);
  sqlite3_finalize(st);
}

static void step_once(sqlite3_stmt *st, sqlite3 *db, const char *label) {
  int rc = sqlite3_step(st);
  printf("  %s: step rc %d %s", label, rc, code_name(rc));
  if (rc == SQLITE_ROW) { printf(", value "); print_value(st, 0); }
  else if (rc != SQLITE_DONE)
    printf(", extended_errcode %d, errmsg \"%s\"", sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  printf("\n");
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: txn DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  sqlite3 *db = open_at("txn.db");
  sqlite3 *db2 = open_at("txn.db");
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3);");
  sqlite3_stmt *st = NULL;

  printf("\nT1. BEGIN (deferred), a read, a write, COMMIT; BEGIN, a write, ROLLBACK\n");
  printf("  (idle, after setup)\n"); state(db);
  printf("  txn_state(db, \"temp\") %s, txn_state(db, \"nosuch\") %s\n",
         txn_name(sqlite3_txn_state(db, "temp")), txn_name(sqlite3_txn_state(db, "nosuch")));
  runs(db, "BEGIN");
  runs(db, "SELECT count(*) FROM t");
  runs(db, "INSERT INTO t VALUES (4)");
  seen(db2, "db2");
  runs(db, "COMMIT");
  seen(db2, "db2");
  runs(db, "BEGIN");
  runs(db, "INSERT INTO t VALUES (5)");
  runs(db, "ROLLBACK");
  seen(db, "db");

  printf("\nT2. BEGIN IMMEDIATE, a read, a write, COMMIT\n");
  runs(db, "BEGIN IMMEDIATE");
  runs(db, "SELECT count(*) FROM t");
  runs(db, "INSERT INTO t VALUES (5)");
  runs(db, "COMMIT");

  printf("\nT3. BEGIN EXCLUSIVE, a read, ROLLBACK\n");
  runs(db, "BEGIN EXCLUSIVE");
  runs(db, "SELECT count(*) FROM t");
  runs(db, "ROLLBACK");

  printf("\nT4. Empty transactions, and the other spellings\n");
  runs(db, "BEGIN");
  runs(db, "COMMIT");
  runs(db, "BEGIN TRANSACTION");
  runs(db, "END TRANSACTION");
  runs(db, "BEGIN DEFERRED TRANSACTION");
  runs(db, "END");
  runs(db, "BEGIN IMMEDIATE");
  runs(db, "ROLLBACK TRANSACTION");

  printf("\nT5. A SELECT stepped once and not finished, in autocommit\n");
  sqlite3_prepare_v2(db, "SELECT x FROM t ORDER BY x", -1, &st, NULL);
  printf("  prepared, not stepped\n"); state(db);
  step_once(st, db, "step 1"); state(db);
  printf("  reset: rc %d\n", sqlite3_reset(st)); state(db);
  step_once(st, db, "step 1 again"); state(db);
  for (int i = 2; i <= 6; i++) { char l[32]; snprintf(l, sizeof l, "step %d", i); step_once(st, db, l); }
  printf("  (done, not reset)\n"); state(db);
  printf("  reset: rc %d\n", sqlite3_reset(st));
  printf("  finalize: rc %d\n", sqlite3_finalize(st));

  printf("\nT6. In a transaction, a SELECT stepped once, then finalized\n");
  runs(db, "BEGIN");
  sqlite3_prepare_v2(db, "SELECT x FROM t ORDER BY x", -1, &st, NULL);
  step_once(st, db, "step 1"); state(db);
  printf("  finalize: rc %d\n", sqlite3_finalize(st)); state(db);
  runs(db, "COMMIT");

  printf("\nT7. A temp table: txn_state(NULL) against txn_state(main) and (temp)\n");
  runs(db, "BEGIN");
  runs(db, "CREATE TEMP TABLE tt(x)");
  printf("    txn_state(temp) %s\n", txn_name(sqlite3_txn_state(db, "temp")));
  runs(db, "INSERT INTO tt VALUES (1)");
  printf("    txn_state(temp) %s\n", txn_name(sqlite3_txn_state(db, "temp")));
  runs(db, "ROLLBACK");
  printf("    txn_state(temp) %s\n", txn_name(sqlite3_txn_state(db, "temp")));

  printf("\nS1. SAVEPOINT outside a transaction, a write, RELEASE of it\n");
  must(db, "DELETE FROM t; INSERT INTO t VALUES (1), (2), (3);");
  runs(db, "SAVEPOINT a");
  runs(db, "SELECT count(*) FROM t");
  runs(db, "INSERT INTO t VALUES (10)");
  seen(db2, "db2");
  runs(db, "RELEASE a");
  seen(db2, "db2");

  printf("\nS2. Nested: RELEASE of an inner savepoint, ROLLBACK TO the outer, and after\n");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (20)");
  runs(db, "SAVEPOINT b");
  runs(db, "INSERT INTO t VALUES (21)");
  runs(db, "RELEASE b");
  seen(db, "db");
  runs(db, "ROLLBACK TO a");
  seen(db, "db");
  printf("  (is a still open? a write, then ROLLBACK TO a again)\n");
  runs(db, "INSERT INTO t VALUES (22)");
  runs(db, "ROLLBACK TO a");
  seen(db, "db");
  runs(db, "INSERT INTO t VALUES (23)");
  runs(db, "RELEASE a");
  seen(db2, "db2");

  printf("\nS3. ROLLBACK TO an inner savepoint: is it still open, and the outer?\n");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (30)");
  runs(db, "SAVEPOINT b");
  runs(db, "INSERT INTO t VALUES (31)");
  runs(db, "ROLLBACK TO b");
  seen(db, "db");
  runs(db, "INSERT INTO t VALUES (32)");
  runs(db, "RELEASE b");
  seen(db, "db");
  runs(db, "RELEASE a");
  seen(db2, "db2");

  printf("\nS4. ROLLBACK TO the outermost savepoint, which began the transaction\n");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (40)");
  runs(db, "ROLLBACK TO a");
  seen(db2, "db2");
  runs(db, "RELEASE a");
  seen(db2, "db2");

  printf("\nS5. SAVEPOINT inside BEGIN: RELEASE leaves the transaction open\n");
  runs(db, "BEGIN");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (50)");
  runs(db, "RELEASE a");
  seen(db2, "db2");
  runs(db, "COMMIT");
  seen(db2, "db2");

  printf("\nS6. COMMIT and ROLLBACK with savepoints open, the first begun by SAVEPOINT\n");
  runs(db, "SAVEPOINT a");
  runs(db, "SAVEPOINT b");
  runs(db, "INSERT INTO t VALUES (60)");
  runs(db, "COMMIT");
  seen(db2, "db2");
  runs(db, "RELEASE a");
  runs(db, "SAVEPOINT a");
  runs(db, "SAVEPOINT b");
  runs(db, "INSERT INTO t VALUES (61)");
  runs(db, "ROLLBACK");
  seen(db2, "db2");
  runs(db, "ROLLBACK TO a");

  printf("\nS7. BEGIN after a SAVEPOINT that began the transaction\n");
  runs(db, "SAVEPOINT a");
  runs(db, "BEGIN");
  runs(db, "ROLLBACK");

  printf("\nS8. Savepoint names: case, quoting\n");
  runs(db, "SAVEPOINT Foo");
  runs(db, "RELEASE foo");
  runs(db, "SAVEPOINT foo");
  runs(db, "RELEASE \"FOO\"");
  runs(db, "SAVEPOINT \"a b\"");
  runs(db, "RELEASE \"a b\"");
  runs(db, "SAVEPOINT 'q'");
  runs(db, "RELEASE q");
  runs(db, "SAVEPOINT [br]");
  runs(db, "RELEASE br");
  runs(db, "SAVEPOINT `bt`");
  runs(db, "RELEASE \"bt\"");
  runs(db, "SAVEPOINT \"\xc3\x84\"");          /* U+00C4 */
  runs(db, "RELEASE \"\xc3\xa4\"");            /* U+00E4, its lower case */
  runs(db, "RELEASE \"\xc3\x84\"");
  runs(db, "SAVEPOINT \"\"");
  runs(db, "RELEASE \"\"");
  runs(db, "SAVEPOINT begin");
  runs(db, "SAVEPOINT \"x\"\"y\"");
  runs(db, "RELEASE 'x\"y'");
  runs(db, "RELEASE \"begin\"");

  printf("\nS9. A name used twice: which one ROLLBACK TO and RELEASE reach\n");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (70)");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (71)");
  runs(db, "ROLLBACK TO a");
  seen(db, "db");
  runs(db, "INSERT INTO t VALUES (72)");
  runs(db, "RELEASE a");
  seen(db2, "db2");
  runs(db, "ROLLBACK TO a");
  seen(db, "db");
  runs(db, "RELEASE a");
  seen(db2, "db2");

  printf("\nS10. RELEASE of an outer savepoint releases the inner ones\n");
  runs(db, "SAVEPOINT a");
  runs(db, "SAVEPOINT b");
  runs(db, "SAVEPOINT c");
  runs(db, "RELEASE b");
  runs(db, "RELEASE c");
  runs(db, "ROLLBACK TO c");
  runs(db, "RELEASE a");

  printf("\nS11. The long forms\n");
  runs(db, "SAVEPOINT a");
  runs(db, "ROLLBACK TRANSACTION TO SAVEPOINT a");
  runs(db, "RELEASE SAVEPOINT a");

  printf("\nS12. An unknown savepoint, outside and inside a transaction\n");
  runs(db, "RELEASE nosuch");
  runs(db, "ROLLBACK TO nosuch");
  runs(db, "SAVEPOINT a");
  runs(db, "INSERT INTO t VALUES (80)");
  runs(db, "RELEASE nosuch");
  runs(db, "ROLLBACK TO nosuch");
  seen(db, "db");
  runs(db, "ROLLBACK");

  printf("\nX1. BEGIN inside a transaction begun by BEGIN, and by SAVEPOINT\n");
  runs(db, "BEGIN");
  runs(db, "BEGIN");
  runs(db, "BEGIN IMMEDIATE");
  runs(db, "ROLLBACK");
  runs(db, "SAVEPOINT a");
  runs(db, "BEGIN EXCLUSIVE");
  runs(db, "ROLLBACK");
  printf("\nX2. COMMIT, END and ROLLBACK with no transaction open\n");
  runs(db, "COMMIT");
  runs(db, "END");
  runs(db, "ROLLBACK");
  printf("\nX3. RELEASE and ROLLBACK TO with no savepoint at all\n");
  runs(db, "RELEASE a");
  runs(db, "ROLLBACK TO a");

  close_db(db2);
  close_db(db);
  return 0;
}
