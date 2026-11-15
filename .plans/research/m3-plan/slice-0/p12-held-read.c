/* P12: does the busy timeout cover a write while the connection's own
 * statement holds a read, as query-fold's statement does while its
 * procedure runs? (The M3 plan, section 8; its Q14. The adversarial review
 * of the plan measured it first; this is that measurement in the
 * research's form, with the rows the plan builds on.)
 *
 *   p12-held-read DIR TIMING
 *
 * Each case: a fresh file holding t(x) with 3 committed rows, in WAL or
 * rollback-journal ("delete") mode. c1 sets PRAGMA busy_timeout = 1500. Then,
 * by the case:
 *
 *   held     c1 steps H = "SELECT x FROM t" once and holds it at its row;
 *   none     c1 holds nothing, the control;
 *   locked   c1 runs BEGIN IMMEDIATE first, then steps H once and holds it,
 *            as a fold run inside with-transaction would.
 *
 * Then c2, in the same process, runs BEGIN IMMEDIATE and an INSERT and holds
 * them, except in the locked case, where c1 holds the write lock already and
 * c2 runs nothing. Then c1 makes the case's call, timed: BEGIN IMMEDIATE, an
 * autocommit INSERT, or, for locked, an INSERT and SAVEPOINT s, INSERT,
 * RELEASE s. Its facts: the call's answer, extended; "at once" under 100 ms,
 * "waited" at 1400 ms or more, else "between"; autocommit before and after.
 * Each case runs RUNS times; the first run's facts are printed with how many
 * runs gave the same facts, and the call's times go to TIMING as a
 * distribution. Every connection opens as chez-sqlite3 opens one.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef RUNS
#define RUNS 5
#endif

static const char *dir;
static FILE *timing;
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
  fprintf(timing, "libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
}

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1e3 + (double)t.tv_nsec / 1e6;
}

static int cmpd(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return x < y ? -1 : x > y;
}

static void dist(const char *label, double *v, int n) {
  qsort(v, (size_t)n, sizeof *v, cmpd);
  fprintf(timing, "%s: n %d, min %.3f, median %.3f, max %.3f ms\n", label, n, v[0], v[n / 2],
          v[n - 1]);
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

/* exec_rc: SQL run by sqlite3_exec; its extended code, or 0. */
static int exec_rc(sqlite3 *db, const char *sql) {
  int rc = sqlite3_exec(db, sql, NULL, NULL, NULL);
  return rc == SQLITE_OK ? 0 : sqlite3_extended_errcode(db);
}

static const char *told(double ms) {
  return ms < 100 ? "at once" : ms >= 1400 ? "waited" : "between";
}

static void one(const char *journal, const char *hold, const char *call, char *facts,
                size_t size, double *ms) {
  char file[64], setup[64];
  snprintf(file, sizeof file, "p12-%d.db", case_number++);
  sqlite3 *c1 = open_at(file);
  snprintf(setup, sizeof setup, "PRAGMA journal_mode = %s", journal);
  must(c1, setup);
  must(c1, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  must(c1, "PRAGMA busy_timeout = 1500");
  sqlite3 *c2 = open_at(file);
  int locked = strcmp(hold, "locked") == 0;
  int begin = locked ? exec_rc(c1, "BEGIN IMMEDIATE") : -1;
  sqlite3_stmt *h = NULL;
  int hstep = -1;
  if (strcmp(hold, "none") != 0) {
    if (sqlite3_prepare_v2(c1, "SELECT x FROM t", -1, &h, NULL) != SQLITE_OK) exit(2);
    hstep = sqlite3_step(h);
  }
  if (!locked) must(c2, "BEGIN IMMEDIATE; INSERT INTO t VALUES (9)");
  int ac0 = sqlite3_get_autocommit(c1);
  double t0 = now_ms();
  int rc = exec_rc(c1, call);
  *ms = now_ms() - t0;
  int ac1 = sqlite3_get_autocommit(c1);
  int hnext = h ? sqlite3_step(h) : -1;
  int hfin = h ? sqlite3_finalize(h) : -1;
  int commit = locked ? exec_rc(c1, "COMMIT") : -1;
  if (!sqlite3_get_autocommit(c1)) exec_rc(c1, "ROLLBACK");
  if (!sqlite3_get_autocommit(c2)) must(c2, "ROLLBACK");
  snprintf(facts, size,
           "c1's BEGIN IMMEDIATE first %d; H's step %d; autocommit %d; the call %d (%s), "
           "autocommit %d; H's next step %d, finalize %d; c1's COMMIT %d",
           begin, hstep, ac0, rc, told(*ms), ac1, hnext, hfin, commit);
  int r2 = sqlite3_close(c2);
  int r1 = sqlite3_close(c1);
  if (r1 != SQLITE_OK || r2 != SQLITE_OK) { fprintf(stderr, "close: %d %d\n", r1, r2); exit(2); }
}

static void a_case(const char *journal, const char *hold, const char *call) {
  char first[512], facts[512], label[256];
  double v[RUNS];
  int same = 0;
  for (int i = 0; i < RUNS; i++) {
    one(journal, hold, call, i == 0 ? first : facts, sizeof first, &v[i]);
    if (i == 0 || strcmp(first, facts) == 0) same++;
  }
  printf("  %-6s %-6s %s:\n    %s (%d of %d)\n", journal, hold, call, first, same, RUNS);
  snprintf(label, sizeof label, "%s %s %s", journal, hold, call);
  dist(label, v, RUNS);
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: p12-held-read DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  version_lines();
  printf("\nP12. A write beside the connection's own held read; c1's busy timeout 1500 ms;\n"
         "     c2 holds BEGIN IMMEDIATE and an INSERT unless c1 is locked; codes extended,\n"
         "     -1 for what the case didn't run\n");
  static const char *const journals[] = {"wal", "delete"};
  for (int j = 0; j < 2; j++) {
    a_case(journals[j], "none", "BEGIN IMMEDIATE");
    a_case(journals[j], "held", "BEGIN IMMEDIATE");
    a_case(journals[j], "none", "INSERT INTO t VALUES (100)");
    a_case(journals[j], "held", "INSERT INTO t VALUES (100)");
    a_case(journals[j], "locked", "INSERT INTO t VALUES (100)");
    a_case(journals[j], "locked", "SAVEPOINT s; INSERT INTO t VALUES (101); RELEASE s");
  }
  fclose(timing);
  return 0;
}
