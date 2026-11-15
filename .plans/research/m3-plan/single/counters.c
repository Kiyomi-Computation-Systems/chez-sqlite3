/* B2: the change counters, sqlite3_changes64, sqlite3_total_changes64 and
 * sqlite3_last_insert_rowid, after each kind of statement.
 *
 *   counters DIR       DIR: a fresh directory for this run's databases
 *
 * Before each measured statement, prime() runs
 *   INSERT OR REPLACE INTO z(rowid, v) VALUES (7776, 'p'), (7777, 'p')
 * so changes64 is 2 and last_insert_rowid 7777, values no measured statement
 * gives by itself. Each line then shows the three counters after the
 * statement, and total_changes64's move across it.
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
  case 8: return "READONLY"; case 13: return "FULL"; case 19: return "CONSTRAINT";
  case 21: return "MISUSE"; case 100: return "ROW"; case 101: return "DONE";
  default: return "?";
  }
}

static void counters(sqlite3 *db, const char *label, sqlite3_int64 total_before) {
  sqlite3_int64 c = sqlite3_changes64(db);
  sqlite3_int64 t = sqlite3_total_changes64(db);
  sqlite3_int64 r = sqlite3_last_insert_rowid(db);
  printf("    %s: changes64 %lld, total_changes64 +%lld, last_insert_rowid %lld\n",
         label, (long long)c, (long long)(t - total_before), (long long)r);
}

static void prime(sqlite3 *db) {
  must(db, "INSERT OR REPLACE INTO z(rowid, v) VALUES (7776, 'p'), (7777, 'p')");
}

/* measure: prime, run SQL to the end, print the counters. */
static void measure(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  prime(db);
  sqlite3_int64 before = sqlite3_total_changes64(db);
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) {
    printf("    prepare: rc %d, errmsg \"%s\"\n", rc, sqlite3_errmsg(db));
    return;
  }
  int rows = 0;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) rows++;
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE, rows %d\n", rows);
  else printf("    step: rc %d %s, errmsg \"%s\"\n", rc, code_name(rc), sqlite3_errmsg(db));
  counters(db, "after the last step", before);
  int f = sqlite3_finalize(st);
  printf("    finalize: rc %d\n", f);
  counters(db, "after finalize", before);
}

static void show(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) { printf("    show: prepare failed\n"); return; }
  printf("  show: %s\n", sql);
  while (sqlite3_step(st) == SQLITE_ROW) {
    printf("    row:");
    for (int i = 0; i < sqlite3_column_count(st); i++) {
      if (sqlite3_column_type(st, i) == SQLITE_NULL) printf(" NULL");
      else printf(" %s", sqlite3_column_text(st, i));
    }
    printf("\n");
  }
  sqlite3_finalize(st);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: counters DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  sqlite3 *db = open_at("c.db");
  sqlite3_stmt *st;
  printf("\nC0. A fresh connection\n");
  counters(db, "before any statement", 0);
  printf("    total_changes64 %lld\n", (long long)sqlite3_total_changes64(db));
  must(db, "CREATE TABLE z(v); CREATE TABLE t(x);");

  printf("\nC1. INSERT, UPDATE and DELETE of 3 rows\n");
  measure(db, "INSERT INTO t(rowid, x) VALUES (101, 1), (102, 2), (103, 3)");
  measure(db, "UPDATE t SET x = x + 10");
  measure(db, "UPDATE t SET x = x WHERE x > 1000");
  measure(db, "DELETE FROM t WHERE x > 11");
  measure(db, "INSERT INTO t(rowid, x) SELECT 200 + value, value FROM "
              "(WITH RECURSIVE n(value) AS (SELECT 1 UNION ALL SELECT value + 1 FROM n WHERE value < 5) SELECT value FROM n)");

  printf("\nC2. DELETE FROM t with no WHERE, and of an empty table\n");
  measure(db, "DELETE FROM t");
  measure(db, "DELETE FROM t");

  printf("\nC3. DDL\n");
  must(db, "INSERT INTO t VALUES (1), (2), (3)");
  measure(db, "CREATE TABLE d(x)");
  measure(db, "CREATE INDEX ti ON t(x)");
  measure(db, "ALTER TABLE t ADD COLUMN y");
  measure(db, "CREATE VIEW vw AS SELECT x FROM t");
  must(db, "INSERT INTO d VALUES (1), (2), (3), (4)");
  measure(db, "DROP TABLE d");
  measure(db, "DROP INDEX ti");

  printf("\nC4. SELECT, PRAGMA and transaction statements\n");
  measure(db, "SELECT x FROM t");
  measure(db, "PRAGMA user_version = 5");
  measure(db, "BEGIN");
  measure(db, "COMMIT");

  printf("\nC5. A statement that fails partway\n");
  must(db, "CREATE TABLE f(x UNIQUE); INSERT INTO f(rowid, x) VALUES (1, 1);");
  measure(db, "INSERT INTO f(rowid, x) VALUES (301, 31), (302, 32), (303, 1), (304, 34)");
  measure(db, "INSERT OR FAIL INTO f(rowid, x) VALUES (401, 41), (402, 42), (403, 1), (404, 44)");
  measure(db, "INSERT INTO f(rowid, x) VALUES (501, 1)");
  measure(db, "UPDATE f SET x = 1 WHERE x > 40");
  show(db, "SELECT rowid, x FROM f ORDER BY rowid");

  printf("\nC6. INSERT OR IGNORE that ignores, and that doesn't\n");
  measure(db, "INSERT OR IGNORE INTO f(rowid, x) VALUES (601, 1)");
  measure(db, "INSERT OR IGNORE INTO f(rowid, x) VALUES (602, 1), (603, 63)");

  printf("\nC7. INSERT OR REPLACE that replaces\n");
  must(db, "CREATE TABLE r(id INTEGER PRIMARY KEY, u UNIQUE); "
           "INSERT INTO r VALUES (1, 'a'), (2, 'b'), (3, 'c');");
  measure(db, "INSERT OR REPLACE INTO r VALUES (1, 'a2')");
  measure(db, "INSERT OR REPLACE INTO r VALUES (9, 'b')");
  measure(db, "INSERT OR REPLACE INTO r VALUES (3, 'a2')");
  show(db, "SELECT id, u FROM r ORDER BY id");

  printf("\nC8. Upserts\n");
  must(db, "CREATE TABLE up(k UNIQUE, v); INSERT INTO up(rowid, k, v) VALUES (11, 1, 'one');");
  measure(db, "INSERT INTO up(rowid, k, v) VALUES (12, 1, 'uno') ON CONFLICT(k) DO UPDATE SET v = excluded.v");
  measure(db, "INSERT INTO up(rowid, k, v) VALUES (13, 1, 'eins') ON CONFLICT(k) DO NOTHING");
  measure(db, "INSERT INTO up(rowid, k, v) VALUES (14, 1, 'un'), (15, 5, 'cinq') ON CONFLICT(k) DO UPDATE SET v = excluded.v");
  measure(db, "INSERT INTO up(rowid, k, v) VALUES (16, 5, 'fem'), (17, 1, 'en') ON CONFLICT(k) DO UPDATE SET v = excluded.v");
  show(db, "SELECT rowid, k, v FROM up ORDER BY rowid");

  printf("\nC9. A trigger's own writes; last_insert_rowid() and changes() inside it\n");
  must(db, "CREATE TABLE tg(x); CREATE TABLE lg(tag, new_rowid, lir, ch);"
           "CREATE TRIGGER tg_bi BEFORE INSERT ON tg BEGIN "
           "  INSERT INTO lg(rowid, tag, new_rowid, lir, ch) VALUES (NULL, 'before', new.rowid, last_insert_rowid(), changes()); END;"
           "CREATE TRIGGER tg_ai AFTER INSERT ON tg BEGIN "
           "  INSERT INTO lg(tag, new_rowid, lir, ch) VALUES ('after 1', new.rowid, last_insert_rowid(), changes());"
           "  INSERT INTO lg(tag, new_rowid, lir, ch) VALUES ('after 2', new.rowid, last_insert_rowid(), changes()); END;"
           "CREATE TRIGGER tg_au AFTER UPDATE ON tg BEGIN "
           "  INSERT INTO lg(tag, new_rowid, lir, ch) VALUES ('update', new.rowid, last_insert_rowid(), changes()); END;");
  measure(db, "INSERT INTO tg(rowid, x) VALUES (500, 'a'), (501, 'b')");
  show(db, "SELECT rowid, tag, new_rowid, lir, ch FROM lg ORDER BY rowid");
  measure(db, "UPDATE tg SET x = x || '!'");
  show(db, "SELECT rowid, tag, new_rowid, lir, ch FROM lg WHERE tag = 'update' ORDER BY rowid");

  printf("\nC10. A foreign-key cascade\n");
  must(db, "PRAGMA foreign_keys = ON;"
           "CREATE TABLE p(id INTEGER PRIMARY KEY);"
           "CREATE TABLE ch(pid REFERENCES p(id) ON DELETE CASCADE ON UPDATE CASCADE);"
           "INSERT INTO p VALUES (1), (2);"
           "INSERT INTO ch VALUES (1), (1), (1), (2);");
  measure(db, "DELETE FROM p WHERE id = 1");
  measure(db, "UPDATE p SET id = 20 WHERE id = 2");
  show(db, "SELECT pid FROM ch");

  printf("\nC11. A WITHOUT ROWID table\n");
  must(db, "CREATE TABLE wr(k PRIMARY KEY, v) WITHOUT ROWID;");
  measure(db, "INSERT INTO wr VALUES ('a', 1), ('b', 2)");
  measure(db, "UPDATE wr SET v = v + 1");
  measure(db, "INSERT OR REPLACE INTO wr VALUES ('a', 9)");

  printf("\nC12. INSERT ... RETURNING of 3 rows, step by step\n");
  prime(db);
  {
    sqlite3_int64 before = sqlite3_total_changes64(db);
    sqlite3_prepare_v2(db, "INSERT INTO t(rowid, x) VALUES (901, 'r1'), (902, 'r2'), (903, 'r3') RETURNING rowid", -1, &st, NULL);
    counters(db, "prepared", before);
    for (int i = 1; i <= 4; i++) {
      int rc = sqlite3_step(st);
      char l[64];
      snprintf(l, sizeof l, "step %d (rc %d %s)", i, rc, code_name(rc));
      counters(db, l, before);
    }
    printf("    reset: rc %d\n", sqlite3_reset(st));
    counters(db, "after reset", before);
    sqlite3_finalize(st);
  }
  printf("\nC12b. INSERT ... RETURNING of 3 rows, stepped once, then reset\n");
  prime(db);
  {
    sqlite3_int64 before = sqlite3_total_changes64(db);
    sqlite3_prepare_v2(db, "INSERT INTO t(rowid, x) VALUES (911, 'r1'), (912, 'r2'), (913, 'r3') RETURNING rowid", -1, &st, NULL);
    int rc = sqlite3_step(st);
    char l[64];
    snprintf(l, sizeof l, "step 1 (rc %d %s)", rc, code_name(rc));
    counters(db, l, before);
    printf("    reset: rc %d\n", sqlite3_reset(st));
    counters(db, "after reset", before);
    sqlite3_finalize(st);
    show(db, "SELECT count(*) FROM t WHERE rowid BETWEEN 911 AND 913");
  }
  printf("\nC12c. DELETE ... RETURNING of 3 rows, stepped once, then finalized\n");
  prime(db);
  {
    sqlite3_int64 before = sqlite3_total_changes64(db);
    sqlite3_prepare_v2(db, "DELETE FROM t WHERE rowid BETWEEN 911 AND 913 RETURNING rowid", -1, &st, NULL);
    int rc = sqlite3_step(st);
    char l[64];
    snprintf(l, sizeof l, "step 1 (rc %d %s)", rc, code_name(rc));
    counters(db, l, before);
    printf("    finalize: rc %d\n", sqlite3_finalize(st));
    counters(db, "after finalize", before);
  }

  printf("\nC13. Another connection's writes\n");
  {
    sqlite3 *db2 = open_at("c.db");
    prime(db);
    sqlite3_int64 before = sqlite3_total_changes64(db);
    sqlite3_int64 before2 = sqlite3_total_changes64(db2);
    must(db2, "INSERT INTO t(rowid, x) VALUES (8001, 1), (8002, 2), (8003, 3)");
    counters(db, "db, after db2's 3-row INSERT", before);
    counters(db2, "db2 itself", before2);
    must(db2, "DELETE FROM t WHERE rowid > 8000");
    counters(db, "db, after db2's 3-row DELETE", before);
    close_db(db2);
  }

  printf("\nC14. A statement prepared but never stepped, then finalized\n");
  measure(db, "SELECT 1 WHERE 0");
  prime(db);
  {
    sqlite3_int64 before = sqlite3_total_changes64(db);
    sqlite3_prepare_v2(db, "INSERT INTO t VALUES (1)", -1, &st, NULL);
    sqlite3_finalize(st);
    counters(db, "INSERT prepared and finalized, unstepped", before);
  }

  printf("\nC15. Rows written in a transaction that is rolled back\n");
  prime(db);
  {
    sqlite3_int64 before = sqlite3_total_changes64(db);
    must(db, "BEGIN; INSERT INTO t(rowid, x) VALUES (7001, 1), (7002, 2);");
    counters(db, "after the INSERT", before);
    must(db, "ROLLBACK");
    counters(db, "after ROLLBACK", before);
  }

  close_db(db);
  return 0;
}
