/* P7: a transaction's ending while an interrupt sticks behind a statement
 * held at a row. (The M3 plan, section 8; ADR-0017's consequences.)
 *
 *   p7-rollback-sticky DIR TIMING     (TIMING unused: nothing here is timed)
 *
 * Each case has a fresh file holding t(x) with 3 committed rows. Inside a
 * transaction a marker row is inserted, then H = "SELECT x FROM t" is
 * stepped once and held at its row. sqlite3_interrupt is called, on this
 * thread, while no statement is in a step: concurrency I3 measured that a
 * statement held at a row keeps it in force. Then the ending statement E is
 * run, one call at a time: its prepare, its step. Then H is reset, and E is
 * run again, prepared afresh. After each call the line gives
 * sqlite3_get_autocommit, sqlite3_is_interrupted, and how many rows a second
 * connection counts: 3, or 4 once the marker is committed.
 *
 * E is ROLLBACK, COMMIT, or for a savepoint level ROLLBACK TO s then RELEASE
 * s. A last case prepares E before the interrupt, as a statement cache would
 * hold it, and steps it after.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;
static int case_number;

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n", SQLITE_VERSION_NUMBER,
            SQLITE_SOURCE_ID, sqlite3_libversion_number(), sqlite3_sourceid());
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

static void must(sqlite3 *db, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static int count_rows(const char *file) {
  sqlite3 *other = open_at(file);
  sqlite3_stmt *st = NULL;
  int n = -1;
  if (sqlite3_prepare_v2(other, "SELECT count(*) FROM t", -1, &st, NULL) == SQLITE_OK
      && sqlite3_step(st) == SQLITE_ROW)
    n = sqlite3_column_int(st, 0);
  sqlite3_finalize(st);
  sqlite3_close(other);
  return n;
}

static void state(sqlite3 *db, const char *file, const char *after) {
  int ac = sqlite3_get_autocommit(db);
  int ii = sqlite3_is_interrupted(db);
  int n = count_rows(file);
  printf("      after %-28s autocommit %d, is_interrupted %d, another connection counts %d\n",
         after, ac, ii, n);
}

/* run: SQL prepared and stepped, each call reported. */
static void run(sqlite3 *db, const char *file, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  int ext = sqlite3_extended_errcode(db);
  printf("    %s: prepare rc %d (extended %d), %s\n", sql, rc, ext, st ? "a statement" : "NULL");
  if (st) {
    rc = sqlite3_step(st);
    ext = sqlite3_extended_errcode(db);
    printf("      step rc %d (extended %d) \"%s\"\n", rc, ext, sqlite3_errmsg(db));
    rc = sqlite3_finalize(st);
    printf("      finalize rc %d\n", rc);
  }
  state(db, file, sql);
}

static void setup(sqlite3 *db, const char *begin) {
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  must(db, begin);
  must(db, "INSERT INTO t VALUES (100)");
}

static sqlite3_stmt *hold(sqlite3 *db) {
  sqlite3_stmt *h = NULL;
  if (sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &h, NULL) != SQLITE_OK) exit(2);
  int rc = sqlite3_step(h);
  printf("    H stepped once: rc %d\n", rc);
  return h;
}

static void ending(const char *begin, const char *const *ends, int n_ends) {
  char file[64];
  snprintf(file, sizeof file, "p7-%d.db", case_number++);
  sqlite3 *db = open_at(file);
  setup(db, begin);
  sqlite3_stmt *h = hold(db);
  sqlite3_interrupt(db);
  state(db, file, "the interrupt");
  printf("   with H held at its row:\n");
  for (int i = 0; i < n_ends; i++) run(db, file, ends[i]);
  int rc = sqlite3_reset(h);
  printf("   H reset: rc %d\n", rc);
  state(db, file, "H's reset");
  printf("   with H reset:\n");
  for (int i = 0; i < n_ends; i++) run(db, file, ends[i]);
  rc = sqlite3_finalize(h);
  printf("   H finalized: rc %d\n", rc);
  if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

static void prepared_before(void) {
  char file[64];
  snprintf(file, sizeof file, "p7-%d.db", case_number++);
  sqlite3 *db = open_at(file);
  setup(db, "BEGIN");
  sqlite3_stmt *e = NULL;
  int rc = sqlite3_prepare_v2(db, "ROLLBACK", -1, &e, NULL);
  printf("    ROLLBACK prepared before H and the interrupt: rc %d\n", rc);
  sqlite3_stmt *h = hold(db);
  sqlite3_interrupt(db);
  state(db, file, "the interrupt");
  rc = sqlite3_step(e);
  int ext = sqlite3_extended_errcode(db);
  printf("    the held ROLLBACK stepped: rc %d (extended %d) \"%s\"\n", rc, ext, sqlite3_errmsg(db));
  state(db, file, "its step");
  rc = sqlite3_reset(e);
  printf("    its reset: rc %d\n", rc);
  rc = sqlite3_reset(h);
  printf("    H reset: rc %d\n", rc);
  rc = sqlite3_step(e);
  ext = sqlite3_extended_errcode(db);
  printf("    the held ROLLBACK stepped again: rc %d (extended %d) \"%s\"\n", rc, ext,
         sqlite3_errmsg(db));
  state(db, file, "its second step");
  sqlite3_finalize(e);
  sqlite3_finalize(h);
  if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: p7-rollback-sticky DIR [TIMING]\n"); return 2; }
  dir = argv[1];
  version_lines();
  printf("\nP7. Ending a transaction while an interrupt sticks behind a held row\n");
  static const char *const rollback[] = {"ROLLBACK"};
  static const char *const commit[] = {"COMMIT"};
  static const char *const to_release[] = {"ROLLBACK TO s", "RELEASE s"};
  printf("\nP7.1 BEGIN, then ROLLBACK\n");
  ending("BEGIN", rollback, 1);
  printf("\nP7.2 BEGIN, then COMMIT\n");
  ending("BEGIN", commit, 1);
  printf("\nP7.3 BEGIN and SAVEPOINT s, then ROLLBACK TO s and RELEASE s\n");
  ending("BEGIN; SAVEPOINT s", to_release, 2);
  printf("\nP7.4 ROLLBACK prepared before the interrupt, stepped after\n");
  prepared_before();
  return 0;
}
