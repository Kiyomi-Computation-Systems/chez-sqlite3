/* P2: the six settings on a fresh connection under another connection's
 * lock, with a busy timeout set first. Which wait in the busy timeout, and
 * which answer BUSY at once? (The M3 plan, section 8; ADR-0018, decision 5.)
 *
 *   p2-settings-locks DIR TIMING
 *
 * Each case has a fresh file holding t(x) with 3 committed rows, in
 * rollback-journal ("delete") or WAL mode. c1 opens it and holds one of:
 *
 *   none       nothing: c1 open and idle, the control
 *   read       BEGIN, then "SELECT x FROM t" stepped once and held at its row
 *   reserved   BEGIN IMMEDIATE, then an INSERT
 *   exclusive  BEGIN EXCLUSIVE, then an INSERT
 *
 * Then c2 opens the file, fresh, as open-database opens a connection, and
 * runs "PRAGMA busy_timeout = 200" first, as ADR-0018 runs it, then the
 * case's statement S: a set or a read form of the six settings, or a
 * SELECT of the table, the control. S's prepare and its steps are timed
 * apart, and each is told "at once" under 60 ms, "waited" at 190 ms or more,
 * else "between". Each case runs RUNS times; the first run's facts are
 * printed with how many runs gave the same facts, and the times go to
 * TIMING as distributions. Codes are extended.
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

/* first_value: the text of a statement's first column, or a word for none. */
static void first_value(sqlite3_stmt *st, char *out, size_t size) {
  const unsigned char *t = sqlite3_column_text(st, 0);
  snprintf(out, size, "%s", t ? (const char *)t : "NULL");
}

/* run_timed: SQL on DB; its facts into FACTS, prepare's and steps' times. */
static void run_timed(sqlite3 *db, const char *sql, char *facts, size_t size, double *prep_ms,
                      double *step_ms) {
  sqlite3_stmt *st = NULL;
  char row[64] = "no row";
  double t0 = now_ms();
  int p = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  double t1 = now_ms();
  int pe = sqlite3_extended_errcode(db);
  *prep_ms = t1 - t0;
  *step_ms = 0;
  if (p != SQLITE_OK || st == NULL) {
    snprintf(facts, size, "prepare %d (%s)", p == SQLITE_OK ? 0 : pe, told(*prep_ms));
    return;
  }
  int rows = 0, s;
  double t2 = now_ms();
  while ((s = sqlite3_step(st)) == SQLITE_ROW) {
    if (rows++ == 0) first_value(st, row, sizeof row);
  }
  double t3 = now_ms();
  int se = sqlite3_extended_errcode(db);
  *step_ms = t3 - t2;
  sqlite3_finalize(st);
  snprintf(facts, size, "prepare 0 (%s), step %d (%s), row %s", told(*prep_ms),
           s == SQLITE_DONE ? 101 : se, told(*step_ms), rows ? row : "none");
}

static void hold_lock(sqlite3 *c1, const char *lock, sqlite3_stmt **h) {
  *h = NULL;
  if (strcmp(lock, "read") == 0) {
    must(c1, "BEGIN");
    if (sqlite3_prepare_v2(c1, "SELECT x FROM t", -1, h, NULL) != SQLITE_OK) exit(2);
    if (sqlite3_step(*h) != SQLITE_ROW) exit(2);
  } else if (strcmp(lock, "reserved") == 0) {
    must(c1, "BEGIN IMMEDIATE; INSERT INTO t VALUES (9)");
  } else if (strcmp(lock, "exclusive") == 0) {
    must(c1, "BEGIN EXCLUSIVE; INSERT INTO t VALUES (9)");
  }
}

static void one(const char *journal, const char *lock, const char *sql, char *facts, size_t size,
                double *prep_ms, double *step_ms) {
  char file[64], setup[64], bt_facts[160], s_facts[200];
  double bt_prep, bt_step;
  snprintf(file, sizeof file, "p2-%d.db", case_number++);
  sqlite3 *c1 = open_at(file);
  snprintf(setup, sizeof setup, "PRAGMA journal_mode = %s", journal);
  must(c1, setup);
  must(c1, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  sqlite3_stmt *h;
  hold_lock(c1, lock, &h);
  sqlite3 *c2 = open_at(file);
  run_timed(c2, "PRAGMA busy_timeout = 200", bt_facts, sizeof bt_facts, &bt_prep, &bt_step);
  run_timed(c2, sql, s_facts, sizeof s_facts, prep_ms, step_ms);
  snprintf(facts, size, "busy_timeout = 200: %s; S: %s", bt_facts, s_facts);
  int r2 = sqlite3_close(c2);
  if (h) sqlite3_finalize(h);
  if (!sqlite3_get_autocommit(c1)) must(c1, "ROLLBACK");
  int r1 = sqlite3_close(c1);
  if (r1 != SQLITE_OK || r2 != SQLITE_OK) { fprintf(stderr, "close: %d %d\n", r1, r2); exit(2); }
}

static void a_case(const char *journal, const char *lock, const char *sql) {
  char first[512], facts[512], label[256];
  double p[RUNS], s[RUNS];
  int same = 0;
  for (int i = 0; i < RUNS; i++) {
    one(journal, lock, sql, i == 0 ? first : facts, sizeof first, &p[i], &s[i]);
    if (i == 0 || strcmp(first, facts) == 0) same++;
  }
  printf("  %-6s %-9s %-30s %s (%d of %d)\n", journal, lock, sql, first, same, RUNS);
  snprintf(label, sizeof label, "%s %s %s: prepare", journal, lock, sql);
  dist(label, p, RUNS);
  snprintf(label, sizeof label, "%s %s %s: steps", journal, lock, sql);
  dist(label, s, RUNS);
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: p2-settings-locks DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  version_lines();
  printf("\nP2. The six settings on a fresh connection under another's lock, busy timeout 200 ms\n"
         "    (codes extended: 0 OK, 5 BUSY, 101 DONE)\n");
  static const char *const journals[] = {"delete", "wal"};
  static const char *const locks[] = {"none", "read", "reserved", "exclusive"};
  static const char *const common[] = {
    "PRAGMA busy_timeout", "PRAGMA foreign_keys = 1", "PRAGMA foreign_keys",
    "PRAGMA journal_mode", "PRAGMA synchronous = 1", "PRAGMA synchronous",
    "PRAGMA temp_store = 2", "PRAGMA temp_store", "PRAGMA trusted_schema = 0",
    "PRAGMA trusted_schema", "SELECT count(*) FROM t",
  };
  for (int j = 0; j < 2; j++) {
    for (int l = 0; l < 4; l++) {
      for (size_t i = 0; i < sizeof common / sizeof common[0]; i++)
        a_case(journals[j], locks[l], common[i]);
      a_case(journals[j], locks[l],
             j == 0 ? "PRAGMA journal_mode = wal" : "PRAGMA journal_mode = delete");
    }
  }
  fclose(timing);
  return 0;
}
