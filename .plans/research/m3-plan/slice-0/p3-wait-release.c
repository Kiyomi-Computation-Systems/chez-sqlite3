/* P3: a call waiting in the busy timeout, when the other connection lets go
 * mid-wait. Does it succeed, and how soon after the release? (The M3 plan,
 * section 8; concurrency B6 measured a retry, not a wait that ends early.)
 *
 *   p3-wait-release DIR TIMING
 *
 * A holder thread opens c1 on a fresh file holding t(x) with 3 committed
 * rows, takes the case's lock, says so, sleeps 150 ms, notes the time, and
 * lets go. The main thread, once told, opens c2 fresh, runs
 * "PRAGMA busy_timeout = 1500", then the case's call, timed. Each thread
 * uses only its own connection. Every wait between the threads is bounded,
 * and an alarm ends the probe, naming the case, if one hangs.
 *
 *   P3.1  c2's BEGIN IMMEDIATE, c1 holding BEGIN IMMEDIATE and an INSERT,
 *         let go by COMMIT; in WAL and in rollback-journal mode. Then c2
 *         counts the rows, which is 4 if it sees c1's commit
 *   P3.2  c2's PRAGMA journal_mode = wal on a rollback-journal file, c1
 *         holding BEGIN and a SELECT at its row, let go by finalize and
 *         COMMIT (concurrency B8: BUSY at the step with no timeout)
 *   P3.3  c2's PRAGMA journal_mode, c1 holding BEGIN EXCLUSIVE and an
 *         INSERT, let go by COMMIT (concurrency B10: BUSY at prepare with no
 *         timeout)
 *
 * The facts are the call's answer, and whether it returned after the
 * release and before the timeout's end: "after the release" when its time
 * from the call is at least 140 ms and under 1000 ms. Each case runs RUNS
 * times; the first run's facts are printed with how many runs gave the same
 * facts, and the time from the release to the call's return goes to TIMING
 * as a distribution.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef RUNS
#define RUNS 21
#endif

static const char *dir;
static FILE *timing;
static int case_number;
static const char *volatile section = "start";

static void on_alarm(int sig) {
  static const char m[] = "TIMEOUT: the watchdog ended the probe in case ";
  const char *s = section;
  (void)sig;
  if (write(1, m, sizeof m - 1) < 0 || write(1, s, strlen(s)) < 0 || write(1, "\n", 1) < 0)
    _exit(4);
  _exit(3);
}

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

static void sleep_ms(int ms) {
  struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000L};
  while (nanosleep(&t, &t) == -1 && errno == EINTR) {}
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

/* ---- the holder ------------------------------------------------------- */

struct holder {
  const char *file, *journal, *lock;
  pthread_mutex_t m;
  pthread_cond_t c;
  int locked, failed, commit_rc;
  double released;
};

static void *hold(void *arg) {
  struct holder *h = arg;
  sqlite3 *c1 = open_at(h->file);
  sqlite3_stmt *st = NULL;
  char setup[64];
  snprintf(setup, sizeof setup, "PRAGMA journal_mode = %s", h->journal);
  must(c1, setup);
  must(c1, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)");
  if (strcmp(h->lock, "read") == 0) {
    must(c1, "BEGIN");
    if (sqlite3_prepare_v2(c1, "SELECT x FROM t", -1, &st, NULL) != SQLITE_OK
        || sqlite3_step(st) != SQLITE_ROW)
      h->failed = 1;
  } else {
    must(c1, h->lock);
    must(c1, "INSERT INTO t VALUES (9)");
  }
  pthread_mutex_lock(&h->m);
  h->locked = 1;
  pthread_cond_signal(&h->c);
  pthread_mutex_unlock(&h->m);
  sleep_ms(150);
  h->released = now_ms();
  if (st) sqlite3_finalize(st);
  h->commit_rc = exec_rc(c1, "COMMIT");
  if (!sqlite3_get_autocommit(c1)) exec_rc(c1, "ROLLBACK");
  if (sqlite3_close(c1) != SQLITE_OK) h->failed = 1;
  return NULL;
}

/* ---- a case ----------------------------------------------------------- */

static int count(sqlite3 *db) {
  sqlite3_stmt *st = NULL;
  int n = -1;
  if (sqlite3_prepare_v2(db, "SELECT count(*) FROM t", -1, &st, NULL) == SQLITE_OK
      && sqlite3_step(st) == SQLITE_ROW)
    n = sqlite3_column_int(st, 0);
  sqlite3_finalize(st);
  return n;
}

/* the call: its answer, extended, and the first row's text where it has one */
static void call(sqlite3 *db, const char *sql, char *out, size_t size) {
  sqlite3_stmt *st = NULL;
  int p = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (p != SQLITE_OK) {
    int e = sqlite3_extended_errcode(db);
    snprintf(out, size, "prepare %d", e);
    return;
  }
  int s = sqlite3_step(st);
  int e = sqlite3_extended_errcode(db);
  if (s == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    snprintf(out, size, "row %s", t ? (const char *)t : "NULL");
  } else if (s == SQLITE_DONE) {
    snprintf(out, size, "done");
  } else {
    snprintf(out, size, "step %d", e);
  }
  sqlite3_finalize(st);
}

static void one(const char *journal, const char *lock, const char *sql, int counts,
                char *facts, size_t size, double *after_release) {
  char file[64], answer[96];
  struct holder h = {0};
  snprintf(file, sizeof file, "p3-%d.db", case_number++);
  h.file = file;
  h.journal = journal;
  h.lock = lock;
  pthread_mutex_init(&h.m, NULL);
  pthread_cond_init(&h.c, NULL);
  pthread_t t;
  if (pthread_create(&t, NULL, hold, &h) != 0) exit(2);
  struct timespec until;
  clock_gettime(CLOCK_REALTIME, &until);
  until.tv_sec += 5;
  pthread_mutex_lock(&h.m);
  while (!h.locked) {
    if (pthread_cond_timedwait(&h.c, &h.m, &until) == ETIMEDOUT) {
      printf("TIMEOUT: the holder never took its lock\n");
      exit(3);
    }
  }
  pthread_mutex_unlock(&h.m);
  sqlite3 *c2 = open_at(file);
  int bt = exec_rc(c2, "PRAGMA busy_timeout = 1500");
  double t0 = now_ms();
  call(c2, sql, answer, sizeof answer);
  double t1 = now_ms();
  int n = counts ? count(c2) : -1;
  if (!sqlite3_get_autocommit(c2)) exec_rc(c2, "COMMIT");
  struct timespec join_by;
  clock_gettime(CLOCK_REALTIME, &join_by);
  join_by.tv_sec += 5;
  if (pthread_timedjoin_np(t, NULL, &join_by) != 0) {
    printf("TIMEOUT: the holder never finished\n");
    exit(3);
  }
  double took = t1 - t0;
  *after_release = t1 - h.released;
  snprintf(facts, size, "busy_timeout = 1500 answered %d; c1's COMMIT %d; the call: %s, %s%s", bt,
           h.commit_rc, answer,
           took >= 140 && took < 1000 ? "after the release"
           : took < 140 ? "before the release" : "at the timeout",
           counts ? "; then c2 counts " : "");
  if (counts) {
    size_t len = strlen(facts);
    snprintf(facts + len, size - len, "%d", n);
  }
  if (h.failed) { printf("the holder failed\n"); exit(2); }
  if (sqlite3_close(c2) != SQLITE_OK) { fprintf(stderr, "close c2\n"); exit(2); }
  pthread_mutex_destroy(&h.m);
  pthread_cond_destroy(&h.c);
}

static void a_case(const char *name, const char *journal, const char *lock, const char *sql,
                   int counts) {
  char first[256], facts[256], label[128];
  double v[RUNS];
  int same = 0;
  section = name;
  alarm(60);
  for (int i = 0; i < RUNS; i++) {
    one(journal, lock, sql, counts, i == 0 ? first : facts, sizeof first, &v[i]);
    if (i == 0 || strcmp(first, facts) == 0) same++;
  }
  alarm(0);
  printf("  %s: %s, c1 holding %s; c2's %s:\n    %s (%d of %d runs)\n", name, journal, lock, sql,
         first, same, RUNS);
  snprintf(label, sizeof label, "%s %s: the release to the call's return", name, journal);
  dist(label, v, RUNS);
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: p3-wait-release DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  signal(SIGALRM, on_alarm);
  version_lines();
  printf("\nP3. A busy wait the other connection ends by letting go after 150 ms;\n"
         "    busy timeout 1500 ms; codes extended\n");
  a_case("P3.1", "wal", "BEGIN IMMEDIATE", "BEGIN IMMEDIATE", 1);
  a_case("P3.1", "delete", "BEGIN IMMEDIATE", "BEGIN IMMEDIATE", 1);
  a_case("P3.2", "delete", "read", "PRAGMA journal_mode = wal", 0);
  a_case("P3.3", "delete", "BEGIN EXCLUSIVE", "PRAGMA journal_mode", 0);
  fclose(timing);
  return 0;
}
