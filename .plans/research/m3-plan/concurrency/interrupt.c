/* interrupt.c: A1, sqlite3_interrupt called from a second thread.
 *
 *   interrupt SCRATCH-DIR TIMING-FILE
 *
 * Facts go to stdout, and must match byte for byte across runs; timings go
 * to TIMING-FILE. Each timed case runs RUNS times on fresh connections: its
 * facts are printed from run 1, then how many runs gave the same facts.
 *
 * Every connection opens as chez-sqlite3 opens one: READWRITE | CREATE |
 * EXRESCODE, with FULLMUTEX unless the case says NOMUTEX (ADR-0010).
 *
 * Rules kept: no interrupt reaches a connection that is closed or closing
 * (each interrupter thread is joined before its connection closes); no
 * statement is used after its finalize; every wait is bounded, and a
 * watchdog alarm ends the probe, saying so, if a section hangs.
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

/* ---- the second thread ------------------------------------------------ */

/* Waits (bounded) for go, sleeps delay_ms, then makes its call: an
 * interrupt, reading sqlite3_is_interrupted just before and after; or
 * sqlite3_errmsg, timing it. Always ends within 10 s plus its delay. */
enum op { OP_INTERRUPT, OP_ERRMSG };

struct peer {
  sqlite3 *db;
  enum op op;
  int delay_ms;
  pthread_t th;
  pthread_mutex_t m;
  pthread_cond_t c;
  int go, done, fired, gave_up;
  int running; /* the main thread's call had not returned when it fired */
  int before, after;
  double t_call, t_return;
};

static void *peer_main(void *p) {
  struct peer *s = p;
  struct timespec d;
  deadline_in(&d, 10000);
  pthread_mutex_lock(&s->m);
  while (!s->go) {
    if (pthread_cond_timedwait(&s->c, &s->m, &d) == ETIMEDOUT) {
      s->gave_up = 1;
      pthread_cond_broadcast(&s->c);
      pthread_mutex_unlock(&s->m);
      return NULL;
    }
  }
  pthread_mutex_unlock(&s->m);
  sleep_ms(s->delay_ms);
  pthread_mutex_lock(&s->m);
  s->running = !s->done;
  pthread_mutex_unlock(&s->m);
  if (s->op == OP_INTERRUPT) {
    s->before = sqlite3_is_interrupted(s->db);
    s->t_call = now_ms();
    sqlite3_interrupt(s->db);
    s->t_return = now_ms();
    s->after = sqlite3_is_interrupted(s->db);
  } else {
    s->t_call = now_ms();
    (void)sqlite3_errmsg(s->db);
    s->t_return = now_ms();
  }
  pthread_mutex_lock(&s->m);
  s->fired = 1;
  pthread_cond_broadcast(&s->c);
  pthread_mutex_unlock(&s->m);
  return NULL;
}

static void peer_start(struct peer *s, sqlite3 *db, enum op op, int delay) {
  memset(s, 0, sizeof *s);
  s->db = db;
  s->op = op;
  s->delay_ms = delay;
  pthread_mutex_init(&s->m, NULL);
  pthread_cond_init(&s->c, NULL);
  if (pthread_create(&s->th, NULL, peer_main, s) != 0) {
    printf("FATAL: pthread_create\n");
    exit(1);
  }
}

static void peer_go(struct peer *s) {
  pthread_mutex_lock(&s->m);
  s->go = 1;
  pthread_cond_broadcast(&s->c);
  pthread_mutex_unlock(&s->m);
}

static void peer_done(struct peer *s) {
  pthread_mutex_lock(&s->m);
  s->done = 1;
  pthread_mutex_unlock(&s->m);
}

/* Waits up to ms for the peer to have made its call; answers 1 if it did. */
static int peer_wait(struct peer *s, int ms) {
  struct timespec d;
  int ok;
  deadline_in(&d, ms);
  pthread_mutex_lock(&s->m);
  while (!s->fired && !s->gave_up)
    if (pthread_cond_timedwait(&s->c, &s->m, &d) == ETIMEDOUT) break;
  ok = s->fired;
  pthread_mutex_unlock(&s->m);
  return ok;
}

/* Joins the peer: always before its connection closes. */
static void peer_join(struct peer *s) {
  pthread_join(s->th, NULL);
  pthread_mutex_destroy(&s->m);
  pthread_cond_destroy(&s->c);
}

/* An interrupt from another thread while nothing runs on the connection. */
static void idle_interrupt(struct buf *b, sqlite3 *db) {
  struct peer s;
  peer_start(&s, db, OP_INTERRUPT, 0);
  peer_go(&s);
  int ok = peer_wait(&s, 10000);
  peer_join(&s);
  bput(b, "  interrupt from a second thread: made %s; is_interrupted %d before, "
          "%d after\n",
       ok ? "yes" : "NO (timed out)", s.before, s.after);
}

/* ---- the work --------------------------------------------------------- */

/* Counts to 2e9: minutes of work; only an interrupt ends it in time. */
static const char *LONG_SQL =
    "WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM c WHERE i < "
    "2000000000) SELECT count(*) FROM c";

static const char *THREE_ROWS = "SELECT column1 FROM (VALUES(1),(2),(3))";

struct stepped {
  int rc, ext;
  char msg[200];
  double t_return;
};

/* Steps st on this thread while a peer interrupts after delay ms. */
static struct stepped step_with_interrupt(sqlite3 *db, sqlite3_stmt *st,
                                          int delay, struct peer *s) {
  struct stepped r;
  peer_start(s, db, OP_INTERRUPT, delay);
  peer_go(s);
  r.rc = sqlite3_step(st);
  r.t_return = now_ms();
  peer_done(s);
  r.ext = sqlite3_extended_errcode(db);
  snprintf(r.msg, sizeof r.msg, "%s", sqlite3_errmsg(db));
  peer_join(s);
  return r;
}

static void put_peer(struct buf *b, struct peer *s, struct stepped *r,
                     const char *what) {
  bput(b,
       "  peer: interrupted %s; the call was still running then: %s; "
       "is_interrupted %d just before the interrupt, %d just after\n",
       s->fired ? "yes" : "NO", (s->running && s->t_call < r->t_return)
                                    ? "yes" : "no",
       s->before, s->after);
  bput(b, "  %s answered %d %s, extended %d %s, \"%s\"\n", what, r->rc,
       name_of(r->rc), r->ext, name_of(r->ext), r->msg);
}

/* I1: a long step, interrupted after 100 ms. */
static void i1_run(struct buf *b, int mutex_flag, int run, double *lat,
                   double *call_us) {
  char file[64];
  struct peer s;
  snprintf(file, sizeof file, "i1-%d-%d.db", mutex_flag, run);
  sqlite3 *db = open_db(file, mutex_flag);
  bput(b, "  fresh connection: is_interrupted %d\n", sqlite3_is_interrupted(db));
  sqlite3_stmt *st = prep(db, LONG_SQL);
  bput(b, "  after prepare: is_interrupted %d\n", sqlite3_is_interrupted(db));
  struct stepped r = step_with_interrupt(db, st, 100, &s);
  put_peer(b, &s, &r, "step");
  lat[run] = r.t_return - s.t_call;
  call_us[run] = (s.t_return - s.t_call) * 1000.0;
  bput(b, "  after the step: errcode %d, is_interrupted %d, stmt_busy %d\n",
       sqlite3_errcode(db), sqlite3_is_interrupted(db), sqlite3_stmt_busy(st));
  int rr = sqlite3_reset(st);
  bput(b, "  reset answered %d %s; then is_interrupted %d\n", rr, name_of(rr),
       sqlite3_is_interrupted(db));
  int fr = sqlite3_finalize(st);
  bput(b, "  finalize answered %d %s; then is_interrupted %d\n", fr,
       name_of(fr), sqlite3_is_interrupted(db));
  sqlite3_stmt *n = NULL;
  int pr = sqlite3_prepare_v2(db, "SELECT 1", -1, &n, NULL);
  bput(b, "  next statement SELECT 1: prepare %d %s, then is_interrupted %d\n",
       pr, name_of(pr), sqlite3_is_interrupted(db));
  if (n) {
    int sr = sqlite3_step(n);
    bput(b, "  ... its step %d %s, then is_interrupted %d\n", sr, name_of(sr),
         sqlite3_is_interrupted(db));
    sqlite3_finalize(n);
  }
  close_db(db);
}

static void i1(int mutex_flag, const char *name) {
  struct buf first, cur;
  double lat[RUNS], call_us[RUNS];
  int same = 0;
  char label[128];
  for (int run = 0; run < RUNS; run++) {
    memset(&cur, 0, sizeof cur);
    i1_run(&cur, mutex_flag, run, lat, call_us);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  printf("I1 %s: a long step (a recursive CTE counting to 2e9), interrupted "
         "from a second thread after 100 ms\n%s",
         name, first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
  snprintf(label, sizeof label,
           "I1 %s: ms from sqlite3_interrupt's call to the step's return", name);
  dist(label, lat, RUNS, "ms");
  snprintf(label, sizeof label,
           "I1 %s: the sqlite3_interrupt call itself, during the step", name);
  dist(label, call_us, RUNS, "us");
}

/* I2: interrupts while no statement runs. */
static void i2(void) {
  struct buf b;
  sqlite3 *db;
  sqlite3_stmt *st;
  int rc;

  memset(&b, 0, sizeof b);
  bput(&b, "I2a: a fresh connection, no statement ever prepared\n");
  db = open_db("i2a.db", SQLITE_OPEN_FULLMUTEX);
  idle_interrupt(&b, db);
  put_state(&b, "  then", db);
  st = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT 1", -1, &st, NULL);
  bput(&b, "  prepare SELECT 1: %d %s; then is_interrupted %d\n", rc,
       name_of(rc), sqlite3_is_interrupted(db));
  rc = sqlite3_step(st);
  bput(&b, "  its step: %d %s; then is_interrupted %d\n", rc, name_of(rc),
       sqlite3_is_interrupted(db));
  sqlite3_finalize(st);
  close_db(db);

  bput(&b, "I2b: a statement prepared, not yet stepped\n");
  db = open_db("i2b.db", SQLITE_OPEN_FULLMUTEX);
  st = prep(db, "SELECT 1");
  idle_interrupt(&b, db);
  rc = sqlite3_step(st);
  bput(&b, "  its step: %d %s; then is_interrupted %d\n", rc, name_of(rc),
       sqlite3_is_interrupted(db));
  sqlite3_finalize(st);
  close_db(db);

  bput(&b, "I2c: after a statement was stepped to a row, then reset\n");
  db = open_db("i2c.db", SQLITE_OPEN_FULLMUTEX);
  st = prep(db, THREE_ROWS);
  rc = sqlite3_step(st);
  bput(&b, "  step %d %s; ", rc, name_of(rc));
  rc = sqlite3_reset(st);
  bput(&b, "reset %d %s; stmt_busy %d\n", rc, name_of(rc), sqlite3_stmt_busy(st));
  idle_interrupt(&b, db);
  rc = sqlite3_step(st);
  bput(&b, "  the same statement stepped again: %d %s; then is_interrupted %d\n",
       rc, name_of(rc), sqlite3_is_interrupted(db));
  sqlite3_finalize(st);
  close_db(db);

  bput(&b, "I2d: after a statement was stepped, then finalized\n");
  db = open_db("i2d.db", SQLITE_OPEN_FULLMUTEX);
  st = prep(db, THREE_ROWS);
  rc = sqlite3_step(st);
  bput(&b, "  step %d %s; ", rc, name_of(rc));
  rc = sqlite3_finalize(st);
  bput(&b, "finalize %d %s\n", rc, name_of(rc));
  idle_interrupt(&b, db);
  st = prep(db, "SELECT 1");
  bput(&b, "  a new statement prepared: is_interrupted %d\n",
       sqlite3_is_interrupted(db));
  rc = sqlite3_step(st);
  bput(&b, "  its step: %d %s; then is_interrupted %d\n", rc, name_of(rc),
       sqlite3_is_interrupted(db));
  sqlite3_finalize(st);
  close_db(db);

  bput(&b, "I2e: after a statement ran to DONE and was left unreset\n");
  db = open_db("i2e.db", SQLITE_OPEN_FULLMUTEX);
  st = prep(db, "SELECT 1");
  rc = sqlite3_step(st);
  bput(&b, "  step %d %s, ", rc, name_of(rc));
  rc = sqlite3_step(st);
  bput(&b, "step %d %s; stmt_busy %d\n", rc, name_of(rc), sqlite3_stmt_busy(st));
  idle_interrupt(&b, db);
  sqlite3_stmt *n = prep(db, "SELECT 2");
  rc = sqlite3_step(n);
  bput(&b, "  another statement's step: %d %s; then is_interrupted %d\n", rc,
       name_of(rc), sqlite3_is_interrupted(db));
  sqlite3_finalize(n);
  sqlite3_finalize(st);
  close_db(db);
  printf("%s", b.s);
}

/* I3: an interrupt while a statement holds a row: it is active but not
 * running. What do it, and statements started after, answer? */
static void i3(void) {
  struct buf b;
  int rc;
  memset(&b, 0, sizeof b);
  bput(&b, "I3: statement A (three rows) stepped once and held at its row, "
           "then an interrupt\n");
  sqlite3 *db = open_db("i3.db", SQLITE_OPEN_FULLMUTEX);
  sqlite3_stmt *a = prep(db, THREE_ROWS);
  rc = sqlite3_step(a);
  bput(&b, "  A's step %d %s; stmt_busy %d\n", rc, name_of(rc),
       sqlite3_stmt_busy(a));
  idle_interrupt(&b, db);
  sqlite3_stmt *p = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT 2", -1, &p, NULL);
  bput(&b, "  prepare \"SELECT 2\" (whitespace inside): %d %s, extended %d, "
           "\"%s\", statement %s\n",
       rc, name_of(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db),
       p ? "made" : "NULL");
  if (p) sqlite3_finalize(p);
  p = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT(2)", -1, &p, NULL);
  bput(&b, "  prepare \"SELECT(2)\" (no whitespace): %d %s, statement %s\n", rc,
       name_of(rc), p ? "made" : "NULL");
  if (p) {
    rc = sqlite3_step(p);
    bput(&b, "  ... its step: %d %s, \"%s\"\n", rc, name_of(rc),
         sqlite3_errmsg(db));
    sqlite3_finalize(p);
  }
  bput(&b, "  is_interrupted %d\n", sqlite3_is_interrupted(db));
  rc = sqlite3_step(a);
  bput(&b, "  A's next step: %d %s, \"%s\"; stmt_busy %d; is_interrupted %d\n",
       rc, name_of(rc), sqlite3_errmsg(db), sqlite3_stmt_busy(a),
       sqlite3_is_interrupted(db));
  rc = sqlite3_reset(a);
  bput(&b, "  A's reset: %d %s\n", rc, name_of(rc));
  p = prep(db, "SELECT 3");
  rc = sqlite3_step(p);
  bput(&b, "  then a new statement: %d %s; is_interrupted %d\n", rc,
       name_of(rc), sqlite3_is_interrupted(db));
  sqlite3_finalize(p);
  rc = sqlite3_step(a);
  bput(&b, "  and A after its reset: %d %s\n", rc, name_of(rc));
  sqlite3_finalize(a);
  close_db(db);
  printf("%s", b.s);
}

/* I4: a long step interrupted, then a second statement started before the
 * first is reset; with and without a third statement holding a row. */
static void i4_run(struct buf *b, int with_holder, int run) {
  char file[64];
  struct peer s;
  int rc;
  snprintf(file, sizeof file, "i4-%d-%d.db", with_holder, run);
  sqlite3 *db = open_db(file, SQLITE_OPEN_FULLMUTEX);
  sqlite3_stmt *h = NULL;
  if (with_holder) {
    h = prep(db, THREE_ROWS);
    rc = sqlite3_step(h);
    bput(b, "  holder H stepped once: %d %s\n", rc, name_of(rc));
  }
  sqlite3_stmt *s1 = prep(db, LONG_SQL);
  struct stepped r = step_with_interrupt(db, s1, 100, &s);
  put_peer(b, &s, &r, "S1's step");
  bput(b, "  S1 not reset: stmt_busy %d; is_interrupted %d\n",
       sqlite3_stmt_busy(s1), sqlite3_is_interrupted(db));
  sqlite3_stmt *s2 = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT 1", -1, &s2, NULL);
  bput(b, "  S2 \"SELECT 1\": prepare %d %s", rc, name_of(rc));
  if (s2) {
    rc = sqlite3_step(s2);
    bput(b, ", step %d %s", rc, name_of(rc));
    sqlite3_finalize(s2);
  }
  bput(b, "; then is_interrupted %d\n", sqlite3_is_interrupted(db));
  s2 = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT(1)", -1, &s2, NULL);
  bput(b, "  S2' \"SELECT(1)\": prepare %d %s", rc, name_of(rc));
  if (s2) {
    rc = sqlite3_step(s2);
    bput(b, ", step %d %s", rc, name_of(rc));
    sqlite3_finalize(s2);
  }
  bput(b, "\n");
  if (h) {
    rc = sqlite3_step(h);
    bput(b, "  H's next step: %d %s\n", rc, name_of(rc));
    sqlite3_finalize(h);
    s2 = prep(db, "SELECT 1");
    rc = sqlite3_step(s2);
    bput(b, "  after H's finalize, a new statement: %d %s; is_interrupted %d\n",
         rc, name_of(rc), sqlite3_is_interrupted(db));
    sqlite3_finalize(s2);
  }
  sqlite3_finalize(s1);
  close_db(db);
}

static void i4(int with_holder) {
  struct buf first, cur;
  int same = 0;
  for (int run = 0; run < RUNS; run++) {
    memset(&cur, 0, sizeof cur);
    i4_run(&cur, with_holder, run);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  printf("I4%s: long S1 interrupted after 100 ms; S2 started before S1's "
         "reset%s\n%s",
         with_holder ? "b" : "a",
         with_holder ? ", while H holds a row" : "", first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
}

/* I5: interrupts inside transactions. Table t holds 2000 committed rows;
 * triggers make every row written by INSERT, UPDATE or DELETE cost a scan
 * of big's 100,000 rows, so each write runs for seconds and is writing
 * rows when the interrupt lands. */
static void setup_tx(sqlite3 *db) {
  must(db, "CREATE TABLE big(v INTEGER)");
  must(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, x INTEGER, y INTEGER)");
  must(db, "BEGIN");
  must(db, "INSERT INTO big(v) WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL "
           "SELECT i+1 FROM c WHERE i < 100000) SELECT i FROM c");
  must(db, "INSERT INTO t(x, y) WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL "
           "SELECT i+1 FROM c WHERE i < 2000) SELECT i, 0 FROM c");
  must(db, "COMMIT");
  must(db, "CREATE TRIGGER ti AFTER INSERT ON t BEGIN SELECT count(*) FROM "
           "big WHERE v <> new.x; END");
  must(db, "CREATE TRIGGER tu AFTER UPDATE ON t BEGIN SELECT count(*) FROM "
           "big WHERE v <> new.x; END");
  must(db, "CREATE TRIGGER td AFTER DELETE ON t BEGIN SELECT count(*) FROM "
           "big WHERE v <> old.x; END");
}

static void put_table(struct buf *b, const char *label, sqlite3 *db) {
  bput(b, "%s: rows %lld, markers %lld, sum(y) %lld\n", label,
       qint(db, "SELECT count(*) FROM t"),
       qint(db, "SELECT count(*) FROM t WHERE x < 0"),
       qint(db, "SELECT total(y) FROM t"));
}

struct txcase {
  const char *name;
  const char *begin[3]; /* run in order before the interrupted statement */
  const char *stmt;     /* the statement interrupted after 100 ms */
  const char *after[3]; /* run in order afterwards, each answer shown */
};

static void i5_case(const struct txcase *c, int idx) {
  struct buf b;
  struct peer s;
  char file[64];
  int rc;
  memset(&b, 0, sizeof b);
  snprintf(file, sizeof file, "i5-%d.db", idx);
  sqlite3 *db = open_db(file, SQLITE_OPEN_FULLMUTEX);
  setup_tx(db);
  bput(&b, "I5 %s\n", c->name);
  for (int i = 0; i < 3 && c->begin[i]; i++) {
    struct ans a = run_sql(db, c->begin[i]);
    bput(&b, "  %s: %d %s\n", c->begin[i], a.rc, name_of(a.rc));
  }
  sqlite3_stmt *reader = prep(db, "SELECT x FROM t ORDER BY id");
  rc = sqlite3_step(reader);
  bput(&b, "  reader R on t stepped once: %d %s\n", rc, name_of(rc));
  put_state(&b, "  before the statement", db);
  bput(&b, "  the statement: %s\n", c->stmt);
  sqlite3_stmt *st = prep(db, c->stmt);
  struct stepped r = step_with_interrupt(db, st, 100, &s);
  put_peer(&b, &s, &r, "its step");
  put_state(&b, "  after it", db);
  rc = sqlite3_step(reader);
  bput(&b, "  R's next step: %d %s, extended %d %s, \"%s\"\n", rc, name_of(rc),
       sqlite3_extended_errcode(db), name_of(sqlite3_extended_errcode(db)),
       sqlite3_errmsg(db));
  sqlite3_finalize(reader);
  sqlite3_finalize(st);
  put_table(&b, "  this connection sees", db);
  for (int i = 0; i < 3 && c->after[i]; i++) {
    char label[160];
    snprintf(label, sizeof label, "  %s", c->after[i]);
    put_ans(&b, label, run_sql(db, c->after[i]));
  }
  put_state(&b, "  then", db);
  sqlite3 *other = open_db(file, SQLITE_OPEN_FULLMUTEX);
  put_table(&b, "  a new connection then sees", other);
  close_db(other);
  close_db(db);
  printf("%s", b.s);
}

static void i5(void) {
  static const struct txcase cases[] = {
      {"INSERT of 2000 rows inside BEGIN, after a marker row",
       {"BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)", NULL},
       "INSERT INTO t(x, y) SELECT x + 100000, 1 FROM t WHERE x > 0",
       {"COMMIT", "ROLLBACK", NULL}},
      {"UPDATE of 2000 rows inside BEGIN, after a marker row",
       {"BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)", NULL},
       "UPDATE t SET y = y + 1 WHERE x > 0",
       {"COMMIT", "ROLLBACK", NULL}},
      {"DELETE of 2000 rows inside BEGIN, after a marker row",
       {"BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)", NULL},
       "DELETE FROM t WHERE x > 0",
       {"COMMIT", "ROLLBACK", NULL}},
      {"SELECT inside BEGIN, after a marker row (a write transaction)",
       {"BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)", NULL},
       "SELECT count(*) FROM t, big",
       {"COMMIT", "ROLLBACK", NULL}},
      {"SELECT inside BEGIN that has only read (a read transaction)",
       {"BEGIN", "SELECT count(*) FROM t", NULL},
       "SELECT count(*) FROM t, big",
       {"COMMIT", NULL, NULL}},
      {"UPDATE inside nested savepoints a > b, no BEGIN",
       {"SAVEPOINT a", "INSERT INTO t(x, y) VALUES(-1, -1)", "SAVEPOINT b"},
       "UPDATE t SET y = y + 1 WHERE x > 0",
       {"ROLLBACK TO b", "RELEASE a", "COMMIT"}},
      /* No trigger on t, so the statement's only work is its own rows. Calling
       * a function (abs) gives the statement a statement journal; the plain
       * one is the contrast. */
      {"INSERT ... SELECT abs(i) FROM a 2e9-row recursive CTE inside BEGIN, "
       "after a marker row, no trigger (the statement calls a function)",
       {"DROP TRIGGER ti", "BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)"},
       "INSERT INTO t(x, y) WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL SELECT "
       "i+1 FROM c WHERE i < 2000000000) SELECT abs(i), 1 FROM c",
       {"COMMIT", "ROLLBACK", NULL}},
      {"INSERT ... SELECT i FROM a 2e9-row recursive CTE inside BEGIN, after a "
       "marker row, no trigger (no function called)",
       {"DROP TRIGGER ti", "BEGIN", "INSERT INTO t(x, y) VALUES(-1, -1)"},
       "INSERT INTO t(x, y) WITH RECURSIVE c(i) AS (VALUES(1) UNION ALL SELECT "
       "i+1 FROM c WHERE i < 2000000000) SELECT i, 1 FROM c",
       {"COMMIT", "ROLLBACK", NULL}},
  };
  for (int i = 0; i < (int)(sizeof cases / sizeof cases[0]); i++)
    i5_case(&cases[i], i);
}

/* I6: a step or a prepare blocked in the busy timeout (600 ms), on another
 * connection's lock, interrupted after 100 ms. */
enum blocker { B_BEGIN_IMMEDIATE, B_INSERT, B_WAL_BEGIN_IMMEDIATE, B_COMMIT,
               B_PREPARE };

static const char *blocker_name[] = {
    "rollback journal: BEGIN IMMEDIATE under the other's BEGIN IMMEDIATE",
    "rollback journal: an autocommit INSERT under the other's BEGIN IMMEDIATE",
    "WAL: BEGIN IMMEDIATE under the other's BEGIN IMMEDIATE",
    "rollback journal: COMMIT under the other's read (a statement at a row)",
    "rollback journal: a fresh connection's prepare under the other's BEGIN "
    "EXCLUSIVE and a write"};

#define I6_TIMEOUT 600

static void i6_run(struct buf *b, enum blocker k, int run, double *elapsed) {
  char file[64];
  struct peer s;
  int rc;
  snprintf(file, sizeof file, "i6-%d-%d.db", (int)k, run);
  sqlite3 *other = open_db(file, SQLITE_OPEN_FULLMUTEX);
  must(other, "CREATE TABLE t(x)");
  must(other, "INSERT INTO t VALUES(1), (2), (3)");
  if (k == B_WAL_BEGIN_IMMEDIATE) {
    sqlite3_stmt *jm = prep(other, "PRAGMA journal_mode=wal");
    sqlite3_step(jm);
    bput(b, "  journal_mode: %s\n", sqlite3_column_text(jm, 0));
    sqlite3_finalize(jm);
  }
  sqlite3 *db = open_db(file, SQLITE_OPEN_FULLMUTEX);
  sqlite3_busy_timeout(db, I6_TIMEOUT);
  if (k != B_PREPARE) {
    long long n = qint(db, "SELECT count(*) FROM t");
    bput(b, "  the blocked connection read %lld rows first\n", n);
  }
  sqlite3_stmt *held = NULL;
  if (k == B_COMMIT) {
    held = prep(other, "SELECT x FROM t");
    rc = sqlite3_step(held);
    bput(b, "  the other's reader stepped: %d %s\n", rc, name_of(rc));
    must(db, "BEGIN");
    must(db, "INSERT INTO t VALUES(4)");
  } else if (k == B_PREPARE) {
    must(other, "BEGIN EXCLUSIVE");
    must(other, "INSERT INTO t VALUES(5)");
  } else {
    must(other, "BEGIN IMMEDIATE");
  }
  struct stepped r;
  double t0;
  if (k == B_PREPARE) {
    sqlite3_stmt *p = NULL;
    peer_start(&s, db, OP_INTERRUPT, 100);
    peer_go(&s);
    t0 = now_ms();
    r.rc = sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &p, NULL);
    r.t_return = now_ms();
    peer_done(&s);
    r.ext = sqlite3_extended_errcode(db);
    snprintf(r.msg, sizeof r.msg, "%s", sqlite3_errmsg(db));
    peer_join(&s);
    if (p) sqlite3_finalize(p);
  } else {
    const char *sql = k == B_INSERT ? "INSERT INTO t VALUES(9)"
                      : k == B_COMMIT ? "COMMIT"
                                      : "BEGIN IMMEDIATE";
    sqlite3_stmt *st = prep(db, sql);
    t0 = now_ms();
    r = step_with_interrupt(db, st, 100, &s);
    sqlite3_finalize(st);
  }
  elapsed[run] = r.t_return - t0;
  put_peer(b, &s, &r, k == B_PREPARE ? "prepare" : "step");
  double e = elapsed[run];
  bput(b, "  it ended %s\n",
       e < I6_TIMEOUT / 2.0          ? "early: before half the busy timeout"
       : e >= I6_TIMEOUT * 0.9       ? "at the busy timeout: at least 90% of it"
                                     : "between half and 90% of the busy timeout");
  put_state(b, "  then", db);
  sqlite3_stmt *n = NULL;
  rc = sqlite3_prepare_v2(db, "SELECT 1", -1, &n, NULL);
  if (n) {
    rc = sqlite3_step(n);
    sqlite3_finalize(n);
  }
  bput(b, "  next statement SELECT 1 on it: %d %s; then is_interrupted %d\n", rc,
       name_of(rc), sqlite3_is_interrupted(db));
  if (held) sqlite3_finalize(held);
  if (k == B_COMMIT) {
    struct ans a = run_sql(db, "COMMIT");
    bput(b, "  after the other's reader finalized, COMMIT again: %d %s\n", a.rc,
         name_of(a.rc));
  } else {
    must(other, "COMMIT");
    if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
  }
  close_db(db);
  close_db(other);
}

static void i6(enum blocker k) {
  struct buf first, cur;
  double elapsed[RUNS];
  int same = 0;
  char label[200];
  for (int run = 0; run < RUNS; run++) {
    memset(&cur, 0, sizeof cur);
    i6_run(&cur, k, run, elapsed);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  printf("I6%c: %s; busy timeout %d ms; interrupted after 100 ms\n%s",
         'a' + (int)k, blocker_name[k], I6_TIMEOUT, first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
  snprintf(label, sizeof label, "I6%c: ms from the call to its return",
           'a' + (int)k);
  dist(label, elapsed, RUNS, "ms");
}

/* I7: an interrupt during sqlite3_prepare_v2 of a very long SQL text:
 * "SELECT 1" followed by N comments, each a whitespace token. */
#define I7_TOKENS 20000000

static void i7(void) {
  size_t unit = 5; /* a space, then an empty comment */
  size_t len = 8 + unit * I7_TOKENS;
  char *sql = malloc(len + 1);
  double plain[RUNS], lat[RUNS];
  struct buf first, cur;
  int same = 0;
  if (!sql) {
    printf("FATAL: malloc for I7\n");
    exit(1);
  }
  memcpy(sql, "SELECT 1", 8);
  for (size_t i = 0; i < I7_TOKENS; i++) memcpy(sql + 8 + i * unit, " /**/", unit);
  sql[len] = 0;
  sqlite3 *db = open_db("i7.db", SQLITE_OPEN_FULLMUTEX);
  for (int run = 0; run < RUNS; run++) {
    sqlite3_stmt *st = NULL;
    double t0 = now_ms();
    int rc = sqlite3_prepare_v2(db, sql, (int)len, &st, NULL);
    plain[run] = now_ms() - t0;
    if (rc != SQLITE_OK || !st) fatal("I7 plain prepare", db, rc);
    sqlite3_finalize(st);
  }
  for (int run = 0; run < RUNS; run++) {
    struct peer s;
    sqlite3_stmt *st = NULL;
    memset(&cur, 0, sizeof cur);
    peer_start(&s, db, OP_INTERRUPT, 50);
    peer_go(&s);
    int rc = sqlite3_prepare_v2(db, sql, (int)len, &st, NULL);
    double t1 = now_ms();
    peer_done(&s);
    int ext = sqlite3_extended_errcode(db);
    char msg[200];
    snprintf(msg, sizeof msg, "%s", sqlite3_errmsg(db));
    peer_join(&s);
    lat[run] = t1 - s.t_call;
    bput(&cur, "  peer: interrupted %s; the prepare was still running then: %s\n",
         s.fired ? "yes" : "NO", (s.running && s.t_call < t1) ? "yes" : "no");
    bput(&cur, "  prepare answered %d %s, extended %d %s, \"%s\", statement %s\n",
         rc, name_of(rc), ext, name_of(ext), msg, st ? "made" : "NULL");
    bput(&cur, "  then is_interrupted %d\n", sqlite3_is_interrupted(db));
    if (st) sqlite3_finalize(st);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  sqlite3_stmt *st = prep(db, "SELECT 1");
  int rc = sqlite3_step(st);
  sqlite3_finalize(st);
  close_db(db);
  free(sql);
  printf("I7: prepare_v2 of \"SELECT 1\" and %d comments (%zu bytes), "
         "interrupted after 50 ms\n%s",
         I7_TOKENS, len, first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
  printf("  afterwards SELECT 1 on the connection: %d %s\n", rc, name_of(rc));
  dist("I7: the same prepare, not interrupted: ms", plain, RUNS, "ms");
  dist("I7: ms from sqlite3_interrupt's call to the prepare's return", lat,
       RUNS, "ms");
}

/* I8: under FULLMUTEX, another thread's sqlite3_errmsg during a long step
 * waits for the step: it takes the connection's mutex, which the step
 * holds. sqlite3_interrupt doesn't. */
static void i8(void) {
  struct buf first, cur;
  double wait[RUNS];
  int same = 0;
  for (int run = 0; run < RUNS; run++) {
    char file[64];
    struct peer e, s;
    memset(&cur, 0, sizeof cur);
    snprintf(file, sizeof file, "i8-%d.db", run);
    sqlite3 *db = open_db(file, SQLITE_OPEN_FULLMUTEX);
    sqlite3_stmt *st = prep(db, LONG_SQL);
    peer_start(&e, db, OP_ERRMSG, 100);
    peer_start(&s, db, OP_INTERRUPT, 300);
    peer_go(&e);
    peer_go(&s);
    int rc = sqlite3_step(st);
    double t1 = now_ms();
    peer_done(&e);
    peer_done(&s);
    peer_join(&s);
    peer_join(&e);
    wait[run] = e.t_return - e.t_call;
    bput(&cur, "  step answered %d %s\n", rc, name_of(rc));
    bput(&cur, "  errmsg thread: called while the step ran: %s; returned only "
               "after the interrupt was made: %s\n",
         e.running ? "yes" : "no", e.t_return > s.t_call ? "yes" : "no");
    bput(&cur, "  interrupt thread: called while errmsg was still waiting: %s; "
               "the interrupt call returned before the step did: %s\n",
         s.t_call < e.t_return ? "yes" : "no", s.t_return < t1 ? "yes" : "no");
    sqlite3_finalize(st);
    close_db(db);
    if (run == 0) first = cur;
    if (strcmp(first.s, cur.s) == 0) same++;
  }
  printf("I8: FULLMUTEX; a long step; thread E calls sqlite3_errmsg at 100 ms, "
         "thread I calls sqlite3_interrupt at 300 ms\n%s",
         first.s);
  printf("  runs whose facts equal run 1's: %d of %d\n", same, RUNS);
  dist("I8: ms thread E's sqlite3_errmsg took", wait, RUNS, "ms");
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: interrupt SCRATCH-DIR TIMING-FILE\n");
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

  watch("I1 FULLMUTEX", 120);
  i1(SQLITE_OPEN_FULLMUTEX, "FULLMUTEX");
  watch("I1 NOMUTEX", 120);
  i1(SQLITE_OPEN_NOMUTEX, "NOMUTEX");
  watch("I2", 60);
  i2();
  watch("I3", 60);
  i3();
  watch("I4a", 120);
  i4(0);
  watch("I4b", 120);
  i4(1);
  watch("I5", 300);
  i5();
  for (int k = B_BEGIN_IMMEDIATE; k <= B_PREPARE; k++) {
    watch(blocker_name[k], 120);
    i6((enum blocker)k);
  }
  watch("I7", 300);
  i7();
  watch("I8", 120);
  i8();
  alarm(0);
  printf("end\n");
  return 0;
}
