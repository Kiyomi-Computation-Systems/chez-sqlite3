/* P14: PRAGMA journal_mode = wal on a file already in WAL, from a fresh
 * connection with a busy timeout set first, while another connection holds
 * a lock: the setting every connection of M3's contention suite carries,
 * which P2's WAL column left out. (The M3 plan, section 8 and section 4.3.
 * The adversarial review of the plan measured it first; this is that
 * measurement in the research's form.)
 *
 *   p14-wal-on-wal DIR TIMING
 *
 * Each case: a fresh file put in WAL and holding t(x) with 3 rows. c1 holds
 * nothing, a read (BEGIN and a SELECT at its row), BEGIN IMMEDIATE and an
 * INSERT, or BEGIN EXCLUSIVE and an INSERT. c2 opens fresh, runs
 * PRAGMA busy_timeout = 200, then the set and its read-back, each timed:
 * "at once" under 60 ms, "waited" at 190 ms or more, else "between". Each case
 * runs RUNS times; the first run's facts are printed with how many runs gave
 * the same facts, and the times go to TIMING as distributions.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef RUNS
#define RUNS 7
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

static const char *told(double ms) {
  return ms < 60 ? "at once" : ms >= 190 ? "waited" : "between";
}

/* run: SQL's answers and its first row's text into OUT; its time. */
static double run(sqlite3 *db, const char *sql, char *out, size_t size) {
  sqlite3_stmt *st = NULL;
  double t0 = now_ms();
  int p = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  int pe = sqlite3_extended_errcode(db);
  if (p != SQLITE_OK || st == NULL) {
    double ms = now_ms() - t0;
    snprintf(out, size, "prepare %d (%s)", pe, told(ms));
    return ms;
  }
  int s = sqlite3_step(st);
  int se = sqlite3_extended_errcode(db);
  double ms = now_ms() - t0;
  char row[32] = "none";
  if (s == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    snprintf(row, sizeof row, "%s", t ? (const char *)t : "NULL");
  }
  int f = sqlite3_finalize(st);
  snprintf(out, size, "step %d, row %s, finalize %d (%s)",
           s == SQLITE_ROW ? 100 : s == SQLITE_DONE ? 101 : se, row, f, told(ms));
  return ms;
}

static void one(const char *lock, char *facts, size_t size, double *set_ms, double *read_ms) {
  char file[64], a[96], b[96];
  snprintf(file, sizeof file, "p14-%d.db", case_number++);
  sqlite3 *c1 = open_at(file);
  must(c1, "PRAGMA journal_mode = wal");
  must(c1, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  sqlite3_stmt *h = NULL;
  if (strcmp(lock, "read") == 0) {
    must(c1, "BEGIN");
    if (sqlite3_prepare_v2(c1, "SELECT x FROM t", -1, &h, NULL) != SQLITE_OK) exit(2);
    if (sqlite3_step(h) != SQLITE_ROW) exit(2);
  } else if (strcmp(lock, "none") != 0) {
    must(c1, lock);
    must(c1, "INSERT INTO t VALUES (9)");
  }
  sqlite3 *c2 = open_at(file);
  must(c2, "PRAGMA busy_timeout = 200");
  *set_ms = run(c2, "PRAGMA journal_mode = wal", a, sizeof a);
  *read_ms = run(c2, "PRAGMA journal_mode", b, sizeof b);
  snprintf(facts, size, "set: %s; read-back: %s", a, b);
  int r2 = sqlite3_close(c2);
  if (h) sqlite3_finalize(h);
  if (!sqlite3_get_autocommit(c1)) must(c1, "ROLLBACK");
  int r1 = sqlite3_close(c1);
  if (r1 != SQLITE_OK || r2 != SQLITE_OK) { fprintf(stderr, "close %d %d\n", r1, r2); exit(2); }
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: p14-wal-on-wal DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  version_lines();
  printf("\nP14. journal_mode = wal on a WAL file, from a fresh connection, busy timeout 200 ms;\n"
         "     codes extended: 100 ROW\n");
  static const char *const locks[] = {"none", "read", "BEGIN IMMEDIATE", "BEGIN EXCLUSIVE"};
  for (int l = 0; l < 4; l++) {
    char first[256], facts[256], label[128];
    double s[RUNS], r[RUNS];
    int same = 0;
    for (int i = 0; i < RUNS; i++) {
      one(locks[l], i == 0 ? first : facts, sizeof first, &s[i], &r[i]);
      if (i == 0 || strcmp(first, facts) == 0) same++;
    }
    printf("  c1 holding %-16s %s (%d of %d)\n", locks[l], first, same, RUNS);
    snprintf(label, sizeof label, "c1 holding %s: the set", locks[l]);
    dist(label, s, RUNS);
    snprintf(label, sizeof label, "c1 holding %s: the read-back", locks[l]);
    dist(label, r, RUNS);
  }
  fclose(timing);
  return 0;
}
