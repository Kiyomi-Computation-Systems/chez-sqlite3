/* P1: a PRAGMA statement reset and stepped again, with no re-prepare: does
 * its setting apply again? (The M3 plan, section 8; ADR-0020, decision 8.)
 *
 *   p1-pragma-reuse DIR TIMING     (TIMING unused: nothing here is timed)
 *
 * DIR: a fresh directory for this run's databases.
 *
 * For each setting, on a file of its own that holds a table, and for each of
 * prepare_v3's flags 0 and SQLITE_PREPARE_PERSISTENT:
 *
 *   S = "PRAGMA name = A" is prepared, then stepped to done, then reset;
 *   T = "PRAGMA name = B" is prepared, stepped and finalized;
 *   S is stepped again, with no prepare, then reset, then finalized.
 *
 * After each step the value is read by a statement of its own, `PRAGMA
 * name`, prepared afresh. Each line also gives S's re-prepare count,
 * sqlite3_stmt_status(SQLITE_STMTSTATUS_REPREPARE). Every connection opens as
 * chez-sqlite3 opens one: READWRITE | CREATE | EXRESCODE | FULLMUTEX.
 *
 * P1b steps S twice with nothing between, to tell whether S re-prepares on
 * its own. P1c changes busy_timeout between S's steps by the C call
 * sqlite3_busy_timeout, which no PRAGMA statement makes, to tell whether S
 * re-prepares because T ran. P1d is the control: a SELECT stepped twice
 * with nothing between.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;

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

/* read_value: `PRAGMA name`'s first column of its first row, as text. */
static void read_value(sqlite3 *db, const char *name, char *out, size_t size) {
  char sql[256];
  sqlite3_stmt *st = NULL;
  snprintf(sql, sizeof sql, "PRAGMA %s", name);
  snprintf(out, size, "(no row)");
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { snprintf(out, size, "(prepare rc %d)", rc); return; }
  rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    snprintf(out, size, "%s", t ? (const char *)t : "NULL");
  } else if (rc != SQLITE_DONE) {
    snprintf(out, size, "(step rc %d)", rc);
  }
  sqlite3_finalize(st);
}

static int reprepares(sqlite3_stmt *st) {
  return sqlite3_stmt_status(st, SQLITE_STMTSTATUS_REPREPARE, 0);
}

/* run_once: SQL prepared, stepped to done and finalized; its answer. */
static int run_once(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) return rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  int f = sqlite3_finalize(st);
  return rc == SQLITE_DONE ? f : rc;
}

/* step_to_done: S stepped until it stops; the code it stopped on. */
static int step_to_done(sqlite3_stmt *st) {
  int rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  return rc;
}

static void line(sqlite3 *db, sqlite3_stmt *s, const char *name, const char *when) {
  char v[128];
  read_value(db, name, v, sizeof v);
  if (s == NULL) {
    printf("    %-34s reads %s\n", when, v);
    return;
  }
  int r = reprepares(s);
  printf("    %-34s reads %-8s S's reprepares %d\n", when, v, r);
}

struct setting { const char *name; const char *a; const char *b; };

static const struct setting settings[] = {
  {"foreign_keys", "1", "0"},
  {"busy_timeout", "250", "100"},
  {"synchronous", "0", "2"},
  {"temp_store", "2", "1"},
  {"trusted_schema", "0", "1"},
  {"journal_mode", "wal", "delete"},
  {"cache_size", "123", "456"},
  {"user_version", "7", "8"},
};

static void one(const struct setting *s, unsigned flags, int n) {
  char file[64], sql_a[128], sql_b[128];
  snprintf(file, sizeof file, "p1-%d.db", n);
  sqlite3 *db = open_at(file);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  snprintf(sql_a, sizeof sql_a, "PRAGMA %s = %s", s->name, s->a);
  snprintf(sql_b, sizeof sql_b, "PRAGMA %s = %s", s->name, s->b);
  printf("  %s, S \"%s\", T \"%s\", flags %s\n", s->name, sql_a, sql_b,
         flags ? "PERSISTENT" : "0");
  line(db, NULL, s->name, "before S is prepared");
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql_a, -1, flags, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) {
    printf("    S's prepare rc %d\n", rc);
    sqlite3_close(db);
    return;
  }
  line(db, st, s->name, "S prepared, unstepped");
  rc = step_to_done(st);
  printf("    S's first step: rc %d\n", rc);
  line(db, st, s->name, "after S's first step");
  rc = sqlite3_reset(st);
  printf("    S's reset: rc %d\n", rc);
  line(db, st, s->name, "after S's reset");
  rc = run_once(db, sql_b);
  printf("    T: rc %d\n", rc);
  line(db, st, s->name, "after T");
  rc = step_to_done(st);
  printf("    S's second step, no prepare: rc %d\n", rc);
  line(db, st, s->name, "after S's second step");
  rc = sqlite3_reset(st);
  printf("    S's second reset: rc %d\n", rc);
  rc = sqlite3_finalize(st);
  printf("    S's finalize: rc %d\n", rc);
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

/* twice: S stepped, reset and stepped again, with nothing between. Does S
 * re-prepare on its own? */
static void twice(const struct setting *s, int n) {
  char file[64], sql_a[128];
  snprintf(file, sizeof file, "p1b-%d.db", n);
  sqlite3 *db = open_at(file);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  snprintf(sql_a, sizeof sql_a, "PRAGMA %s = %s", s->name, s->a);
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql_a, -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) { printf("  %s: prepare rc %d\n", sql_a, rc); exit(2); }
  int r1 = step_to_done(st);
  int p1 = reprepares(st);
  int z1 = sqlite3_reset(st);
  int r2 = step_to_done(st);
  int p2 = reprepares(st);
  int z2 = sqlite3_reset(st);
  printf("  \"%s\": first step %d, reprepares %d; reset %d; second step %d, reprepares %d;"
         " reset %d\n", sql_a, r1, p1, z1, r2, p2, z2);
  sqlite3_finalize(st);
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

/* by_c_call: busy_timeout's S, with T the C call sqlite3_busy_timeout(db,
 * 100), which no PRAGMA statement makes. */
static void by_c_call(void) {
  sqlite3 *db = open_at("p1c.db");
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, "PRAGMA busy_timeout = 250", -1, SQLITE_PREPARE_PERSISTENT,
                              &st, NULL);
  if (rc != SQLITE_OK) exit(2);
  printf("  S \"PRAGMA busy_timeout = 250\", T the C call sqlite3_busy_timeout(db, 100), flags PERSISTENT\n");
  rc = step_to_done(st);
  printf("    S's first step: rc %d\n", rc);
  line(db, st, "busy_timeout", "after S's first step");
  rc = sqlite3_reset(st);
  printf("    S's reset: rc %d\n", rc);
  rc = sqlite3_busy_timeout(db, 100);
  printf("    T: rc %d\n", rc);
  line(db, st, "busy_timeout", "after T");
  rc = step_to_done(st);
  printf("    S's second step, no prepare: rc %d\n", rc);
  line(db, st, "busy_timeout", "after S's second step");
  sqlite3_finalize(st);
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

/* control: a SELECT, reset and stepped again with nothing between, re-prepares
 * or not; the control P1b's PRAGMAs are read against. */
static void control(unsigned flags) {
  sqlite3 *db = open_at(flags ? "p1d-persistent.db" : "p1d-0.db");
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2)");
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, "SELECT x FROM t", -1, flags, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) exit(2);
  int r1 = step_to_done(st);
  int p1 = reprepares(st);
  int z1 = sqlite3_reset(st);
  int r2 = step_to_done(st);
  int p2 = reprepares(st);
  int z2 = sqlite3_reset(st);
  printf("  \"SELECT x FROM t\", flags %s: first step %d, reprepares %d; reset %d; second step %d,"
         " reprepares %d; reset %d\n", flags ? "PERSISTENT" : "0", r1, p1, z1, r2, p2, z2);
  sqlite3_finalize(st);
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: p1-pragma-reuse DIR [TIMING]\n"); return 2; }
  dir = argv[1];
  version_lines();
  printf("\nP1. A PRAGMA statement reset and stepped again, with no re-prepare\n");
  int n = 0;
  for (size_t i = 0; i < sizeof settings / sizeof settings[0]; i++) {
    one(&settings[i], 0, n++);
    one(&settings[i], SQLITE_PREPARE_PERSISTENT, n++);
  }
  printf("\nP1b. S stepped twice with nothing between, flags PERSISTENT\n");
  for (size_t i = 0; i < sizeof settings / sizeof settings[0]; i++) twice(&settings[i], n++);
  printf("\nP1c. busy_timeout changed by the C call between S's steps\n");
  by_c_call();
  printf("\nP1d. The control: a SELECT stepped twice with nothing between\n");
  control(0);
  control(SQLITE_PREPARE_PERSISTENT);
  return 0;
}
