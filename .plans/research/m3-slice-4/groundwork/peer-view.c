/* peer-view.c: whether a second connection can read while the first holds
 * BEGIN IMMEDIATE, through a savepoint's life: the nested rows of levels.c
 * found the second connection's prepare answering 5 in some cases only.
 *
 *   peer-view DIR
 *
 * Each case: a fresh file (tables t, b, src of 10 rows of 3,000 bytes); db
 * runs the steps in turn; after each, db2 (a connection of its own, opened
 * with the file, which has or has not read the schema first) prepares and
 * steps SELECT count(*) FROM t, and its answer is printed. A third variant
 * opens db2 before db makes the tables, as levels.c does. The last three
 * add levels.c's other tables and trigger, and its PRAGMA foreign_keys = ON.
 * Then the same cases after a NOMEM the hard heap limit caused in this
 * process: with the hard limit alone set back to 0 (H), and with the soft
 * limit set to 0 after it (I). J: db reads src's pages inside its
 * transaction before db2 reads, as levels.c's own view does: first in a
 * process with no limit set yet (J0), then after each kind of lift.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;

static sqlite3 *open_at(const char *name) {
  char path[4096];
  sqlite3 *d = NULL;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &d, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open: %d\n", rc); exit(2); }
  return d;
}

static void must(sqlite3 *d, const char *sql) {
  char *m = NULL;
  if (sqlite3_exec(d, sql, NULL, NULL, &m) != SQLITE_OK) { fprintf(stderr, "%s: %s\n", sql, m); exit(2); }
}

static void peer(sqlite3 *d2, const char *after) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(d2, "SELECT count(*) FROM t", -1, &st, NULL);
  if (rc != SQLITE_OK) { printf("    after %s: db2 prepare %d\n", after, rc); return; }
  rc = sqlite3_step(st);
  int n = rc == SQLITE_ROW ? sqlite3_column_int(st, 0) : -1;
  int f = sqlite3_finalize(st);
  printf("    after %s: db2 step %d (count %d), finalize %d\n", after, rc, n, f);
}

static const char *full_setup =
  "CREATE TABLE r(x); CREATE TABLE u(x UNIQUE); "
  "INSERT INTO u VALUES (1); "
  "CREATE TABLE p(id INTEGER PRIMARY KEY); "
  "CREATE TABLE c(pid REFERENCES p(id) DEFERRABLE INITIALLY DEFERRED); "
  "CREATE TRIGGER tr BEFORE INSERT ON u WHEN new.x = 99 "
  "BEGIN SELECT RAISE(ROLLBACK, 'trigger said rollback'); END;";
static int with_fk = 0, with_full = 0;

/* nomem_then_lift: one NOMEM caused by the hard heap limit at
 * memory_used + 1000, then the limit lifted to 0, and, when SOFT, the soft
 * limit set to 0 as well. Prints the limits read after. */
static void nomem_then_lift(int soft) {
  sqlite3 *m = NULL;
  if (sqlite3_open_v2(":memory:", &m, SQLITE_OPEN_READWRITE | SQLITE_OPEN_EXRESCODE, NULL) != SQLITE_OK) exit(2);
  sqlite3_stmt *st = NULL;
  if (sqlite3_prepare_v2(m, "SELECT randomblob(100000)", -1, &st, NULL) != SQLITE_OK) exit(2);
  sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  int rc = sqlite3_step(st);
  sqlite3_hard_heap_limit64(0);
  if (soft) sqlite3_soft_heap_limit64(0);
  long long h = sqlite3_hard_heap_limit64(-1);
  long long s = sqlite3_soft_heap_limit64(-1);
  sqlite3_finalize(st);
  sqlite3_close(m);
  printf("\n== a NOMEM in another connection (step %d), then sqlite3_hard_heap_limit64(0)%s: hard %lld, soft %lld\n",
         rc, soft ? " and sqlite3_soft_heap_limit64(0)" : "", h, s);
}

static void one(const char *id, int warm, const char **steps) {
  int early = warm == 2;
  char name[64];
  snprintf(name, sizeof name, "%s-%d.db", id, warm);
  printf("\n%s, db2 %s\n", id, warm == 1 ? "read the schema first" : warm == 2 ? "opened before the tables were made, never read" : "fresh: never read the schema");
  sqlite3 *db = open_at(name);
  sqlite3 *early_db2 = early ? open_at(name) : NULL;
  if (with_fk) must(db, "PRAGMA foreign_keys = ON");
  if (with_full) must(db, full_setup);
  must(db, "CREATE TABLE t(x); CREATE TABLE b(x); CREATE TABLE src(x); "
           "INSERT INTO src SELECT replace(hex(zeroblob(1500)), '0', 'a') FROM "
           "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10) SELECT i FROM n);");
  sqlite3 *db2 = early ? early_db2 : open_at(name);
  if (warm == 1) peer(db2, "nothing (the warm-up)");
  for (const char **s = steps; *s; s++) {
    int rc = sqlite3_exec(db, *s, NULL, NULL, NULL);
    printf("  db: %s -> %d\n", *s, rc);
    peer(db2, *s);
  }
  sqlite3_close(db2);
  int c = sqlite3_close(db);
  if (c != SQLITE_OK) { fprintf(stderr, "close %d\n", c); exit(2); }
}

/* reader_case: BEGIN IMMEDIATE and a write, then db itself reads src's
 * pages, as levels.c's own view of the connection does, then db2 reads. */
static void reader_case(const char *id) {
  const char *s[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "SELECT count(*), sum(length(x)) FROM src",
                     "COMMIT", NULL};
  one(id, 0, s);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  dir = argv[1];
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID)) return 2;
  printf("libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
  printf("\n== J0: no heap limit yet in this process\n");
  reader_case("J0-reader-before-any-limit");
  const char *a[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "SAVEPOINT s",
                     "INSERT INTO t VALUES ('inner')", "INSERT INTO b VALUES (1)", "RELEASE s", "COMMIT", NULL};
  const char *b[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "INSERT INTO b VALUES (1)", "COMMIT", NULL};
  const char *c[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "SAVEPOINT s",
                     "INSERT INTO t VALUES ('inner')", "ROLLBACK TO s", "RELEASE s", "COMMIT", NULL};
  const char *d[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "SAVEPOINT s",
                     "SELECT count(*) FROM src", "RELEASE s", "COMMIT", NULL};
  for (int warm = 0; warm < 3; warm++) {
    one("A-savepoint-two-tables", warm, a);
    one("B-no-savepoint-two-tables", warm, b);
    one("C-savepoint-rolled-back", warm, c);
    one("D-savepoint-a-read", warm, d);
  }
  const char *e[] = {"BEGIN IMMEDIATE", "INSERT INTO t VALUES ('outer')", "SAVEPOINT s",
                     "INSERT INTO t VALUES ('inner')", "INSERT INTO b VALUES (1)", "RELEASE s", "COMMIT", NULL};
  printf("\n== levels.c's setup: its other tables and trigger, then foreign_keys ON as well\n");
  with_full = 1;
  one("E-levels-tables", 2, e);
  with_fk = 1;
  one("F-levels-tables-and-foreign-keys", 2, e);
  with_full = 0;
  one("G-foreign-keys-alone", 2, e);
  nomem_then_lift(0);
  one("H-after-a-nomem-hard-limit-lifted", 0, a);
  one("H-after-a-nomem-hard-limit-lifted", 1, b);
  nomem_then_lift(1);
  one("I-after-a-nomem-both-limits-lifted", 0, a);
  one("I-after-a-nomem-both-limits-lifted", 1, b);
  nomem_then_lift(0);
  reader_case("J1-reader-after-a-nomem-hard-limit-lifted");
  nomem_then_lift(1);
  reader_case("J2-reader-after-a-nomem-both-limits-lifted");
  return 0;
}
