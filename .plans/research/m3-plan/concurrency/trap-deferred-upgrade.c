/* trap-deferred-upgrade.c: a busy timeout doesn't apply to a transaction
 * that has read and then writes while another connection holds the write
 * lock. Its write answers BUSY at once; the same write outside a
 * transaction waits the timeout out.
 *
 *   trap-deferred-upgrade SCRATCH-DIR
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

static const char *scratch;

static void on_alarm(int sig) {
  static const char m[] = "TIMEOUT: the watchdog ended the probe\n";
  (void)sig;
  if (write(1, m, sizeof m - 1) < 0) _exit(4);
  _exit(3);
}

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1e3 + (double)t.tv_nsec / 1e6;
}

static void sleep_ms(int ms) {
  struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000L};
  while (nanosleep(&t, &t) == -1 && errno == EINTR) {
  }
}

static void start(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s SCRATCH-DIR\n", argv[0]);
    exit(2);
  }
  scratch = argv[1];
  setvbuf(stdout, NULL, _IOLBF, 0);
  signal(SIGALRM, on_alarm);
  alarm(60);
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER ||
      strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %s, runtime %s\n", SQLITE_SOURCE_ID,
            sqlite3_sourceid());
    exit(2);
  }
  printf("libversion %s\nsourceid %s\n", sqlite3_libversion(),
         sqlite3_sourceid());
}

/* READWRITE | CREATE | EXRESCODE | FULLMUTEX, as chez-sqlite3 opens one. */
static sqlite3 *open_db(const char *file) {
  char path[4096];
  sqlite3 *db = NULL;
  snprintf(path, sizeof path, "%s/%s", scratch, file);
  if (sqlite3_open_v2(path, &db,
                      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                          SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX,
                      NULL) != SQLITE_OK) {
    printf("FATAL: open\n");
    exit(1);
  }
  return db;
}

/* Prepares and steps SQL to its end: the prepare's code if it failed,
 * else the last step's. */
static int exec(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || !st) return rc;
  do rc = sqlite3_step(st);
  while (rc == SQLITE_ROW);
  sqlite3_finalize(st);
  return rc;
}

/* Runs SQL that must answer DONE: anything else ends the probe, saying so. */
static void must(sqlite3 *db, const char *sql) {
  int rc = exec(db, sql);
  if (rc != SQLITE_DONE) {
    printf("FATAL: setup \"%s\" answered %d\n", sql, rc);
    exit(1);
  }
}

/* The connection's PRAGMA journal_mode, as text. */
static void journal_mode(sqlite3 *db, char *out, size_t n) {
  sqlite3_stmt *st = NULL;
  snprintf(out, n, "(none)");
  if (sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &st, NULL) != SQLITE_OK ||
      !st) {
    printf("FATAL: PRAGMA journal_mode did not prepare\n");
    exit(1);
  }
  if (sqlite3_step(st) == SQLITE_ROW)
    snprintf(out, n, "%s", (const char *)sqlite3_column_text(st, 0));
  sqlite3_finalize(st);
}

static long long count_t(sqlite3 *db) {
  sqlite3_stmt *st = NULL;
  long long n = -1;
  if (sqlite3_prepare_v2(db, "SELECT count(*) FROM t", -1, &st, NULL) == SQLITE_OK &&
      sqlite3_step(st) == SQLITE_ROW)
    n = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st);
  return n;
}

/* A thread that sleeps delay ms, then interrupts db. Joined before db closes. */
struct intr {
  sqlite3 *db;
  int delay;
  pthread_t th;
};

static void *intr_main(void *p) {
  struct intr *s = p;
  sleep_ms(s->delay);
  sqlite3_interrupt(s->db);
  return NULL;
}

static void intr_start(struct intr *s, sqlite3 *db, int delay) {
  s->db = db;
  s->delay = delay;
  if (pthread_create(&s->th, NULL, intr_main, s) != 0) {
    printf("FATAL: pthread_create\n");
    exit(1);
  }
}

static void intr_join(struct intr *s) { pthread_join(s->th, NULL); }

static const char *bucket(double e) {
  return e >= 1800 ? "after waiting out the timeout"
         : e < 100 ? "at once" : "between";
}

int main(int argc, char **argv) {
  start(argc, argv);
  for (int wal = 0; wal <= 1; wal++) {
    for (int rep = 1; rep <= 2; rep++) {
      char file[64];
      snprintf(file, sizeof file, "trap-upgrade-%d-%d.db", wal, rep);
      sqlite3 *c1 = open_db(file);
      char m1[32], m2[32];
      must(c1, "CREATE TABLE t(x)");
      if (wal) {
        /* the pragma answers a row, so it ends in ROW's last step: DONE */
        must(c1, "PRAGMA journal_mode=wal");
      }
      sqlite3 *c2 = open_db(file);
      if (sqlite3_busy_timeout(c2, 2000) != SQLITE_OK) {
        printf("FATAL: sqlite3_busy_timeout\n");
        exit(1);
      }
      journal_mode(c1, m1, sizeof m1);
      journal_mode(c2, m2, sizeof m2);
      must(c1, "BEGIN IMMEDIATE");
      must(c1, "INSERT INTO t VALUES(1)");
      double t0 = now_ms();
      int rc = exec(c2, "INSERT INTO t VALUES(2)");
      double e1 = now_ms() - t0;
      must(c2, "BEGIN");
      long long n = count_t(c2);
      t0 = now_ms();
      int rc2 = exec(c2, "INSERT INTO t VALUES(3)");
      double e2 = now_ms() - t0;
      printf("%s, repetition %d: journal_mode read on c1: %s, on c2: %s\n"
             "  c1 holds BEGIN IMMEDIATE; c2 has busy "
             "timeout 2000 ms\n  c2 autocommit INSERT: %d, %s\n  c2 BEGIN, "
             "reads %lld rows, INSERT: %d, %s; autocommit then %d\n",
             wal ? "WAL" : "rollback journal", rep, m1, m2, rc, bucket(e1), n, rc2,
             bucket(e2), sqlite3_get_autocommit(c2));
      must(c2, "ROLLBACK");
      must(c1, "COMMIT");
      if (sqlite3_close(c2) != SQLITE_OK || sqlite3_close(c1) != SQLITE_OK) {
        printf("FATAL: close\n");
        exit(1);
      }
    }
  }
  return 0;
}
