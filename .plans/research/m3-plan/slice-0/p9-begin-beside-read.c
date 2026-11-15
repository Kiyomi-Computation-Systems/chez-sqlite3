/* P9: BEGIN in autocommit while the connection's own SELECT holds a read.
 * (The M3 plan, section 8; ADR-0017, decision 2: with-transaction issues
 * BEGIN whenever autocommit is 1, which this state is: single B1, item 2.)
 *
 *   p9-begin-beside-read DIR TIMING
 *
 * Each case has a fresh file holding t(x) with 3 committed rows, in WAL or
 * rollback-journal mode. c1 steps H = "SELECT x FROM t" once and holds it at
 * its row (autocommit 1). Then, when the case says so, c2 inserts a row in
 * autocommit. Then c1 runs BEGIN in a mode, then INSERT, then COMMIT, each
 * answer and autocommit reported, then H is stepped again. c1 has a busy
 * timeout of 300 ms; whether BEGIN waited is told by its time against it:
 * "at once" under 100 ms, "waited" at 290 ms or more. Each case runs RUNS
 * times; the first run's facts are printed with how many runs gave the same
 * facts, and BEGIN's times go to TIMING as a distribution.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef RUNS
#define RUNS 11
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

static const char *waited(double ms) {
  return ms < 100 ? "at once" : ms >= 290 ? "waited" : "between";
}

/* one: a run of the case; its facts written into FACTS, BEGIN's time into MS. */
static void one(const char *mode, const char *journal, int other_commits, char *facts,
                size_t size, double *ms) {
  char file[64];
  snprintf(file, sizeof file, "p9-%d.db", case_number++);
  sqlite3 *c1 = open_at(file);
  char setup[128];
  snprintf(setup, sizeof setup, "PRAGMA journal_mode = %s", journal);
  must(c1, setup);
  must(c1, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  sqlite3 *c2 = open_at(file);
  must(c1, "PRAGMA busy_timeout = 300");
  sqlite3_stmt *h = NULL;
  if (sqlite3_prepare_v2(c1, "SELECT x FROM t", -1, &h, NULL) != SQLITE_OK) exit(2);
  int h1 = sqlite3_step(h);
  int ac0 = sqlite3_get_autocommit(c1);
  int other = other_commits ? exec_rc(c2, "INSERT INTO t VALUES (50)") : -1;
  char begin[64];
  snprintf(begin, sizeof begin, "BEGIN %s", mode);
  double t0 = now_ms();
  int b = exec_rc(c1, begin);
  *ms = now_ms() - t0;
  int ac1 = sqlite3_get_autocommit(c1);
  int ins = exec_rc(c1, "INSERT INTO t VALUES (100)");
  int ac2 = sqlite3_get_autocommit(c1);
  int com = exec_rc(c1, "COMMIT");
  int ac3 = sqlite3_get_autocommit(c1);
  int h2 = sqlite3_step(h);
  int hr = sqlite3_finalize(h);
  if (!sqlite3_get_autocommit(c1)) exec_rc(c1, "ROLLBACK");
  snprintf(facts, size,
           "H's step %d, autocommit %d; c2's insert %d; BEGIN %d (%s), autocommit %d; "
           "INSERT %d, autocommit %d; COMMIT %d, autocommit %d; H's next step %d, finalize %d",
           h1, ac0, other, b, waited(*ms), ac1, ins, ac2, com, ac3, h2, hr);
  int r1 = sqlite3_close(c2);
  int r2 = sqlite3_close(c1);
  if (r1 != SQLITE_OK || r2 != SQLITE_OK) { fprintf(stderr, "close: %d %d\n", r1, r2); exit(2); }
}

static void a_case(const char *mode, const char *journal, int other_commits) {
  char first[512], facts[512], label[128];
  double v[RUNS];
  int same = 0;
  for (int i = 0; i < RUNS; i++) {
    one(mode, journal, other_commits, i == 0 ? first : facts, sizeof first, &v[i]);
    if (i == 0 || strcmp(first, facts) == 0) same++;
  }
  printf("  %s, BEGIN %s, %s: %s\n    (%d of %d runs gave these facts)\n", journal, mode,
         other_commits ? "after c2 commits a row" : "c2 idle", first, same, RUNS);
  snprintf(label, sizeof label, "%s, BEGIN %s, %s: BEGIN's time", journal, mode,
           other_commits ? "after c2's commit" : "c2 idle");
  dist(label, v, RUNS);
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: p9-begin-beside-read DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  version_lines();
  printf("\nP9. BEGIN while the connection's own SELECT holds a read; codes are extended,\n"
         "    0 for SQLITE_OK, and -1 where c2 ran nothing\n");
  static const char *const modes[] = {"DEFERRED", "IMMEDIATE", "EXCLUSIVE"};
  static const char *const journals[] = {"wal", "delete"};
  for (int j = 0; j < 2; j++)
    for (int m = 0; m < 3; m++)
      for (int o = 0; o < 2; o++) a_case(modes[m], journals[j], o);
  fclose(timing);
  return 0;
}
