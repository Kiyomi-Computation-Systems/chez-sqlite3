/* busy.c: A2, the busy timeout and two connections contending, in one
 * process, on a temporary database file; and A4's SQLite claims about
 * busy waits.
 *
 *   busy SCRATCH-DIR TIMING-FILE
 *
 * Facts go to stdout, and must match byte for byte across runs; timings go
 * to TIMING-FILE. Every connection opens as chez-sqlite3 opens one:
 * READWRITE | CREATE | EXRESCODE | FULLMUTEX (ADR-0010). Whether a busy
 * handler ran is read by installing a counting one with
 * sqlite3_busy_handler: it retries LIMIT times, sleeping 1 ms each, then
 * gives up, so under a lock nobody releases it is called LIMIT + 1 times.
 * A watchdog alarm ends the probe, saying so, if a section hangs.
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


/* ---- busy-specific helpers -------------------------------------------- */

static struct buf out;

static void flush_out(void) {
  printf("%s", out.s);
  memset(&out, 0, sizeof out);
}

static sqlite3 *open1(const char *file) {
  return open_db(file, SQLITE_OPEN_FULLMUTEX);
}

#define LIMIT 3

struct counter {
  int calls;
};

static int counting_handler(void *p, int n) {
  struct counter *c = p;
  (void)n;
  c->calls++;
  if (c->calls > LIMIT) return 0;
  sqlite3_sleep(1);
  return 1;
}

static void show(const char *label, struct ans a) { put_ans(&out, label, a); }

static void show_counted(const char *label, sqlite3 *db, const char *sql,
                         struct counter *c) {
  char l[256];
  c->calls = 0;
  struct ans a = run_sql(db, sql);
  snprintf(l, sizeof l, "%s [busy handler calls %d]", label, c->calls);
  show(l, a);
}

static void state(const char *label, sqlite3 *db) {
  bput(&out, "%s: autocommit %d, txn_state(main) %d\n", label,
       sqlite3_get_autocommit(db), sqlite3_txn_state(db, "main"));
}

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
    int ext = sqlite3_extended_errcode(db);
    bput(&out, "%s: no row, step %d %s, extended %d %s, \"%s\"\n", label, rc,
         name_of(rc), ext, name_of(ext), sqlite3_errmsg(db));
  }
  sqlite3_finalize(st);
}

static long long busy_timeout_of(sqlite3 *db) {
  return qint(db, "PRAGMA busy_timeout");
}

static void make_t(sqlite3 *db, int wal) {
  must(db, "CREATE TABLE t(x)");
  must(db, "INSERT INTO t VALUES(1), (2), (3)");
  if (wal) pragma_row("  journal_mode=wal", db, "PRAGMA journal_mode=wal");
}

/* ---- B1: sqlite3_busy_timeout against PRAGMA busy_timeout ------------- */

static void b1(void) {
  struct counter c = {0};
  bput(&out, "B1: sqlite3_busy_timeout against PRAGMA busy_timeout\n");
  sqlite3 *db = open1("b1.db");
  make_t(db, 0);
  bput(&out, "  a new connection's PRAGMA busy_timeout: %lld\n",
       busy_timeout_of(db));
  int rc = sqlite3_busy_timeout(db, 1234);
  bput(&out, "  sqlite3_busy_timeout(db, 1234) answered %d; the pragma reads %lld\n",
       rc, busy_timeout_of(db));
  pragma_row("  PRAGMA busy_timeout = 4321", db, "PRAGMA busy_timeout = 4321");
  bput(&out, "  then the pragma reads %lld\n", busy_timeout_of(db));
  rc = sqlite3_busy_handler(db, counting_handler, &c);
  bput(&out, "  sqlite3_busy_handler(db, counter) answered %d; the pragma reads %lld\n",
       rc, busy_timeout_of(db));
  pragma_row("  PRAGMA busy_timeout = 500, with the counter installed", db,
             "PRAGMA busy_timeout = 500");
  sqlite3 *other = open1("b1.db");
  must(other, "BEGIN IMMEDIATE");
  show_counted("  then, under another's BEGIN IMMEDIATE, BEGIN IMMEDIATE (is the "
               "counter still installed?)", db, "BEGIN IMMEDIATE", &c);
  rc = sqlite3_busy_handler(db, counting_handler, &c);
  rc = sqlite3_busy_timeout(db, 0);
  bput(&out, "  counter reinstalled, then sqlite3_busy_timeout(db, 0) answered %d; "
             "the pragma reads %lld\n",
       rc, busy_timeout_of(db));
  show_counted("  under another's BEGIN IMMEDIATE, BEGIN IMMEDIATE", db,
               "BEGIN IMMEDIATE", &c);
  rc = sqlite3_busy_handler(db, counting_handler, &c);
  bput(&out, "  counter reinstalled (answered %d), then ", rc);
  rc = sqlite3_busy_timeout(db, -1);
  bput(&out, "sqlite3_busy_timeout(db, -1) answered %d; the pragma reads %lld\n",
       rc, busy_timeout_of(db));
  show_counted("  under another's BEGIN IMMEDIATE, BEGIN IMMEDIATE", db,
               "BEGIN IMMEDIATE", &c);
  must(other, "COMMIT");
  close_db(other);
  rc = sqlite3_busy_timeout(db, 300);
  rc = sqlite3_busy_timeout(db, -1);
  bput(&out, "  sqlite3_busy_timeout(db, 300), then (db, -1) answered %d; the "
             "pragma reads %lld\n",
       rc, busy_timeout_of(db));
  static const char *values[] = {"-5",  "0",     "2147483647", "2147483648",
                                 "1.9", "'250'", "' 250'",     "abc",
                                 "0x10", "1e3",  NULL};
  for (int i = 0; values[i]; i++) {
    char sql[128], label[160];
    must(db, "PRAGMA busy_timeout = 777");
    snprintf(sql, sizeof sql, "PRAGMA busy_timeout = %s", values[i]);
    snprintf(label, sizeof label, "  from 777, %s", sql);
    pragma_row(label, db, sql);
    bput(&out, "    then the pragma reads %lld\n", busy_timeout_of(db));
  }
  must(db, "PRAGMA busy_timeout = 777");
  sqlite3 *second = open1("b1.db");
  bput(&out, "  set to 777 by pragma; a second connection to the same file reads %lld\n",
       busy_timeout_of(second));
  close_db(second);
  close_db(db);
  db = open1("b1.db");
  bput(&out, "  the first closed and reopened reads %lld\n", busy_timeout_of(db));
  close_db(db);
  flush_out();
}

/* ---- B2: no timeout; a second writer while the first holds the lock --- */

static void b2(int wal) {
  struct counter c = {0};
  const char *file = wal ? "b2-wal.db" : "b2-delete.db";
  bput(&out, "B2 %s: no busy timeout; c1 holds BEGIN IMMEDIATE\n",
       wal ? "WAL" : "rollback journal");
  sqlite3 *c1 = open1(file);
  make_t(c1, wal);
  sqlite3 *c2 = open1(file);
  bput(&out, "  c2 reads %lld rows first\n", qint(c2, "SELECT count(*) FROM t"));
  show("  c1 BEGIN IMMEDIATE", run_sql(c1, "BEGIN IMMEDIATE"));
  show("  c1 INSERT", run_sql(c1, "INSERT INTO t VALUES(4)"));
  show("  c2 BEGIN IMMEDIATE", run_sql(c2, "BEGIN IMMEDIATE"));
  state("    c2 then", c2);
  show("  c2 BEGIN EXCLUSIVE", run_sql(c2, "BEGIN EXCLUSIVE"));
  show("  c2 autocommit INSERT", run_sql(c2, "INSERT INTO t VALUES(9)"));
  state("    c2 then", c2);
  show("  c2 BEGIN (deferred)", run_sql(c2, "BEGIN"));
  bput(&out, "  c2 SELECT count(*): %lld\n", qint(c2, "SELECT count(*) FROM t"));
  state("    c2 then", c2);
  show("  c2 INSERT, its first write", run_sql(c2, "INSERT INTO t VALUES(9)"));
  state("    c2 then", c2);
  show("  c2 COMMIT", run_sql(c2, "COMMIT"));
  state("    c2 then", c2);
  sqlite3_busy_handler(c2, counting_handler, &c);
  bput(&out, "  with the counting handler on c2:\n");
  show_counted("  c2 BEGIN IMMEDIATE", c2, "BEGIN IMMEDIATE", &c);
  show_counted("  c2 autocommit INSERT", c2, "INSERT INTO t VALUES(9)", &c);
  show_counted("  c2 BEGIN", c2, "BEGIN", &c);
  show_counted("  c2 SELECT count(*)", c2, "SELECT count(*) FROM t", &c);
  show_counted("  c2 INSERT, its first write, its read transaction open", c2,
               "INSERT INTO t VALUES(9)", &c);
  state("    c2 then", c2);
  show_counted("  c2 COMMIT", c2, "COMMIT", &c);
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  bput(&out, "  then c2 reads %lld rows\n", qint(c2, "SELECT count(*) FROM t"));
  close_db(c2);
  close_db(c1);
  flush_out();
}

/* ---- B3: timings of busy waits ---------------------------------------- */

/* The floor's sqliteDefaultBusyCallback schedule (sqlite3.c, 3.45.1), for
 * a build where it sleeps in milliseconds: the number of sleeps it makes
 * and their total, before it gives up, under a lock never released. */
static void floor_schedule(int tmout, int *sleeps, int *total) {
  static const int delays[] = {1, 2, 5, 10, 15, 20, 25, 25, 25, 50, 50, 100};
  static const int totals[] = {0, 1, 3, 8, 18, 33, 53, 78, 103, 128, 178, 228};
  const int nd = 12;
  *sleeps = 0;
  *total = 0;
  for (int count = 0;; count++) {
    int delay, prior;
    if (count < nd) {
      delay = delays[count];
      prior = totals[count];
    } else {
      delay = delays[nd - 1];
      prior = totals[nd - 1] + delay * (count - (nd - 1));
    }
    if (prior + delay > tmout) {
      delay = tmout - prior;
      if (delay <= 0) return;
    }
    (*sleeps)++;
    *total += delay;
  }
}

/* The same callback built with HAVE_NANOSLEEP=0: whole seconds. */
static void floor_schedule_seconds(int tmout, int *sleeps, int *total) {
  *sleeps = 0;
  *total = 0;
  for (int count = 0; (count + 1) * 1000 <= tmout; count++) {
    (*sleeps)++;
    *total += 1000;
  }
}

static void put_schedules(int t) {
  int s, tot, s2, tot2;
  floor_schedule(t, &s, &tot);
  floor_schedule_seconds(t, &s2, &tot2);
  fprintf(timing,
          "  predicted by the floor's source: %d sleeps totalling %d ms; "
          "with HAVE_NANOSLEEP=0, %d sleeps totalling %d ms\n",
          s, tot, s2, tot2);
}

enum how { BY_C_API, BY_PRAGMA };

/* c1 holds BEGIN IMMEDIATE throughout; c2 tries BEGIN IMMEDIATE RUNS
 * times under timeout t, set by the C API or by the pragma. */
static void b3_begin(int wal, int t, enum how how) {
  char file[64], label[200];
  double v[RUNS];
  int all = 1, first = -1;
  snprintf(file, sizeof file, "b3-%d-%d-%d.db", wal, t, (int)how);
  sqlite3 *c1 = open1(file);
  make_t(c1, wal);
  out.n = 0; out.s[0] = 0; /* the journal_mode line is printed in B2 */
  sqlite3 *c2 = open1(file);
  (void)qint(c2, "SELECT count(*) FROM t");
  if (how == BY_C_API) {
    sqlite3_busy_timeout(c2, t);
  } else {
    char sql[64];
    snprintf(sql, sizeof sql, "PRAGMA busy_timeout = %d", t);
    must(c2, sql);
  }
  must(c1, "BEGIN IMMEDIATE");
  sqlite3_stmt *st = prep(c2, "BEGIN IMMEDIATE");
  for (int i = 0; i < RUNS; i++) {
    double t0 = now_ms();
    int rc = sqlite3_step(st);
    v[i] = now_ms() - t0;
    sqlite3_reset(st);
    if (first < 0) first = rc;
    if (rc != first) all = 0;
  }
  sqlite3_finalize(st);
  must(c1, "COMMIT");
  close_db(c2);
  close_db(c1);
  bput(&out, "B3 %s, timeout %d ms by %s: BEGIN IMMEDIATE under the other's "
             "BEGIN IMMEDIATE answered %d %s in %s of %d runs\n",
       wal ? "WAL" : "rollback journal", t,
       how == BY_C_API ? "sqlite3_busy_timeout" : "PRAGMA busy_timeout", first,
       name_of(first), all ? "all" : "NOT all", RUNS);
  flush_out();
  snprintf(label, sizeof label,
           "B3 %s, timeout %d ms by %s: blocked BEGIN IMMEDIATE, ms to BUSY",
           wal ? "WAL" : "rollback journal", t,
           how == BY_C_API ? "sqlite3_busy_timeout" : "PRAGMA busy_timeout");
  dist(label, v, RUNS, "ms");
  put_schedules(t);
}

/* A4: an autocommit INSERT under another connection's read commits inside
 * its step, so the step waits in the busy timeout (ADR-0011 expected it,
 * unmeasured). Rows before and after each attempt are read too. */
static void b3_insert_under_reader(int t) {
  char label[200];
  double v[RUNS];
  int all = 1, first = -1;
  long long before = 0, after = 0;
  sqlite3 *c1 = open1("b3-insert.db");
  make_t(c1, 0);
  sqlite3 *c2 = open1("b3-insert.db");
  sqlite3_stmt *r = prep(c2, "SELECT x FROM t");
  if (sqlite3_step(r) != SQLITE_ROW) fatal("reader", c2, 0);
  sqlite3_busy_timeout(c1, t);
  before = qint(c1, "SELECT count(*) FROM t");
  for (int i = 0; i < RUNS; i++) {
    double t0 = now_ms();
    struct ans a = run_sql(c1, "INSERT INTO t VALUES(7)");
    v[i] = now_ms() - t0;
    if (first < 0) first = a.rc;
    if (a.rc != first) all = 0;
  }
  after = qint(c1, "SELECT count(*) FROM t");
  int ac = sqlite3_get_autocommit(c1);
  sqlite3_finalize(r);
  close_db(c2);
  close_db(c1);
  bput(&out, "B3 rollback journal, timeout %d ms: an autocommit INSERT under "
             "another connection's read answered %d %s in %s of %d runs; rows "
             "%lld before, %lld after; autocommit %d\n",
       t, first, name_of(first), all ? "all" : "NOT all", RUNS, before, after, ac);
  flush_out();
  snprintf(label, sizeof label,
           "B3 rollback journal, timeout %d ms: autocommit INSERT under a "
           "reader, ms to BUSY",
           t);
  dist(label, v, RUNS, "ms");
  put_schedules(t);
}

/* ---- B4: WAL, a reader and a writer ------------------------------------ */

static void b4(void) {
  bput(&out, "B4: WAL, no busy timeout\n");
  sqlite3 *c1 = open1("b4.db");
  make_t(c1, 1);
  sqlite3 *c2 = open1("b4.db");
  bput(&out, " a reader during a writer's open transaction:\n");
  show("  c1 BEGIN", run_sql(c1, "BEGIN"));
  show("  c1 INSERT", run_sql(c1, "INSERT INTO t VALUES(4)"));
  {
    sqlite3_stmt *st = prep(c2, "SELECT count(*) FROM t");
    int rc = sqlite3_step(st);
    bput(&out, "  c2 SELECT count(*): %d %s, count %lld\n", rc, name_of(rc),
         sqlite3_column_int64(st, 0));
    sqlite3_finalize(st);
  }
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  bput(&out, "  then c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  bput(&out, " a writer during a reader's open transaction:\n");
  show("  c2 BEGIN", run_sql(c2, "BEGIN"));
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  state("    c2 then", c2);
  show("  c1 autocommit INSERT", run_sql(c1, "INSERT INTO t VALUES(5)"));
  show("  c1 BEGIN IMMEDIATE", run_sql(c1, "BEGIN IMMEDIATE"));
  show("  c1 INSERT", run_sql(c1, "INSERT INTO t VALUES(6)"));
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  bput(&out, "  c2, in its transaction, counts %lld\n",
       qint(c2, "SELECT count(*) FROM t"));
  show("  c2 COMMIT", run_sql(c2, "COMMIT"));
  bput(&out, "  then c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  bput(&out, " a writer while a reader's statement holds a row, no "
             "transaction:\n");
  {
    sqlite3_stmt *st = prep(c2, "SELECT x FROM t");
    int rc = sqlite3_step(st);
    bput(&out, "  c2's reader stepped: %d %s\n", rc, name_of(rc));
    show("  c1 autocommit INSERT", run_sql(c1, "INSERT INTO t VALUES(7)"));
    sqlite3_finalize(st);
  }
  bput(&out, " the contrast, rollback journal: a reader during a writer's open "
             "transaction:\n");
  sqlite3 *d1 = open1("b4-delete.db");
  make_t(d1, 0);
  sqlite3 *d2 = open1("b4-delete.db");
  show("  d1 BEGIN", run_sql(d1, "BEGIN"));
  show("  d1 INSERT", run_sql(d1, "INSERT INTO t VALUES(4)"));
  {
    sqlite3_stmt *st = prep(d2, "SELECT count(*) FROM t");
    int rc = sqlite3_step(st);
    bput(&out, "  d2 SELECT count(*): %d %s, count %lld\n", rc, name_of(rc),
         sqlite3_column_int64(st, 0));
    sqlite3_finalize(st);
  }
  show("  d1 COMMIT", run_sql(d1, "COMMIT"));
  close_db(d2);
  close_db(d1);
  close_db(c2);
  close_db(c1);
  flush_out();
}

/* ---- B5 and B6: WAL, a deferred transaction's upgrade, and IMMEDIATE ---- */

static void b5(void) {
  struct counter c = {0}, c1c = {0};
  bput(&out, "B5: WAL; c2 BEGIN (deferred), reads, then writes after c1 "
             "committed a write; counting handler on c2\n");
  sqlite3 *c1 = open1("b5.db");
  make_t(c1, 1);
  sqlite3 *c2 = open1("b5.db");
  sqlite3_busy_handler(c2, counting_handler, &c);
  show("  c2 BEGIN", run_sql(c2, "BEGIN"));
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  show("  c1 autocommit INSERT", run_sql(c1, "INSERT INTO t VALUES(4)"));
  show_counted("  c2 INSERT", c2, "INSERT INTO t VALUES(5)", &c);
  state("    c2 then", c2);
  bput(&out, "  c2, still in its transaction, counts %lld\n",
       qint(c2, "SELECT count(*) FROM t"));
  show_counted("  c2 INSERT again", c2, "INSERT INTO t VALUES(5)", &c);
  show("  c2 COMMIT", run_sql(c2, "COMMIT"));
  show("  c2 BEGIN", run_sql(c2, "BEGIN"));
  show_counted("  c2 INSERT in a new transaction", c2, "INSERT INTO t VALUES(5)",
               &c);
  show("  c2 COMMIT", run_sql(c2, "COMMIT"));
  bput(&out, "  then c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  int rc = sqlite3_busy_timeout(c2, 1500);
  bput(&out, "  sqlite3_busy_timeout(c2, 1500) restores it: answered %d; the "
             "pragma reads %lld\n",
       rc, busy_timeout_of(c2));
  bput(&out, " the same, but c1 still holds its write transaction when c2 "
             "writes; counting handler on c2 again\n");
  sqlite3_busy_handler(c2, counting_handler, &c);
  show("  c2 BEGIN", run_sql(c2, "BEGIN"));
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  show("  c1 BEGIN IMMEDIATE", run_sql(c1, "BEGIN IMMEDIATE"));
  show("  c1 INSERT", run_sql(c1, "INSERT INTO t VALUES(6)"));
  show_counted("  c2 INSERT while c1's write is open", c2,
               "INSERT INTO t VALUES(7)", &c);
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  show_counted("  c2 INSERT after c1 committed", c2, "INSERT INTO t VALUES(7)",
               &c);
  state("    c2 then", c2);
  show("  c2 ROLLBACK", run_sql(c2, "ROLLBACK"));
  bput(&out, " B6: the same race with BEGIN IMMEDIATE; counting handlers on "
             "both\n");
  sqlite3_busy_handler(c1, counting_handler, &c1c);
  show_counted("  c2 BEGIN IMMEDIATE", c2, "BEGIN IMMEDIATE", &c);
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  show_counted("  c1 autocommit INSERT", c1, "INSERT INTO t VALUES(8)", &c1c);
  show_counted("  c2 INSERT", c2, "INSERT INTO t VALUES(9)", &c);
  show_counted("  c2 COMMIT", c2, "COMMIT", &c);
  show_counted("  c1 autocommit INSERT, retried", c1, "INSERT INTO t VALUES(8)",
               &c1c);
  bput(&out, "  c1 committed first, then:\n");
  show_counted("  c2 BEGIN IMMEDIATE", c2, "BEGIN IMMEDIATE", &c);
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  show_counted("  c2 INSERT", c2, "INSERT INTO t VALUES(10)", &c);
  show_counted("  c2 COMMIT", c2, "COMMIT", &c);
  bput(&out, "  c1 holds an open write transaction, then:\n");
  show("  c1 BEGIN IMMEDIATE", run_sql(c1, "BEGIN IMMEDIATE"));
  show_counted("  c2 BEGIN IMMEDIATE", c2, "BEGIN IMMEDIATE", &c);
  state("    c2 then", c2);
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  bput(&out, "  then c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  close_db(c2);
  close_db(c1);
  bput(&out, " the contrast, rollback journal: c2 BEGIN, reads; c1 writes; "
             "counting handlers on both\n");
  c1 = open1("b5-delete.db");
  make_t(c1, 0);
  c2 = open1("b5-delete.db");
  sqlite3_busy_handler(c1, counting_handler, &c1c);
  sqlite3_busy_handler(c2, counting_handler, &c);
  show("  c2 BEGIN", run_sql(c2, "BEGIN"));
  bput(&out, "  c2 counts %lld\n", qint(c2, "SELECT count(*) FROM t"));
  show_counted("  c1 autocommit INSERT", c1, "INSERT INTO t VALUES(4)", &c1c);
  bput(&out, "  c1 then counts %lld\n", qint(c1, "SELECT count(*) FROM t"));
  show_counted("  c2 INSERT", c2, "INSERT INTO t VALUES(5)", &c);
  show_counted("  c2 COMMIT", c2, "COMMIT", &c);
  bput(&out, "  then c1 counts %lld\n", qint(c1, "SELECT count(*) FROM t"));
  close_db(c2);
  close_db(c1);
  flush_out();
}

/* The upgrade's timing under a real busy timeout: does it wait at all? */
static void b5_timing(void) {
  double v[RUNS], w[RUNS];
  int first = -1, all = 1, first2 = -1, all2 = 1;
  sqlite3 *c1 = open1("b5t.db");
  make_t(c1, 1);
  out.n = 0; out.s[0] = 0;
  sqlite3 *c2 = open1("b5t.db");
  sqlite3_busy_timeout(c2, 1500);
  for (int i = 0; i < RUNS; i++) {
    must(c2, "BEGIN");
    (void)qint(c2, "SELECT count(*) FROM t");
    must(c1, "INSERT INTO t VALUES(4)");
    double t0 = now_ms();
    struct ans a = run_sql(c2, "INSERT INTO t VALUES(5)");
    v[i] = now_ms() - t0;
    if (first < 0) first = a.ext;
    if (a.ext != first) all = 0;
    must(c2, "ROLLBACK");
  }
  for (int i = 0; i < RUNS; i++) {
    must(c2, "BEGIN");
    (void)qint(c2, "SELECT count(*) FROM t");
    must(c1, "BEGIN IMMEDIATE");
    double t0 = now_ms();
    struct ans a = run_sql(c2, "INSERT INTO t VALUES(5)");
    w[i] = now_ms() - t0;
    if (first2 < 0) first2 = a.ext;
    if (a.ext != first2) all2 = 0;
    must(c1, "COMMIT");
    must(c2, "ROLLBACK");
  }
  close_db(c2);
  close_db(c1);
  bput(&out, "B5 timing, WAL, busy timeout 1500 ms: a deferred transaction's "
             "first write after another's commit answered extended %d %s in %s "
             "of %d runs; while the other's write is open, %d %s in %s of %d\n",
       first, name_of(first), all ? "all" : "NOT all", RUNS, first2,
       name_of(first2), all2 ? "all" : "NOT all", RUNS);
  flush_out();
  dist("B5 WAL, timeout 1500: deferred upgrade after another's commit, ms", v,
       RUNS, "ms");
  dist("B5 WAL, timeout 1500: deferred upgrade while another's write is open, ms",
       w, RUNS, "ms");
}

/* ---- B7: rollback journal, a reader holding SHARED during a COMMIT ---- */

static void b7(void) {
  struct counter c = {0};
  bput(&out, "B7: rollback journal; c2's statement holds a row (a SHARED "
             "lock); c1 commits; no busy timeout\n");
  sqlite3 *c1 = open1("b7.db");
  make_t(c1, 0);
  sqlite3 *c2 = open1("b7.db");
  sqlite3 *c3 = open1("b7.db");
  bput(&out, "  c3 opened and read %lld rows\n", qint(c3, "SELECT count(*) FROM t"));
  sqlite3_stmt *r = prep(c2, "SELECT x FROM t");
  int rc = sqlite3_step(r);
  bput(&out, "  c2's reader stepped: %d %s\n", rc, name_of(rc));
  show("  c1 BEGIN", run_sql(c1, "BEGIN"));
  show("  c1 INSERT", run_sql(c1, "INSERT INTO t VALUES(4)"));
  show("  c1 COMMIT", run_sql(c1, "COMMIT"));
  state("    c1 then", c1);
  {
    struct ans a = run_sql(c3, "SELECT count(*) FROM t");
    show("  c3, which had read before, SELECT count(*)", a);
  }
  sqlite3 *c4 = open1("b7.db");
  {
    struct ans a = run_sql(c4, "SELECT count(*) FROM t");
    show("  c4, a new connection, SELECT count(*)", a);
  }
  close_db(c4);
  rc = sqlite3_step(r);
  bput(&out, "  c2's reader steps again: %d %s\n", rc, name_of(rc));
  sqlite3_busy_handler(c1, counting_handler, &c);
  show_counted("  c1 COMMIT again, counting handler on c1", c1, "COMMIT", &c);
  state("    c1 then", c1);
  sqlite3_finalize(r);
  bput(&out, "  c2's reader finalized\n");
  show_counted("  c1 COMMIT again", c1, "COMMIT", &c);
  state("    c1 then", c1);
  bput(&out, "  c3 then counts %lld\n", qint(c3, "SELECT count(*) FROM t"));
  bput(&out, " an autocommit INSERT under c2's read:\n");
  r = prep(c2, "SELECT x FROM t");
  rc = sqlite3_step(r);
  bput(&out, "  c2's reader stepped: %d %s\n", rc, name_of(rc));
  show_counted("  c1 autocommit INSERT", c1, "INSERT INTO t VALUES(5)", &c);
  state("    c1 then", c1);
  sqlite3_finalize(r);
  bput(&out, "  c2's reader finalized; c1 counts %lld\n",
       qint(c1, "SELECT count(*) FROM t"));
  close_db(c3);
  close_db(c2);
  close_db(c1);
  flush_out();
}

static void b7_timing(int t) {
  char label[200];
  double v[RUNS];
  int first = -1, all = 1;
  sqlite3 *c1 = open1("b7t.db");
  make_t(c1, 0);
  sqlite3 *c2 = open1("b7t.db");
  sqlite3_stmt *r = prep(c2, "SELECT x FROM t");
  if (sqlite3_step(r) != SQLITE_ROW) fatal("reader", c2, 0);
  sqlite3_busy_timeout(c1, t);
  for (int i = 0; i < RUNS; i++) {
    must(c1, "BEGIN");
    must(c1, "INSERT INTO t VALUES(4)");
    double t0 = now_ms();
    struct ans a = run_sql(c1, "COMMIT");
    v[i] = now_ms() - t0;
    if (first < 0) first = a.rc;
    if (a.rc != first) all = 0;
    must(c1, "ROLLBACK");
  }
  sqlite3_finalize(r);
  close_db(c2);
  close_db(c1);
  bput(&out, "B7 timing, rollback journal, timeout %d ms: COMMIT under a "
             "reader answered %d %s in %s of %d runs\n",
       t, first, name_of(first), all ? "all" : "NOT all", RUNS);
  flush_out();
  snprintf(label, sizeof label,
           "B7 rollback journal, timeout %d ms: COMMIT under a reader, ms to BUSY", t);
  dist(label, v, RUNS, "ms");
  put_schedules(t);
}

/* ---- B8: journal_mode=wal on a file ----------------------------------- */

static void b8(void) {
  bput(&out, "B8: PRAGMA journal_mode on a file\n");
  sqlite3 *c1 = open1("b8a.db");
  make_t(c1, 0);
  sqlite3 *c2 = open1("b8a.db");
  bput(&out, "  c2 opened and read %lld rows; it stays open, idle\n",
       qint(c2, "SELECT count(*) FROM t"));
  pragma_row("  c1 PRAGMA journal_mode", c1, "PRAGMA journal_mode");
  pragma_row("  c1 PRAGMA journal_mode=wal", c1, "PRAGMA journal_mode=wal");
  pragma_row("  c2 PRAGMA journal_mode", c2, "PRAGMA journal_mode");
  bput(&out, "  c2 then reads %lld rows\n", qint(c2, "SELECT count(*) FROM t"));
  pragma_row("  c2 PRAGMA journal_mode again", c2, "PRAGMA journal_mode");
  sqlite3 *c3 = open1("b8a.db");
  pragma_row("  c3, opened after, PRAGMA journal_mode", c3, "PRAGMA journal_mode");
  close_db(c3);
  close_db(c2);
  close_db(c1);
  c1 = open1("b8a.db");
  pragma_row("  all closed, then a new connection's PRAGMA journal_mode", c1,
             "PRAGMA journal_mode");
  close_db(c1);

  bput(&out, " inside an open transaction, on a rollback-journal file:\n");
  c1 = open1("b8b.db");
  make_t(c1, 0);
  show("  BEGIN", run_sql(c1, "BEGIN"));
  pragma_row("  PRAGMA journal_mode=wal", c1, "PRAGMA journal_mode=wal");
  state("    then", c1);
  pragma_row("  PRAGMA journal_mode", c1, "PRAGMA journal_mode");
  show("  ROLLBACK", run_sql(c1, "ROLLBACK"));
  show("  BEGIN", run_sql(c1, "BEGIN"));
  bput(&out, "  it reads %lld rows\n", qint(c1, "SELECT count(*) FROM t"));
  pragma_row("  PRAGMA journal_mode=wal", c1, "PRAGMA journal_mode=wal");
  state("    then", c1);
  show("  ROLLBACK", run_sql(c1, "ROLLBACK"));
  show("  BEGIN", run_sql(c1, "BEGIN"));
  pragma_row("  PRAGMA journal_mode=truncate", c1, "PRAGMA journal_mode=truncate");
  show("  ROLLBACK", run_sql(c1, "ROLLBACK"));
  pragma_row("  then PRAGMA journal_mode", c1, "PRAGMA journal_mode");
  pragma_row("  PRAGMA journal_mode=wal, outside a transaction", c1,
             "PRAGMA journal_mode=wal");
  show("  BEGIN", run_sql(c1, "BEGIN"));
  pragma_row("  on WAL now, PRAGMA journal_mode=delete", c1,
             "PRAGMA journal_mode=delete");
  state("    then", c1);
  show("  ROLLBACK", run_sql(c1, "ROLLBACK"));
  close_db(c1);

  bput(&out, " rollback journal, another connection's statement holds a row:\n");
  c1 = open1("b8c.db");
  make_t(c1, 0);
  c2 = open1("b8c.db");
  sqlite3_stmt *r = prep(c2, "SELECT x FROM t");
  int rc = sqlite3_step(r);
  bput(&out, "  c2's reader stepped: %d %s\n", rc, name_of(rc));
  pragma_row("  c1 PRAGMA journal_mode=wal", c1, "PRAGMA journal_mode=wal");
  pragma_row("  c1 then PRAGMA journal_mode", c1, "PRAGMA journal_mode");
  sqlite3_finalize(r);
  bput(&out, "  c2's reader finalized\n");
  pragma_row("  c1 PRAGMA journal_mode=wal", c1, "PRAGMA journal_mode=wal");
  bput(&out, " WAL, back to delete while another connection is open and idle:\n");
  bput(&out, "  c2 reads %lld rows\n", qint(c2, "SELECT count(*) FROM t"));
  pragma_row("  c1 PRAGMA journal_mode=delete", c1, "PRAGMA journal_mode=delete");
  pragma_row("  c1 then PRAGMA journal_mode", c1, "PRAGMA journal_mode");
  close_db(c2);
  bput(&out, "  c2 closed\n");
  pragma_row("  c1 PRAGMA journal_mode=delete", c1, "PRAGMA journal_mode=delete");
  close_db(c1);
  flush_out();
}

/* ---- B9: SQLITE_LOCKED against SQLITE_BUSY ---------------------------- */

static void b9(void) {
  struct counter c = {0};
  bput(&out, "B9: one connection's own conflict; counting handler on c1\n");
  sqlite3 *c1 = open1("b9.db");
  make_t(c1, 0);
  must(c1, "CREATE TABLE u(x)");
  sqlite3_busy_handler(c1, counting_handler, &c);
  sqlite3_stmt *r = prep(c1, "SELECT x FROM t");
  int rc = sqlite3_step(r);
  bput(&out, "  c1's reader on t stepped: %d %s\n", rc, name_of(rc));
  show_counted("  c1 DROP TABLE t", c1, "DROP TABLE t", &c);
  show_counted("  c1 DROP TABLE u", c1, "DROP TABLE u", &c);
  show_counted("  c1 CREATE TABLE v(x)", c1, "CREATE TABLE v(x)", &c);
  show_counted("  c1 INSERT INTO t", c1, "INSERT INTO t VALUES(4)", &c);
  state("    c1 then", c1);
  sqlite3_finalize(r);
  bput(&out, "  the reader finalized\n");
  show_counted("  c1 DROP TABLE u", c1, "DROP TABLE u", &c);
  bput(&out, " the same DROP against another connection's read:\n");
  sqlite3 *c2 = open1("b9.db");
  r = prep(c2, "SELECT x FROM t");
  rc = sqlite3_step(r);
  bput(&out, "  c2's reader on t stepped: %d %s\n", rc, name_of(rc));
  show_counted("  c1 DROP TABLE t", c1, "DROP TABLE t", &c);
  sqlite3_finalize(r);
  close_db(c2);
  close_db(c1);
  flush_out();
}

static void b9_timing(void) {
  double v[RUNS];
  int first = -1, all = 1;
  sqlite3 *c1 = open1("b9t.db");
  make_t(c1, 0);
  sqlite3_busy_timeout(c1, 1500);
  sqlite3_stmt *r = prep(c1, "SELECT x FROM t");
  if (sqlite3_step(r) != SQLITE_ROW) fatal("reader", c1, 0);
  for (int i = 0; i < RUNS; i++) {
    double t0 = now_ms();
    struct ans a = run_sql(c1, "DROP TABLE t");
    v[i] = now_ms() - t0;
    if (first < 0) first = a.rc;
    if (a.rc != first) all = 0;
  }
  sqlite3_finalize(r);
  close_db(c1);
  bput(&out, "B9 timing, busy timeout 1500 ms: DROP TABLE t under its own "
             "reader answered %d %s in %s of %d runs\n",
       first, name_of(first), all ? "all" : "NOT all", RUNS);
  flush_out();
  dist("B9 timeout 1500: DROP TABLE under the connection's own reader, ms", v,
       RUNS, "ms");
}

/* ---- B10: a fresh connection's first statements under another's lock -- */

/* Each SQL is prepared and stepped on a connection opened for it, which has
 * read nothing, while another connection holds a lock: what the settings
 * list would meet at open. No busy timeout. */
static void b10_one(const char *file, const char *sql) {
  sqlite3 *db = open1(file);
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  bput(&out, "    %s: prepare %d %s", sql, rc, name_of(rc));
  if (rc != SQLITE_OK) {
    int ext = sqlite3_extended_errcode(db);
    bput(&out, ", extended %d %s", ext, name_of(ext));
  }
  if (st) {
    rc = sqlite3_step(st);
    bput(&out, ", step %d %s", rc, name_of(rc));
    if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
      int ext = sqlite3_extended_errcode(db);
      bput(&out, ", extended %d %s", ext, name_of(ext));
    }
    if (rc == SQLITE_ROW) {
      const unsigned char *t = sqlite3_column_text(st, 0);
      bput(&out, " \"%s\"", t ? (const char *)t : "(NULL)");
    }
    sqlite3_finalize(st);
  }
  bput(&out, "\n");
  close_db(db);
}

static void b10(void) {
  static const char *sqls[] = {"SELECT 1",
                               "PRAGMA busy_timeout = 100",
                               "PRAGMA foreign_keys = 1",
                               "PRAGMA foreign_keys",
                               "PRAGMA journal_mode",
                               "PRAGMA journal_mode=wal",
                               "PRAGMA synchronous",
                               "SELECT count(*) FROM t",
                               NULL};
  static const char *locks[] = {"BEGIN EXCLUSIVE and a write",
                                "BEGIN IMMEDIATE and a write",
                                "a statement holding a row", NULL};
  bput(&out, "B10: rollback journal; a fresh connection's first statements "
             "while another connection holds a lock; no busy timeout\n");
  for (int k = 0; locks[k]; k++) {
    char file[64];
    snprintf(file, sizeof file, "b10-%d.db", k);
    sqlite3 *other = open1(file);
    make_t(other, 0);
    sqlite3_stmt *r = NULL;
    if (k == 0) {
      must(other, "BEGIN EXCLUSIVE");
      must(other, "INSERT INTO t VALUES(4)");
    } else if (k == 1) {
      must(other, "BEGIN IMMEDIATE");
      must(other, "INSERT INTO t VALUES(4)");
    } else {
      r = prep(other, "SELECT x FROM t");
      if (sqlite3_step(r) != SQLITE_ROW) fatal("reader", other, 0);
    }
    bput(&out, "  the other holds %s:\n", locks[k]);
    for (int i = 0; sqls[i]; i++) b10_one(file, sqls[i]);
    if (r) sqlite3_finalize(r);
    else must(other, "COMMIT");
    close_db(other);
  }
  flush_out();
}

/* ---- B11: COMMIT while the connection's own statement is unfinished --- */

static void b11(void) {
  bput(&out, "B11: one connection, no other; COMMIT while its own INSERT ... "
             "RETURNING is stepped once and not finished\n");
  sqlite3 *c1 = open1("b11.db");
  make_t(c1, 0);
  show("  BEGIN", run_sql(c1, "BEGIN"));
  sqlite3_stmt *r = prep(c1, "INSERT INTO t VALUES(4) RETURNING x");
  int rc = sqlite3_step(r);
  bput(&out, "  the INSERT ... RETURNING stepped: %d %s\n", rc, name_of(rc));
  show("  COMMIT", run_sql(c1, "COMMIT"));
  state("    then", c1);
  sqlite3_finalize(r);
  bput(&out, "  the INSERT ... RETURNING finalized\n");
  show("  COMMIT again", run_sql(c1, "COMMIT"));
  state("    then", c1);
  bput(&out, "  rows: %lld\n", qint(c1, "SELECT count(*) FROM t"));
  close_db(c1);
  flush_out();
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: busy SCRATCH-DIR TIMING-FILE\n");
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
  watch("B1", 30);
  b1();
  watch("B2 delete", 30);
  b2(0);
  watch("B2 wal", 30);
  b2(1);
  static const int timeouts[] = {0, 1, 10, 50, 250, 1500};
  for (int i = 0; i < 6; i++) {
    watch("B3 begin", 120);
    b3_begin(0, timeouts[i], BY_C_API);
  }
  watch("B3 pragma", 60);
  b3_begin(0, 250, BY_PRAGMA);
  watch("B3 wal", 60);
  b3_begin(1, 250, BY_C_API);
  watch("B3 insert", 120);
  b3_insert_under_reader(1500);
  watch("B4", 30);
  b4();
  watch("B5", 30);
  b5();
  watch("B5 timing", 60);
  b5_timing();
  watch("B7", 30);
  b7();
  watch("B7 timing", 60);
  b7_timing(250);
  watch("B8", 30);
  b8();
  watch("B9", 30);
  b9();
  watch("B10", 30);
  b10();
  watch("B11", 30);
  b11();
  watch("B9 timing", 60);
  b9_timing();
  alarm(0);
  printf("end\n");
  return 0;
}
