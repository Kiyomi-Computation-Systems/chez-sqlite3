/* p7-cached.c: slice-0 P7 again, for with-transaction's statements as its
 * cache holds them: prepared SQLITE_PREPARE_PERSISTENT before the
 * interrupt, stepped once by an earlier use and reset, ready.
 *
 *   p7-cached DIR
 *
 * P7.4 measured one such statement, a ROLLBACK. This measures each of
 * with-transaction's ending statements so: COMMIT and ROLLBACK at the outer
 * level, RELEASE chez_sqlite3_1 and ROLLBACK TO chez_sqlite3_1 at a nested
 * one; each one's step, reset and finalize answers, as slice 3's cache
 * finalizes a statement whose step failed; then a fresh prepare of the same
 * SQL; then, once the held statement H is reset, the level ended normally.
 *
 * The file holds t, 3 committed rows. A transaction: BEGIN IMMEDIATE, a
 * marker; nested: SAVEPOINT chez_sqlite3_1 and a second marker. Then
 * H = SELECT x FROM t stepped once and held, and sqlite3_interrupt while no
 * step runs (P7's order). db2 counts t's rows.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;
static sqlite3 *db, *db2;

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

static sqlite3_stmt *cached(const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  if (rc != SQLITE_OK || !st) { fprintf(stderr, "%s: prepare %d\n", sql, rc); exit(2); }
  return st;
}

/* use: an earlier use of a cached statement: stepped to DONE, reset. */
static void use(sqlite3_stmt *st) {
  int rc = sqlite3_step(st);
  if (rc != SQLITE_DONE) { fprintf(stderr, "%s: earlier step %d\n", sqlite3_sql(st), rc); exit(2); }
  rc = sqlite3_reset(st);
  if (rc != SQLITE_OK) { fprintf(stderr, "%s: earlier reset %d\n", sqlite3_sql(st), rc); exit(2); }
}

static int count_t(sqlite3 *d) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(d, "SELECT count(*) FROM t", -1, &st, NULL);
  if (rc != SQLITE_OK) return -100 - rc;
  rc = sqlite3_step(st);
  int n = rc == SQLITE_ROW ? sqlite3_column_int(st, 0) : -200 - rc;
  sqlite3_finalize(st);
  return n;
}

static void status(const char *when) {
  int ac = sqlite3_get_autocommit(db);
  int intr = sqlite3_is_interrupted(db);
  int n = count_t(db2);
  printf("    %s: autocommit %d, is_interrupted %d, db2 counts %d\n", when, ac, intr, n);
}

/* cached_try: the cached statement's step, reset and finalize, as the
 * cache would run them on a failed step. */
static void cached_try(sqlite3_stmt *st) {
  const char *sql = sqlite3_sql(st);
  char copy[128];
  snprintf(copy, sizeof copy, "%s", sql);
  int rc = sqlite3_step(st);
  int ext = sqlite3_extended_errcode(db);
  char msg[128];
  snprintf(msg, sizeof msg, "%s", sqlite3_errmsg(db));
  int r = sqlite3_reset(st);
  int f = sqlite3_finalize(st);
  printf("  cached %s: step %d, extended %d, \"%s\"; reset %d; finalize %d\n", copy, rc, ext, msg, r, f);
}

static void fresh_try(const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  int ext = sqlite3_extended_errcode(db);
  if (rc != SQLITE_OK || !st) {
    printf("  fresh %s: prepare %d, extended %d, \"%s\", statement %s\n", sql, rc, ext,
           sqlite3_errmsg(db), st ? "made" : "NULL");
    if (st) sqlite3_finalize(st);
    return;
  }
  rc = sqlite3_step(st);
  ext = sqlite3_extended_errcode(db);
  int f = sqlite3_finalize(st);
  printf("  fresh %s: prepare 0; step %d, extended %d; finalize %d\n", sql, rc, ext, f);
}

static sqlite3_stmt *hold(void) {
  sqlite3_stmt *h = NULL;
  int rc = sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &h, NULL);
  if (rc != SQLITE_OK) exit(2);
  rc = sqlite3_step(h);
  printf("  H = SELECT x FROM t, step: %d\n", rc);
  sqlite3_interrupt(db);
  printf("  sqlite3_interrupt, no step running\n");
  return h;
}

static void setup(const char *name) {
  db = open_at(name);
  db2 = open_at(name);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3);");
}

static void outer(void) {
  printf("\nA. the outer level: cached COMMIT and ROLLBACK\n");
  setup("a.db");
  sqlite3_stmt *begin = cached("BEGIN IMMEDIATE");
  sqlite3_stmt *commit = cached("COMMIT");
  sqlite3_stmt *rollback = cached("ROLLBACK");
  use(begin); use(commit); use(begin); use(rollback);
  printf("  earlier uses: BEGIN IMMEDIATE, COMMIT; BEGIN IMMEDIATE, ROLLBACK; each reset, kept\n");
  use(begin);
  must(db, "INSERT INTO t VALUES ('marker')");
  status("the level begun, its marker written");
  sqlite3_stmt *h = hold();
  status("after the interrupt");
  cached_try(rollback);
  status("after it");
  cached_try(commit);
  status("after it");
  fresh_try("ROLLBACK");
  fresh_try("COMMIT");
  status("after them");
  int r = sqlite3_reset(h);
  printf("  H reset: %d\n", r);
  status("after H's reset");
  fresh_try("ROLLBACK");
  status("after the fresh ROLLBACK");
  int f = sqlite3_finalize(h);
  int fb = sqlite3_finalize(begin);
  printf("  H finalize %d; BEGIN finalize %d\n", f, fb);
  int c2 = sqlite3_close(db2), c1 = sqlite3_close(db);
  if (c1 || c2) { fprintf(stderr, "close %d %d\n", c1, c2); exit(2); }
}

static void nested(void) {
  printf("\nB. a nested level: cached RELEASE chez_sqlite3_1 and ROLLBACK TO chez_sqlite3_1\n");
  setup("b.db");
  sqlite3_stmt *begin = cached("BEGIN IMMEDIATE");
  sqlite3_stmt *commit = cached("COMMIT");
  sqlite3_stmt *sp = cached("SAVEPOINT chez_sqlite3_1");
  sqlite3_stmt *release = cached("RELEASE chez_sqlite3_1");
  sqlite3_stmt *rollback_to = cached("ROLLBACK TO chez_sqlite3_1");
  use(begin); use(sp); use(release); use(sp); use(rollback_to); use(release); use(commit);
  printf("  earlier uses: BEGIN IMMEDIATE; SAVEPOINT, RELEASE; SAVEPOINT, ROLLBACK TO, RELEASE; COMMIT\n");
  use(begin);
  must(db, "INSERT INTO t VALUES ('outer')");
  use(sp);
  must(db, "INSERT INTO t VALUES ('inner')");
  status("both levels begun, their markers written");
  sqlite3_stmt *h = hold();
  cached_try(release);
  status("after it");
  cached_try(rollback_to);
  status("after it");
  fresh_try("ROLLBACK TO chez_sqlite3_1");
  fresh_try("RELEASE chez_sqlite3_1");
  status("after them");
  int r = sqlite3_reset(h);
  printf("  H reset: %d\n", r);
  fresh_try("ROLLBACK TO chez_sqlite3_1");
  fresh_try("RELEASE chez_sqlite3_1");
  status("after the nested level's rollback");
  must(db, "COMMIT");
  status("after the outer COMMIT");
  int f = sqlite3_finalize(h);
  int fb = sqlite3_finalize(begin), fc = sqlite3_finalize(commit), fs = sqlite3_finalize(sp);
  printf("  H finalize %d; BEGIN, COMMIT, SAVEPOINT finalize %d %d %d\n", f, fb, fc, fs);
  int c2 = sqlite3_close(db2), c1 = sqlite3_close(db);
  if (c1 || c2) { fprintf(stderr, "close %d %d\n", c1, c2); exit(2); }
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  dir = argv[1];
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID)) {
    fprintf(stderr, "refused: header and library differ\n");
    return 2;
  }
  printf("libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
  outer();
  nested();
  return 0;
}
