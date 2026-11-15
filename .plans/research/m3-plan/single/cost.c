/* B4: what preparing costs against reusing a prepared statement, in C.
 *
 *   cost DIR       DIR is unused; the database is :memory:
 *
 * Four loops of N rounds each, on one :memory: connection whose table t
 * holds 1,000 rows to begin with:
 *   insert, prepare each round:  prepare_v3, bind text and int, step, finalize
 *   insert, reuse one statement:  reset, bind text and int, step
 *   select, prepare each round:  prepare_v3, bind int, step, read 2 columns, finalize
 *   select, reuse one statement:  reset, bind int, step, read 2 columns
 * The insert runs in autocommit. prepare_v3 is given the SQL's byte length.
 * The four loops are measured twice: with flags 0, as ADR-0014's prepare
 * passes them, and with SQLITE_PREPARE_PERSISTENT. Each time, the reused
 * statements are prepared once, outside the timing, with the same flags as
 * the loops that prepare each round. The select loop's statement is reset,
 * outside the timing, after each run, so no read stays open into the next
 * run's inserts. Every prepare, bind, step, reset and finalize has its
 * return code checked.
 *
 * RUNS runs; each run does the four loops in turn. Lines starting "time:" are
 * timings, ns per round, min / median / max over the runs; the machine is
 * shared, so they are not compared byte for byte. Every other line is.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define N 2000
#define RUNS 25

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

static double now_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

static void must_rc(int rc, int want, const char *what) {
  if (rc != want) { fprintf(stderr, "%s: rc %d, wanted %d\n", what, rc, want); exit(2); }
}

static const char *INSERT_SQL = "INSERT INTO t(name, n) VALUES (?1, ?2)";
static const char *SELECT_SQL = "SELECT name, n FROM t WHERE id = ?1";
static long long checksum = 0;

static void insert_prepare(sqlite3 *db, int base, unsigned int flags) {
  for (int i = 0; i < N; i++) {
    sqlite3_stmt *st = NULL;
    must_rc(sqlite3_prepare_v3(db, INSERT_SQL, (int)strlen(INSERT_SQL), flags, &st, NULL), SQLITE_OK, "prepare");
    must_rc(sqlite3_bind_text(st, 1, "a typical name", 14, SQLITE_TRANSIENT), SQLITE_OK, "bind");
    must_rc(sqlite3_bind_int64(st, 2, base + i), SQLITE_OK, "bind");
    must_rc(sqlite3_step(st), SQLITE_DONE, "step");
    must_rc(sqlite3_finalize(st), SQLITE_OK, "finalize");
  }
}

static void insert_reuse(sqlite3_stmt *st, int base) {
  for (int i = 0; i < N; i++) {
    must_rc(sqlite3_reset(st), SQLITE_OK, "reset");
    must_rc(sqlite3_bind_text(st, 1, "a typical name", 14, SQLITE_TRANSIENT), SQLITE_OK, "bind");
    must_rc(sqlite3_bind_int64(st, 2, base + i), SQLITE_OK, "bind");
    must_rc(sqlite3_step(st), SQLITE_DONE, "step");
  }
}

static void select_prepare(sqlite3 *db, unsigned int flags) {
  for (int i = 0; i < N; i++) {
    sqlite3_stmt *st = NULL;
    must_rc(sqlite3_prepare_v3(db, SELECT_SQL, (int)strlen(SELECT_SQL), flags, &st, NULL), SQLITE_OK, "prepare");
    must_rc(sqlite3_bind_int64(st, 1, 1 + (i % 1000)), SQLITE_OK, "bind");
    must_rc(sqlite3_step(st), SQLITE_ROW, "step");
    checksum += sqlite3_column_bytes(st, 0);
    checksum += sqlite3_column_int64(st, 1);
    must_rc(sqlite3_finalize(st), SQLITE_OK, "finalize");
  }
}

static void select_reuse(sqlite3_stmt *st) {
  for (int i = 0; i < N; i++) {
    must_rc(sqlite3_reset(st), SQLITE_OK, "reset");
    must_rc(sqlite3_bind_int64(st, 1, 1 + (i % 1000)), SQLITE_OK, "bind");
    must_rc(sqlite3_step(st), SQLITE_ROW, "step");
    checksum += sqlite3_column_bytes(st, 0);
    checksum += sqlite3_column_int64(st, 1);
  }
}

static int cmp(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return x < y ? -1 : x > y;
}

static void report(const char *label, const char *flags, double *t) {
  char full[128];
  snprintf(full, sizeof full, "%s, %s", label, flags);
  qsort(t, RUNS, sizeof t[0], cmp);
  printf("time: %-44s min %7.0f  median %7.0f  max %7.0f  ns/round\n",
         full, t[0] / N, t[RUNS / 2] / N, t[RUNS - 1] / N);
}

/* measure: the four loops, RUNS times after one untimed run, every prepare
 * given FLAGS. */
static void measure(sqlite3 *db, unsigned int flags, const char *name) {
  sqlite3_stmt *ins = NULL, *sel = NULL;
  must_rc(sqlite3_prepare_v3(db, INSERT_SQL, (int)strlen(INSERT_SQL), flags, &ins, NULL), SQLITE_OK, "prepare");
  must_rc(sqlite3_prepare_v3(db, SELECT_SQL, (int)strlen(SELECT_SQL), flags, &sel, NULL), SQLITE_OK, "prepare");
  double t_ip[RUNS], t_ir[RUNS], t_sp[RUNS], t_sr[RUNS];
  /* one warm-up run, untimed */
  insert_prepare(db, 0, flags);
  insert_reuse(ins, 0);
  select_prepare(db, flags);
  select_reuse(sel);
  must_rc(sqlite3_reset(sel), SQLITE_OK, "reset");
  for (int r = 0; r < RUNS; r++) {
    double t0 = now_ns();
    insert_prepare(db, r, flags);
    double t1 = now_ns();
    insert_reuse(ins, r);
    double t2 = now_ns();
    select_prepare(db, flags);
    double t3 = now_ns();
    select_reuse(sel);
    double t4 = now_ns();
    must_rc(sqlite3_reset(sel), SQLITE_OK, "reset");  /* untimed: no read stays open */
    t_ip[r] = t1 - t0; t_ir[r] = t2 - t1; t_sp[r] = t3 - t2; t_sr[r] = t4 - t3;
  }
  must_rc(sqlite3_finalize(ins), SQLITE_OK, "finalize");
  must_rc(sqlite3_finalize(sel), SQLITE_OK, "finalize");
  report("insert, prepare each round", name, t_ip);
  report("insert, reuse one statement", name, t_ir);
  report("select, prepare each round", name, t_sp);
  report("select, reuse one statement", name, t_sr);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: cost DIR\n"); return 2; }
  version_lines();
  printf("rounds per loop %d, runs %d\n", N, RUNS);
  sqlite3 *db = NULL;
  must_rc(sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                          | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL), SQLITE_OK, "open");
  must_rc(sqlite3_exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, n INTEGER);"
                           "INSERT INTO t(name, n) SELECT 'a typical name', value FROM "
                           "(WITH RECURSIVE c(value) AS (SELECT 1 UNION ALL SELECT value + 1 FROM c WHERE value < 1000) "
                           "SELECT value FROM c);", NULL, NULL, NULL), SQLITE_OK, "setup");
  measure(db, 0, "flags 0");
  measure(db, SQLITE_PREPARE_PERSISTENT, "PERSISTENT");
  {
    sqlite3_stmt *st = NULL;
    must_rc(sqlite3_prepare_v2(db, "SELECT count(*) FROM t", -1, &st, NULL), SQLITE_OK, "prepare");
    must_rc(sqlite3_step(st), SQLITE_ROW, "step");
    printf("rows in t afterwards: %lld\n", (long long)sqlite3_column_int64(st, 0));
    must_rc(sqlite3_finalize(st), SQLITE_OK, "finalize");
  }
  printf("select checksum: %lld\n", checksum);
  must_rc(sqlite3_close(db), SQLITE_OK, "close");
  return 0;
}
