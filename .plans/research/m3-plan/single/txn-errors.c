/* B1: which errors end the transaction they happen in, and which leave it
 * open.
 *
 *   txn-errors DIR       DIR: a fresh directory for this run's databases
 *
 * Each case has a database file of its own. Its table t holds 1 and 2,
 * committed. Then BEGIN (or SAVEPOINT), INSERT 10, the failing statement,
 * and the state: sqlite3_get_autocommit, sqlite3_txn_state(db, "main"), and
 * the rows this connection sees. Then COMMIT if the transaction is still
 * open, and the rows a second connection sees once it has.
 *
 * NOMEM is caused with sqlite3_hard_heap_limit64(sqlite3_memory_used() +
 * 1000), set just before the step and set back to 0 straight after, with a
 * value of 100,000 bytes, larger than lookaside serves (M2 slice 4's way).
 * The limit stays in force across every step, the statement's own rollback
 * included; txn-special.c measures what that changes, against exactly one
 * failing allocation.
 * SQLITE_FULL comes from PRAGMA max_page_count on a file database.
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

static void print_failure(const char *what, sqlite3 *db, int rc) {
  printf("    %s: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
         what, rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

/* run: prepare one statement, step it to the end, finalize it. When
 * heap_limit is set, the hard heap limit is lowered around the steps only. */
static int run_limited(sqlite3 *db, const char *sql, int heap_limit) {
  sqlite3_stmt *st = NULL;
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("prepare", db, rc); return rc; }
  if (heap_limit) {
    sqlite3_int64 used = sqlite3_memory_used();
    printf("    (memory_used before the limit is above 0: %d)\n", used > 0);
    sqlite3_hard_heap_limit64(used + 1000);
  }
  int rows = 0;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) rows++;
  if (heap_limit) {
    sqlite3_hard_heap_limit64(0);
    printf("    (hard heap limit was memory_used + 1000 for the steps, now %lld)\n",
           (long long)sqlite3_hard_heap_limit64(-1));
  }
  if (rows) printf("    rows: %d\n", rows);
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE\n");
  else print_failure("step", db, rc);
  int f = sqlite3_finalize(st);
  printf("    finalize: rc %d\n", f);
  return rc;
}

static int run(sqlite3 *db, const char *sql) { return run_limited(db, sql, 0); }

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

static void seen_in(sqlite3 *db, const char *who, const char *table) {
  char sql[256];
  sqlite3_stmt *st = NULL;
  snprintf(sql, sizeof sql,
           "SELECT coalesce(group_concat(x, ','), '(none)') FROM (SELECT x FROM %s ORDER BY x)",
           table);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("seen: prepare", db, rc); return; }
  rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) printf("    rows of %s %s sees: %s\n", table, who, sqlite3_column_text(st, 0));
  else print_failure("seen: step", db, rc);
  sqlite3_finalize(st);
}

/* count_in: how many rows the table holds, as db sees it. */
static void count_in(sqlite3 *db, const char *who, const char *table) {
  char sql[256];
  sqlite3_stmt *st = NULL;
  snprintf(sql, sizeof sql, "SELECT count(*) FROM %s", table);
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) { print_failure("count", db, 1); return; }
  if (sqlite3_step(st) == SQLITE_ROW)
    printf("    rows in %s %s sees: %lld\n", table, who, (long long)sqlite3_column_int64(st, 0));
  sqlite3_finalize(st);
}

static sqlite3 *db, *db2;
static int case_number = 0;

/* begin_case: a fresh database with t holding 1 and 2, then OPENER and
 * INSERT 10. EXTRA is more setup, run before the transaction. */
static void begin_case(const char *title, const char *extra, const char *opener) {
  char name[64];
  case_number++;
  snprintf(name, sizeof name, "e%02d.db", case_number);
  printf("\nE%d. %s\n", case_number, title);
  db = open_at(name);
  db2 = open_at(name);
  must(db, "CREATE TABLE t(x INTEGER UNIQUE NOT NULL CHECK (x < 1000)); INSERT INTO t VALUES (1), (2);");
  if (extra) must(db, extra);
  run(db, opener);
  run(db, "INSERT INTO t VALUES (10)");
  state(db);
}

/* end_case: the state after the failure; COMMIT if still open; what db2 sees. */
static void end_case(const char *table) {
  state(db);
  seen_in(db, "db", "t");
  if (strcmp(table, "t") != 0) count_in(db, "db", table);
  if (!sqlite3_get_autocommit(db)) { run(db, "COMMIT"); state(db); }
  seen_in(db2, "db2, after", "t");
  if (strcmp(table, "t") != 0) count_in(db2, "db2, after", table);
  close_db(db2);
  close_db(db);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: txn-errors DIR\n"); return 2; }
  dir = argv[1];
  version_lines();

  begin_case("A UNIQUE failure under the default conflict resolution (ABORT), one row",
             NULL, "BEGIN");
  run(db, "INSERT INTO t VALUES (1)");
  end_case("t");

  begin_case("A UNIQUE failure in the third row of a four-row INSERT, default resolution",
             NULL, "BEGIN");
  run(db, "INSERT INTO t VALUES (20), (21), (1), (22)");
  end_case("t");

  begin_case("NOT NULL and CHECK failures, default resolution", NULL, "BEGIN");
  run(db, "INSERT INTO t VALUES (NULL)");
  state(db);
  run(db, "INSERT INTO t VALUES (5000)");
  end_case("t");

  begin_case("INSERT OR ROLLBACK, failing", NULL, "BEGIN");
  run(db, "INSERT OR ROLLBACK INTO t VALUES (1)");
  end_case("t");

  begin_case("INSERT OR ROLLBACK, failing, in a transaction begun by SAVEPOINT", NULL, "SAVEPOINT a");
  run(db, "SAVEPOINT b");
  run(db, "INSERT OR ROLLBACK INTO t VALUES (1)");
  state(db);
  run(db, "RELEASE b");
  run(db, "ROLLBACK TO a");
  run(db, "RELEASE a");
  run(db, "ROLLBACK");
  end_case("t");

  begin_case("INSERT OR FAIL, failing at its third row of four", NULL, "BEGIN");
  run(db, "INSERT OR FAIL INTO t VALUES (30), (31), (1), (32)");
  end_case("t");

  begin_case("UPDATE OR ROLLBACK, failing", NULL, "BEGIN");
  run(db, "UPDATE OR ROLLBACK t SET x = 1 WHERE x = 2");
  end_case("t");

  begin_case("A trigger's RAISE(ROLLBACK, ...)",
             "CREATE TRIGGER tr BEFORE INSERT ON t WHEN new.x = 99 "
             "BEGIN SELECT RAISE(ROLLBACK, 'trigger said rollback'); END;",
             "BEGIN");
  run(db, "INSERT INTO t VALUES (99)");
  end_case("t");

  begin_case("A trigger's RAISE(ABORT, ...), at the third row of four",
             "CREATE TRIGGER tr BEFORE INSERT ON t WHEN new.x = 99 "
             "BEGIN SELECT RAISE(ABORT, 'trigger said abort'); END;",
             "BEGIN");
  run(db, "INSERT INTO t VALUES (40), (41), (99), (42)");
  end_case("t");

  begin_case("A trigger's RAISE(FAIL, ...), at the third row of four",
             "CREATE TRIGGER tr BEFORE INSERT ON t WHEN new.x = 99 "
             "BEGIN SELECT RAISE(FAIL, 'trigger said fail'); END;",
             "BEGIN");
  run(db, "INSERT INTO t VALUES (50), (51), (99), (52)");
  end_case("t");

  begin_case("A trigger's RAISE(IGNORE), at the third row of four",
             "CREATE TRIGGER tr BEFORE INSERT ON t WHEN new.x = 99 "
             "BEGIN SELECT RAISE(IGNORE); END;",
             "BEGIN");
  run(db, "INSERT INTO t VALUES (60), (61), (99), (62)");
  end_case("t");

  begin_case("An immediate foreign key failure",
             "PRAGMA foreign_keys = ON; CREATE TABLE p(id INTEGER PRIMARY KEY); "
             "CREATE TABLE c(pid REFERENCES p(id));",
             "BEGIN");
  run(db, "INSERT INTO c VALUES (7)");
  end_case("t");

  begin_case("A deferred foreign key failure: COMMIT fails",
             "PRAGMA foreign_keys = ON; CREATE TABLE p(id INTEGER PRIMARY KEY); "
             "CREATE TABLE c(pid REFERENCES p(id) DEFERRABLE INITIALLY DEFERRED);",
             "BEGIN");
  run(db, "INSERT INTO c VALUES (7)");
  state(db);
  run(db, "COMMIT");
  state(db);
  seen_in(db2, "db2, after the failed COMMIT", "t");
  run(db, "INSERT INTO p VALUES (7)");
  end_case("t");

  begin_case("A runtime error that isn't a constraint (integer overflow), third row of four",
             NULL, "BEGIN");
  run(db, "INSERT INTO t SELECT CASE WHEN v = 3 THEN abs(-9223372036854775807 - 1) ELSE 100 + v END "
          "FROM (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4)");
  end_case("t");

  begin_case("SQLITE_FULL, one row, into a table with no constraints",
             "CREATE TABLE b(x);", "BEGIN");
  run(db, "PRAGMA max_page_count = 1");
  run(db, "INSERT INTO b VALUES (zeroblob(100000))");
  end_case("b");

  begin_case("SQLITE_FULL, many rows, into a table with no constraints",
             "CREATE TABLE b(x);", "BEGIN");
  run(db, "PRAGMA max_page_count = 1");
  run(db, "INSERT INTO b SELECT zeroblob(3000) FROM "
          "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100) SELECT i FROM n)");
  end_case("b");

  begin_case("SQLITE_FULL, one row, into a table with a NOT NULL column",
             "CREATE TABLE b(x NOT NULL);", "BEGIN");
  run(db, "PRAGMA max_page_count = 1");
  run(db, "INSERT INTO b VALUES (zeroblob(100000))");
  end_case("b");

  begin_case("SQLITE_FULL, many rows, into a table with a NOT NULL column",
             "CREATE TABLE b(x NOT NULL);", "BEGIN");
  run(db, "PRAGMA max_page_count = 1");
  run(db, "INSERT INTO b SELECT zeroblob(3000) FROM "
          "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100) SELECT i FROM n)");
  end_case("b");

  begin_case("SQLITE_FULL, many rows, into t (UNIQUE, NOT NULL, CHECK)", NULL, "BEGIN");
  run(db, "PRAGMA max_page_count = 1");
  run(db, "INSERT INTO t SELECT 100 + i FROM "
          "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 800) SELECT i FROM n)");
  end_case("t");

  begin_case("SQLITE_NOMEM through the heap limit, one row, into a table with no constraints",
             "CREATE TABLE b(x);", "BEGIN");
  run_limited(db, "INSERT INTO b VALUES (randomblob(100000))", 1);
  end_case("b");

  begin_case("SQLITE_NOMEM through the heap limit, many rows, into a table with a NOT NULL column",
             "CREATE TABLE b(x NOT NULL);", "BEGIN");
  run_limited(db, "INSERT INTO b SELECT randomblob(100000) FROM "
                  "(SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3)", 1);
  end_case("b");

  begin_case("SQLITE_NOMEM through the heap limit, many rows, into t (UNIQUE, NOT NULL, CHECK)",
             NULL, "BEGIN");
  run_limited(db, "INSERT INTO t SELECT 100 + v + 0 * length(randomblob(100000)) FROM "
                  "(SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3)", 1);
  end_case("t");

  begin_case("SQLITE_NOMEM through the heap limit, a SELECT that reads no table", NULL, "BEGIN");
  run_limited(db, "SELECT randomblob(100000)", 1);
  end_case("t");

  begin_case("A statement refused at prepare: no such table, then a syntax error", NULL, "BEGIN");
  run(db, "INSERT INTO nosuch VALUES (1)");
  state(db);
  run(db, "INSRT INTO t VALUES (1)");
  end_case("t");

  begin_case("A statement refused at prepare, in a transaction begun by SAVEPOINT", NULL, "SAVEPOINT a");
  run(db, "INSERT INTO nosuch VALUES (1)");
  state(db);
  run(db, "RELEASE a");
  end_case("t");

  return 0;
}
