/* trap-interrupt-busy-wait.c: sqlite3_interrupt doesn't end a wait in the
 * busy timeout. The step waits the timeout out and answers BUSY, and the
 * interrupt flag is still set when it returns.
 *
 *   trap-interrupt-busy-wait SCRATCH-DIR
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
  volatile int done; /* set by the main thread when the call has returned */
  int running;       /* the call had not returned when the interrupt was made */
  int sent;          /* the interrupt was made */
};

static void *intr_main(void *p) {
  struct intr *s = p;
  sleep_ms(s->delay);
  s->running = !__atomic_load_n(&s->done, __ATOMIC_SEQ_CST);
  sqlite3_interrupt(s->db);
  s->sent = 1;
  return NULL;
}

static void intr_start(struct intr *s, sqlite3 *db, int delay) {
  s->db = db;
  s->delay = delay;
  s->done = 0;
  s->running = 0;
  s->sent = 0;
  if (pthread_create(&s->th, NULL, intr_main, s) != 0) {
    printf("FATAL: pthread_create\n");
    exit(1);
  }
}

static void intr_join(struct intr *s) { pthread_join(s->th, NULL); }

int main(int argc, char **argv) {
  start(argc, argv);
  for (int rep = 1; rep <= 2; rep++) {
    char file[64];
    struct intr s;
    snprintf(file, sizeof file, "trap-busy-%d.db", rep);
    sqlite3 *other = open_db(file);
    exec(other, "CREATE TABLE t(x)");
    sqlite3 *db = open_db(file);
    exec(db, "SELECT count(*) FROM t");
    sqlite3_busy_timeout(db, 1000);
    exec(other, "BEGIN IMMEDIATE");
    intr_start(&s, db, 100);
    double t0 = now_ms();
    int rc = exec(db, "BEGIN IMMEDIATE");
    __atomic_store_n(&s.done, 1, __ATOMIC_SEQ_CST);
    double e = now_ms() - t0;
    intr_join(&s);
    printf("repetition %d: BEGIN IMMEDIATE under another's BEGIN IMMEDIATE, "
           "busy timeout 1000 ms, interrupted from a thread at 100 ms: "
           "answered %d \"%s\", %s; is_interrupted then %d\n",
           rep, rc, sqlite3_errmsg(db),
           e >= 900 ? "after waiting out the timeout"
           : e < 500 ? "early" : "between",
           sqlite3_is_interrupted(db));
    printf("  the interrupt was sent: %s; the call was still running when it "
           "was sent: %s\n",
           s.sent ? "yes" : "NO", s.running ? "yes" : "NO");
    rc = exec(db, "SELECT 1");
    printf("  the next statement answered %d; is_interrupted then %d\n", rc,
           sqlite3_is_interrupted(db));
    exec(other, "COMMIT");
    sqlite3_close(db);
    sqlite3_close(other);
  }
  return 0;
}
