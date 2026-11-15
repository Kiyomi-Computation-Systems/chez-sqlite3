/* sweep.c: A4, SQLite behaviour that the brief's M3 line and section 2.7,
 * and ADR-0010, ADR-0011 and ADR-0014, state as fact, where neither the
 * earlier research nor interrupt.c and busy.c measure it.
 *
 *   sweep SCRATCH-DIR TIMING-FILE
 *
 * Facts go to stdout, and must match byte for byte across runs; timings go
 * to TIMING-FILE. Connections open as chez-sqlite3 opens them: READWRITE |
 * CREATE | EXRESCODE | FULLMUTEX (ADR-0010).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <sqlite3.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef RUNS
#define RUNS 21
#endif

static const char *scratch;
static FILE *timing;
static const char *volatile section = "start";

/* ---- the harness ------------------------------------------------------ */

static void on_alarm(int sig) {
  static const char m[] = "TIMEOUT: the watchdog ended the probe in section ";
  const char *s = section;
  (void)sig;
  if (write(1, m, sizeof m - 1) < 0 || write(1, s, strlen(s)) < 0 ||
      write(1, "\n", 1) < 0)
    _exit(4);
  _exit(3);
}

static void watch(const char *name, unsigned seconds) {
  section = name;
  alarm(seconds);
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

static void deadline_in(struct timespec *d, int ms) {
  clock_gettime(CLOCK_REALTIME, d);
  d->tv_sec += ms / 1000;
  d->tv_nsec += (long)(ms % 1000) * 1000000L;
  if (d->tv_nsec >= 1000000000L) {
    d->tv_sec += 1;
    d->tv_nsec -= 1000000000L;
  }
}

static const char *name_of(int rc) {
  switch (rc) {
  case 0: return "OK";
  case 1: return "ERROR";
  case 4: return "ABORT";
  case 5: return "BUSY";
  case 6: return "LOCKED";
  case 9: return "INTERRUPT";
  case 21: return "MISUSE";
  case 100: return "ROW";
  case 101: return "DONE";
  case 261: return "BUSY_RECOVERY";
  case 516: return "ABORT_ROLLBACK";
  case 517: return "BUSY_SNAPSHOT";
  case 773: return "BUSY_TIMEOUT";
  default: return "?";
  }
}

struct buf {
  char s[16384];
  size_t n;
};

static void bput(struct buf *b, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int k = vsnprintf(b->s + b->n, sizeof b->s - b->n, fmt, ap);
  va_end(ap);
  if (k > 0) b->n += (size_t)k;
  if (b->n >= sizeof b->s) b->n = sizeof b->s - 1;
}

static void fatal(const char *what, sqlite3 *db, int rc) {
  printf("FATAL in %s: %s: %d %s\n", section, what, rc,
         db ? sqlite3_errmsg(db) : "");
  exit(1);
}

static void check_version(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER ||
      strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, runtime %d %s\n",
            SQLITE_VERSION_NUMBER, SQLITE_SOURCE_ID,
            sqlite3_libversion_number(), sqlite3_sourceid());
    exit(2);
  }
  printf("libversion %s\nsourceid %s\n", sqlite3_libversion(),
         sqlite3_sourceid());
  fprintf(timing, "libversion %s\nsourceid %s\n", sqlite3_libversion(),
          sqlite3_sourceid());
}

static int cmpd(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

static void dist(const char *label, double *v, int n, const char *unit) {
  qsort(v, (size_t)n, sizeof *v, cmpd);
  fprintf(timing, "%s: n %d, min %.3f, median %.3f, max %.3f %s\n", label, n,
          v[0], v[n / 2], v[n - 1], unit);
  fprintf(timing, "  sorted:");
  for (int i = 0; i < n; i++) fprintf(timing, " %.3f", v[i]);
  fprintf(timing, "\n");
}

/* ---- SQLite helpers --------------------------------------------------- */

static sqlite3 *open_db(const char *file, int mutex_flag) {
  char path[4096];
  sqlite3 *db = NULL;
  snprintf(path, sizeof path, "%s/%s", scratch, file);
  int rc = sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                               SQLITE_OPEN_EXRESCODE | mutex_flag,
                           NULL);
  if (rc != SQLITE_OK) fatal("open", db, rc);
  return db;
}

static void close_db(sqlite3 *db) {
  int rc = sqlite3_close(db);
  if (rc != SQLITE_OK) fatal("close", db, rc);
}

static sqlite3_stmt *prep(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) fatal(sql, db, rc);
  return st;
}

/* Steps SQL until it answers anything but ROW, then finalizes it. The
 * extended code and message are read straight after the last step. */
struct ans {
  int prep, rc, ext;
  char msg[200];
};

static struct ans run_sql(sqlite3 *db, const char *sql) {
  struct ans a;
  sqlite3_stmt *st = NULL;
  memset(&a, 0, sizeof a);
  a.prep = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (a.prep != SQLITE_OK || st == NULL) {
    a.rc = a.prep;
    a.ext = sqlite3_extended_errcode(db);
    snprintf(a.msg, sizeof a.msg, "%s", sqlite3_errmsg(db));
    if (st) sqlite3_finalize(st);
    return a;
  }
  do a.rc = sqlite3_step(st);
  while (a.rc == SQLITE_ROW);
  a.ext = sqlite3_extended_errcode(db);
  snprintf(a.msg, sizeof a.msg, "%s", sqlite3_errmsg(db));
  sqlite3_finalize(st);
  return a;
}

static void put_ans(struct buf *b, const char *label, struct ans a) {
  if (a.prep != SQLITE_OK)
    bput(b, "%s: prepare answered %d %s, extended %d %s, \"%s\"\n", label,
         a.rc, name_of(a.rc), a.ext, name_of(a.ext), a.msg);
  else
    bput(b, "%s: %d %s, extended %d %s, \"%s\"\n", label, a.rc,
         name_of(a.rc), a.ext, name_of(a.ext), a.msg);
}

static void must(sqlite3 *db, const char *sql) {
  struct ans a = run_sql(db, sql);
  if (a.rc != SQLITE_DONE) fatal(sql, db, a.rc);
}

static long long qint(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = prep(db, sql);
  int rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) fatal(sql, db, rc);
  long long v = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st);
  return v;
}

static void put_state(struct buf *b, const char *label, sqlite3 *db) {
  bput(b, "%s: is_interrupted %d, autocommit %d, txn_state(main) %d\n", label,
       sqlite3_is_interrupted(db), sqlite3_get_autocommit(db),
       sqlite3_txn_state(db, "main"));
}


#include <sys/stat.h>

static struct buf out;

static void flush_out(void) {
  printf("%s", out.s);
  memset(&out, 0, sizeof out);
}

static sqlite3 *open1(const char *file) {
  return open_db(file, SQLITE_OPEN_FULLMUTEX);
}

static void show(const char *label, struct ans a) { put_ans(&out, label, a); }

/* The first step's answer, and the row's first column as text if a row. */
static void pragma_row(const char *label, sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || !st) {
    bput(&out, "%s: prepare %d %s, \"%s\"\n", label, rc, name_of(rc),
         sqlite3_errmsg(db));
    if (st) sqlite3_finalize(st);
    return;
  }
  rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    bput(&out, "%s: row \"%s\"\n", label, t ? (const char *)t : "(NULL)");
  } else {
    bput(&out, "%s: no row, step %d %s\n", label, rc, name_of(rc));
  }
  int f = sqlite3_finalize(st);
  if (f != SQLITE_OK) bput(&out, "  (finalize answered %d %s)\n", f, name_of(f));
}

static long long file_size(const char *file, const char *suffix) {
  char path[4096];
  struct stat s;
  snprintf(path, sizeof path, "%s/%s%s", scratch, file, suffix);
  if (stat(path, &s) != 0) return -1;
  return (long long)s.st_size;
}

static void sizes(const char *label, const char *file) {
  long long w = file_size(file, "-wal");
  bput(&out, "%s: database file %lld bytes; WAL file %s", label,
       file_size(file, ""), w < 0 ? "absent" : "");
  if (w >= 0) bput(&out, "%lld bytes", w);
  bput(&out, "\n");
}

/* S1: brief 2.7, "foreign_keys and busy_timeout reset with each
 * connection". */
static void s1(void) {
  bput(&out, "S1: are busy_timeout and foreign_keys per connection?\n");
  sqlite3 *c1 = open1("s1.db");
  pragma_row("  c1 PRAGMA busy_timeout", c1, "PRAGMA busy_timeout");
  pragma_row("  c1 PRAGMA foreign_keys", c1, "PRAGMA foreign_keys");
  must(c1, "PRAGMA busy_timeout = 500");
  must(c1, "PRAGMA foreign_keys = 1");
  pragma_row("  c1, both set, PRAGMA busy_timeout", c1, "PRAGMA busy_timeout");
  pragma_row("  c1 PRAGMA foreign_keys", c1, "PRAGMA foreign_keys");
  sqlite3 *c2 = open1("s1.db");
  pragma_row("  c2, a second connection to the file, PRAGMA busy_timeout", c2,
             "PRAGMA busy_timeout");
  pragma_row("  c2 PRAGMA foreign_keys", c2, "PRAGMA foreign_keys");
  close_db(c2);
  close_db(c1);
  c1 = open1("s1.db");
  pragma_row("  c1 closed and reopened, PRAGMA busy_timeout", c1,
             "PRAGMA busy_timeout");
  pragma_row("  c1 PRAGMA foreign_keys", c1, "PRAGMA foreign_keys");
  close_db(c1);
  flush_out();
}

/* S2: brief 2.7, "A PRAGMA's value can't be a bound parameter". */
static void s2(void) {
  static const char *sqls[] = {"PRAGMA busy_timeout = ?",
                               "PRAGMA busy_timeout = :ms",
                               "PRAGMA busy_timeout(?)",
                               "PRAGMA journal_mode = ?",
                               "PRAGMA foreign_keys = ?", NULL};
  bput(&out, "S2: a PRAGMA's value as a bound parameter\n");
  sqlite3 *db = open1("s2.db");
  for (int i = 0; sqls[i]; i++) {
    sqlite3_stmt *st = NULL;
    int rc = sqlite3_prepare_v2(db, sqls[i], -1, &st, NULL);
    bput(&out, "  prepare \"%s\": %d %s, \"%s\", statement %s\n", sqls[i], rc,
         name_of(rc), sqlite3_errmsg(db), st ? "made" : "NULL");
    if (st) sqlite3_finalize(st);
  }
  close_db(db);
  flush_out();
}

/* S3: brief 2.7, "a setting is checked by reading its row back": which
 * set forms answer a row, and a set inside a transaction. */
static void s3(void) {
  bput(&out, "S3: the rows the set forms answer\n");
  sqlite3 *db = open1("s3.db");
  must(db, "CREATE TABLE t(x)");
  pragma_row("  PRAGMA busy_timeout = 250", db, "PRAGMA busy_timeout = 250");
  pragma_row("  PRAGMA foreign_keys = 1", db, "PRAGMA foreign_keys = 1");
  pragma_row("  then PRAGMA foreign_keys", db, "PRAGMA foreign_keys");
  pragma_row("  PRAGMA journal_mode = wal", db, "PRAGMA journal_mode = wal");
  must(db, "PRAGMA foreign_keys = 0");
  show("  BEGIN", run_sql(db, "BEGIN"));
  pragma_row("  inside it, PRAGMA foreign_keys = 1", db, "PRAGMA foreign_keys = 1");
  pragma_row("  then PRAGMA foreign_keys", db, "PRAGMA foreign_keys");
  pragma_row("  inside it, PRAGMA busy_timeout = 400", db,
             "PRAGMA busy_timeout = 400");
  show("  COMMIT", run_sql(db, "COMMIT"));
  pragma_row("  after COMMIT, PRAGMA foreign_keys", db, "PRAGMA foreign_keys");
  pragma_row("  PRAGMA busy_timeout", db, "PRAGMA busy_timeout");
  close_db(db);
  flush_out();
}

/* S4: brief 2.7, journal_mode=wal on :memory: (measured before on 3.53.1
 * only) and on a temporary database. */
static void s4(void) {
  bput(&out, "S4: PRAGMA journal_mode=wal where WAL can't be\n");
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(":memory:", &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                               SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX,
                           NULL);
  bput(&out, "  open :memory:: %d %s\n", rc, name_of(rc));
  pragma_row("  PRAGMA journal_mode=wal", db, "PRAGMA journal_mode=wal");
  pragma_row("  then PRAGMA journal_mode", db, "PRAGMA journal_mode");
  rc = sqlite3_close(db);
  bput(&out, "  close: %d %s\n", rc, name_of(rc));
  db = NULL;
  rc = sqlite3_open_v2("", &db,
                       SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                           SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX,
                       NULL);
  bput(&out, "  open \"\" (a temporary database): %d %s\n", rc, name_of(rc));
  pragma_row("  PRAGMA journal_mode", db, "PRAGMA journal_mode");
  pragma_row("  PRAGMA journal_mode=wal", db, "PRAGMA journal_mode=wal");
  pragma_row("  then PRAGMA journal_mode", db, "PRAGMA journal_mode");
  rc = sqlite3_close(db);
  bput(&out, "  close: %d %s\n", rc, name_of(rc));
  flush_out();
}

/* S5: ADR-0011, "sqlite3_close can write, a WAL checkpoint among other
 * things": the last connection's close checkpoints, and no close waits in
 * a busy handler. */
struct counter {
  int calls;
};

static int counting_handler(void *p, int n) {
  struct counter *c = p;
  (void)n;
  c->calls++;
  if (c->calls > 3) return 0;
  sqlite3_sleep(1);
  return 1;
}

static void fill_wal(sqlite3 *db) {
  pragma_row("  journal_mode=wal", db, "PRAGMA journal_mode=wal");
  must(db, "PRAGMA wal_autocheckpoint = 0");
  must(db, "CREATE TABLE t(x)");
  must(db, "INSERT INTO t WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL SELECT "
           "i+1 FROM c WHERE i < 1000) SELECT zeroblob(4000) FROM c");
}

static void s5(void) {
  struct counter c = {0};
  bput(&out, "S5: closing WAL connections\n");
  sqlite3 *c1 = open1("s5a.db");
  fill_wal(c1);
  sizes("  c1 alone wrote 1000 rows of 4000 bytes", "s5a.db");
  int rc = sqlite3_close(c1);
  bput(&out, "  c1 close: %d %s\n", rc, name_of(rc));
  sizes("  then", "s5a.db");

  bput(&out, " with a second connection open, idle, having read:\n");
  c1 = open1("s5b.db");
  fill_wal(c1);
  sqlite3 *c2 = open1("s5b.db");
  bput(&out, "  c2 reads %lld rows\n", qint(c2, "SELECT count(*) FROM t"));
  sizes("  before c1's close", "s5b.db");
  rc = sqlite3_close(c1);
  bput(&out, "  c1 close: %d %s\n", rc, name_of(rc));
  sizes("  then", "s5b.db");
  rc = sqlite3_close(c2);
  bput(&out, "  c2 close: %d %s\n", rc, name_of(rc));
  sizes("  then", "s5b.db");

  bput(&out, " with a second connection's statement holding a row; a counting "
             "busy handler on c1:\n");
  c1 = open1("s5c.db");
  fill_wal(c1);
  sqlite3_busy_handler(c1, counting_handler, &c);
  c2 = open1("s5c.db");
  sqlite3_stmt *r = prep(c2, "SELECT x FROM t");
  rc = sqlite3_step(r);
  bput(&out, "  c2's reader stepped: %d %s\n", rc, name_of(rc));
  rc = sqlite3_close(c1);
  bput(&out, "  c1 close: %d %s [busy handler calls %d]\n", rc, name_of(rc),
       c.calls);
  sizes("  then", "s5c.db");
  sqlite3_finalize(r);
  rc = sqlite3_close(c2);
  bput(&out, "  c2's reader finalized; c2 close: %d %s\n", rc, name_of(rc));
  sizes("  then", "s5c.db");
  flush_out();
}

static void s5_timing(void) {
  double full[RUNS], empty[RUNS];
  for (int i = 0; i < RUNS; i++) {
    char file[64];
    snprintf(file, sizeof file, "s5t-full-%d.db", i);
    sqlite3 *db = open1(file);
    fill_wal(db);
    double t0 = now_ms();
    int rc = sqlite3_close(db);
    full[i] = now_ms() - t0;
    if (rc != SQLITE_OK) fatal("close", NULL, rc);
    snprintf(file, sizeof file, "s5t-empty-%d.db", i);
    db = open1(file);
    must(db, "PRAGMA journal_mode=wal");
    must(db, "CREATE TABLE t(x)");
    must(db, "PRAGMA wal_checkpoint(TRUNCATE)");
    t0 = now_ms();
    rc = sqlite3_close(db);
    empty[i] = now_ms() - t0;
    if (rc != SQLITE_OK) fatal("close", NULL, rc);
  }
  out.n = 0; out.s[0] = 0;
  dist("S5: the last connection's close, its WAL holding about 4 MB unchecked",
       full, RUNS, "ms");
  dist("S5: the last connection's close, its WAL checkpointed and truncated",
       empty, RUNS, "ms");
}

/* S6: the brief (line 104) lists sqlite3_exec "if bound". It is a C call, so it is
 * measured here: an INSERT under another connection's BEGIN IMMEDIATE, busy
 * timeout 250 ms, alone and then interrupted from another thread at 50 ms. */
#define S6_TIMEOUT 250

struct xpeer {
  sqlite3 *db;
  int delay;
  pthread_t th;
  volatile int done; /* set by the main thread when the exec has returned */
  int running;       /* the exec had not returned when the interrupt was made */
  int sent;
  double t_call;
};

static void *xpeer_main(void *p) {
  struct xpeer *s = p;
  sleep_ms(s->delay);
  s->running = !__atomic_load_n(&s->done, __ATOMIC_SEQ_CST);
  s->t_call = now_ms();
  sqlite3_interrupt(s->db);
  s->sent = 1;
  return NULL;
}

static void s6_run(struct buf *b, int interrupted, int run, double *ms) {
  char file[64], err_text[200];
  struct xpeer s;
  char *err = NULL;
  snprintf(file, sizeof file, "s6-%d-%d.db", interrupted, run);
  sqlite3 *c1 = open1(file);
  must(c1, "CREATE TABLE t(x)");
  must(c1, "INSERT INTO t VALUES(1), (2), (3)");
  sqlite3 *c2 = open1(file);
  (void)qint(c2, "SELECT count(*) FROM t");
  if (sqlite3_busy_timeout(c2, S6_TIMEOUT) != SQLITE_OK) fatal("busy_timeout", c2, 0);
  must(c1, "BEGIN IMMEDIATE");
  memset(&s, 0, sizeof s);
  s.db = c2;
  s.delay = 50;
  if (interrupted && pthread_create(&s.th, NULL, xpeer_main, &s) != 0) {
    printf("FATAL: pthread_create\n");
    exit(1);
  }
  double t0 = now_ms();
  int rc = sqlite3_exec(c2, "INSERT INTO t VALUES(9)", NULL, NULL, &err);
  double t1 = now_ms();
  __atomic_store_n(&s.done, 1, __ATOMIC_SEQ_CST);
  int ext = sqlite3_extended_errcode(c2);
  if (interrupted) pthread_join(s.th, NULL);
  snprintf(err_text, sizeof err_text, "%s", err ? err : "(NULL)");
  sqlite3_free(err);
  char errmsg_text[200];
  snprintf(errmsg_text, sizeof errmsg_text, "%s", sqlite3_errmsg(c2));
  ms[run] = t1 - t0;
  if (interrupted)
    bput(b, "  the interrupt was sent: %s; the exec was still running then: %s\n",
         s.sent ? "yes" : "NO", (s.running && s.t_call < t1) ? "yes" : "no");
  bput(b, "  sqlite3_exec answered %d %s, extended %d %s, message out-parameter "
          "\"%s\", sqlite3_errmsg \"%s\"\n",
       rc, name_of(rc), ext, name_of(ext), err_text, errmsg_text);
  bput(b, "  it ended %s\n",
       ms[run] < S6_TIMEOUT / 2.0     ? "early: before half the busy timeout"
       : ms[run] >= S6_TIMEOUT * 0.9  ? "at the busy timeout: at least 90% of it"
                                      : "between half and 90% of the busy timeout");
  int was_interrupted = sqlite3_is_interrupted(c2);
  int autocommit = sqlite3_get_autocommit(c2);
  long long rows = qint(c2, "SELECT count(*) FROM t");
  bput(b, "  then is_interrupted %d, autocommit %d, rows %lld\n", was_interrupted,
       autocommit, rows);
  must(c1, "COMMIT");
  close_db(c2);
  close_db(c1);
}

static void s6(int interrupted) {
  struct buf first, cur;
  double ms[RUNS];
  int same = 0;
  char label[200];
  for (int run = 0; run < RUNS; run++) {
    memset(&cur, 0, sizeof cur);
    s6_run(&cur, interrupted, run, ms);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  printf("S6%c: sqlite3_exec of an INSERT under another connection's BEGIN "
         "IMMEDIATE, busy timeout %d ms%s\n%s",
         interrupted ? 'b' : 'a', S6_TIMEOUT,
         interrupted ? ", interrupted from another thread at 50 ms" : "", first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
  snprintf(label, sizeof label, "S6%c: sqlite3_exec, ms from the call to its return",
           interrupted ? 'b' : 'a');
  dist(label, ms, RUNS, "ms");
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: sweep SCRATCH-DIR TIMING-FILE\n");
    return 2;
  }
  setvbuf(stdout, NULL, _IOLBF, 0);
  scratch = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) {
    perror(argv[2]);
    return 2;
  }
  setvbuf(timing, NULL, _IOLBF, 0);
  signal(SIGALRM, on_alarm);
  check_version();
  fprintf(timing, "RUNS %d per distribution; the machine was shared with "
                  "other probes\n", RUNS);
  watch("S1", 30);
  s1();
  watch("S2", 30);
  s2();
  watch("S3", 30);
  s3();
  watch("S4", 30);
  s4();
  watch("S5", 60);
  s5();
  watch("S5 timing", 120);
  s5_timing();
  watch("S6a", 60);
  s6(0);
  watch("S6b", 60);
  s6(1);
  alarm(0);
  printf("end\n");
  return 0;
}
