/* failed-active.c: what M2's failed state covers, as ADR-0017's context and
 * the M3 plan's section 4.2 have it from the plan's second review, which
 * left no file in the research:
 *
 *   "After a column read's NOMEM ... and after a step that answered BUSY,
 *   sqlite3_stmt_busy read 1, and after an interrupt a prepare answered 9.
 *   Beside the NOMEM one, a BEGIN IMMEDIATE answered 5 at once against a
 *   600 ms timeout. The controls, a step failing on a constraint and a
 *   statement at done, read 0, the BEGIN waited, and the prepare answered 0."
 *
 *   failed-active DIR
 *
 * Each case has a file of its own in rollback-journal mode: src, 10 rows of
 * 3,000 bytes; u(x UNIQUE) holding 1. c1 leaves a statement S in the case's
 * state, and reads sqlite3_stmt_busy(S). Then a fresh prepare and step of
 * SELECT 1 on c1. Then c2 takes BEGIN IMMEDIATE and writes, and c1, with a
 * 1500 ms busy timeout (AGENTS.md: at least 1500, asserted at least 1000),
 * runs BEGIN IMMEDIATE: "at once" under 100 ms, "waited" at 1000 ms or more.
 * The milliseconds are on "time:" lines, left out of comparisons. Then c2
 * rolls back and S is finalized.
 *
 * A watchdog alarm ends the probe after 120 s.
 */
#define _GNU_SOURCE
#include <signal.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const char *dir;
static sqlite3 *c1, *c2;
static char *big;

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

static sqlite3 *open_at(const char *name) {
  char path[4096];
  sqlite3 *d = NULL;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &d, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open: %d\n", rc); exit(2); }
  return d;
}

static void must(sqlite3 *d, const char *sql) {
  char *m = NULL;
  if (sqlite3_exec(d, sql, NULL, NULL, &m) != SQLITE_OK) { fprintf(stderr, "%s: %s\n", sql, m); exit(2); }
}

static sqlite3_stmt *prep(sqlite3 *d, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(d, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || !st) { fprintf(stderr, "%s: prepare %d\n", sql, rc); exit(2); }
  return st;
}

static int progress_calls = 0, interrupt_at = 50;
static int on_progress(void *arg) {
  (void)arg;
  progress_calls++;
  if (progress_calls == interrupt_at) sqlite3_interrupt(c1);
  return 0;
}

static void after(sqlite3_stmt *s) {
  int busy = sqlite3_stmt_busy(s);
  printf("  stmt_busy(S): %d\n", busy);
  sqlite3_stmt *q = NULL;
  int rc = sqlite3_prepare_v2(c1, "SELECT 1", -1, &q, NULL);
  if (rc != SQLITE_OK) printf("  c1 prepares SELECT 1: %d, statement %s\n", rc, q ? "made" : "NULL");
  else {
    int st = sqlite3_step(q);
    printf("  c1 prepares SELECT 1: 0; its step %d\n", st);
  }
  if (q) sqlite3_finalize(q);
  must(c2, "BEGIN IMMEDIATE; INSERT INTO u VALUES (500);");
  sqlite3_busy_timeout(c1, 1500);
  double t0 = now_ms();
  int b = sqlite3_exec(c1, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  double t1 = now_ms();
  double ms = t1 - t0;
  const char *how = ms < 100 ? "at once" : ms >= 1000 ? "waited" : "in between";
  printf("  under c2's BEGIN IMMEDIATE and write, c1's BEGIN IMMEDIATE (1500 ms timeout): %d, %s\n", b, how);
  printf("time: %.3f ms\n", ms);
  if (b == SQLITE_OK) must(c1, "ROLLBACK");
  must(c2, "ROLLBACK");
  int f = sqlite3_finalize(s);
  printf("  S finalized: %d\n", f);
}

static void setup(const char *id, const char *title) {
  char name[64];
  snprintf(name, sizeof name, "%s.db", id);
  printf("\n%s. %s\n", id, title);
  c1 = open_at(name);
  c2 = open_at(name);
  must(c1, "CREATE TABLE src(x); CREATE TABLE u(x UNIQUE); INSERT INTO u VALUES (1); "
           "INSERT INTO src SELECT replace(hex(zeroblob(1500)), '0', 'a') FROM "
           "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10) SELECT i FROM n);");
  must(c2, "SELECT count(*) FROM src");
}

static void teardown(void) {
  int a = sqlite3_close(c2), b = sqlite3_close(c1);
  if (a || b) { fprintf(stderr, "close %d %d\n", a, b); exit(2); }
}

#define CTE "WITH RECURSIVE k(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM k WHERE i < 100000000) "

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  dir = argv[1];
  signal(SIGALRM, on_alarm);
  alarm(120);
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID)) {
    fprintf(stderr, "refused: header and library differ\n");
    return 2;
  }
  printf("libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
  big = malloc(100000);
  if (!big) return 2;
  memset(big, 'a', 100000);

  {
    setup("F1", "a column read's NOMEM: SELECT ?1 FROM src, 100,000 bytes of TEXT bound with their length");
    sqlite3_stmt *s = prep(c1, "SELECT ?1 FROM src LIMIT 1");
    sqlite3_bind_text64(s, 1, big, 100000, SQLITE_STATIC, SQLITE_UTF8);
    int rc = sqlite3_step(s);
    sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
    const unsigned char *p = sqlite3_column_text(s, 0);
    int ext = sqlite3_extended_errcode(c1);
    sqlite3_hard_heap_limit64(0);
    sqlite3_soft_heap_limit64(0);
    printf("  S step %d; sqlite3_column_text under the heap limit: %s, extended %d\n", rc, p ? "a pointer" : "NULL", ext);
    after(s);
    teardown();
  }
  {
    setup("F2", "a step that answered BUSY: S prepared, then c2's BEGIN EXCLUSIVE and write, then S's step with no timeout");
    sqlite3_stmt *s = prep(c1, "SELECT x FROM src");
    must(c2, "BEGIN EXCLUSIVE; INSERT INTO u VALUES (400);");
    sqlite3_busy_timeout(c1, 0);
    int rc = sqlite3_step(s);
    int ext = sqlite3_extended_errcode(c1);
    printf("  S step: %d, extended %d\n", rc, ext);
    must(c2, "ROLLBACK");
    after(s);
    teardown();
  }
  {
    setup("F3", "an interrupted first step: S a long SELECT reading a table, interrupted at its 50th progress call");
    sqlite3_stmt *s = prep(c1, CTE "SELECT count(*) FROM k, src");
    progress_calls = 0; interrupt_at = 50;
    sqlite3_progress_handler(c1, 100, on_progress, NULL);
    int rc = sqlite3_step(s);
    sqlite3_progress_handler(c1, 0, NULL, NULL);
    int intr = sqlite3_is_interrupted(c1);
    printf("  S step: %d; progress calls %d; is_interrupted %d\n", rc, progress_calls, intr);
    after(s);
    teardown();
  }
  {
    setup("F4", "an interrupted later step: S answered a row, then its next step was interrupted");
    sqlite3_stmt *s = prep(c1, CTE "SELECT i FROM k, (SELECT x FROM src LIMIT 1) WHERE i % 50000000 = 1");
    int r1 = sqlite3_step(s);
    progress_calls = 0; interrupt_at = 50;
    sqlite3_progress_handler(c1, 100, on_progress, NULL);
    int rc = sqlite3_step(s);
    sqlite3_progress_handler(c1, 0, NULL, NULL);
    int intr = sqlite3_is_interrupted(c1);
    printf("  S first step: %d; next step: %d; progress calls %d; is_interrupted %d\n", r1, rc, progress_calls, intr);
    after(s);
    teardown();
  }
  {
    setup("F5", "an interrupted step beside another statement H held at a row");
    sqlite3_stmt *h = prep(c1, "SELECT x FROM src");
    int hr = sqlite3_step(h);
    sqlite3_stmt *s = prep(c1, CTE "SELECT count(*) FROM k, src");
    progress_calls = 0; interrupt_at = 50;
    sqlite3_progress_handler(c1, 100, on_progress, NULL);
    int rc = sqlite3_step(s);
    sqlite3_progress_handler(c1, 0, NULL, NULL);
    printf("  H step %d; S step: %d\n", hr, rc);
    int hf = sqlite3_finalize(h);
    printf("  (H finalized first, %d, so only S is left)\n", hf);
    after(s);
    teardown();
  }
  {
    setup("F6", "an interrupted step while another statement H still holds a row (concurrency I4b)");
    sqlite3_stmt *h = prep(c1, "SELECT x FROM src");
    int hr = sqlite3_step(h);
    sqlite3_stmt *s = prep(c1, CTE "SELECT count(*) FROM k, src");
    progress_calls = 0; interrupt_at = 50;
    sqlite3_progress_handler(c1, 100, on_progress, NULL);
    int rc = sqlite3_step(s);
    sqlite3_progress_handler(c1, 0, NULL, NULL);
    int sb = sqlite3_stmt_busy(s);
    sqlite3_stmt *q = NULL;
    int qp = sqlite3_prepare_v2(c1, "SELECT 1", -1, &q, NULL);
    if (q) sqlite3_finalize(q);
    printf("  H step %d; S step: %d; stmt_busy(S) %d; with H held, c1 prepares SELECT 1: %d\n", hr, rc, sb, qp);
    int hf = sqlite3_finalize(h);
    printf("  (H finalized, %d)\n", hf);
    after(s);
    teardown();
  }
  {
    setup("C1", "the control: a step failing on a constraint");
    sqlite3_stmt *s = prep(c1, "INSERT INTO u VALUES (1)");
    int rc = sqlite3_step(s);
    printf("  S step: %d\n", rc);
    after(s);
    teardown();
  }
  {
    setup("C2", "the control: a statement at done, not reset");
    sqlite3_stmt *s = prep(c1, "SELECT count(*) FROM src");
    int r1 = sqlite3_step(s);
    int r2 = sqlite3_step(s);
    printf("  S steps: %d then %d\n", r1, r2);
    after(s);
    teardown();
  }
  {
    setup("C3", "the control: a statement at a row (slice-0 P12's held read)");
    sqlite3_stmt *s = prep(c1, "SELECT x FROM src");
    int rc = sqlite3_step(s);
    printf("  S step: %d\n", rc);
    after(s);
    teardown();
  }
  {
    setup("C4", "the control: a statement prepared, never stepped");
    sqlite3_stmt *s = prep(c1, "SELECT x FROM src");
    after(s);
    teardown();
  }
  free(big);
  return 0;
}
