/* B1: SQLite's special errors, NOMEM, FULL and INTERRUPT, and a column
 * read's NOMEM: which of them end the transaction they happen in.
 *
 *   txn-special DIR       DIR: a fresh directory for this run's databases
 *
 * Every case has a database file of its own, set up and committed first:
 *   t(x)             the marker's table, empty
 *   b(x)             a table with no constraints, empty
 *   bn(x NOT NULL)   a table with one constraint, empty
 *   src(x)           10 rows, each 3,000 bytes of 'a' as TEXT
 * Then BEGIN, INSERT INTO t VALUES ('marker'), the statement, and the state:
 * sqlite3_get_autocommit, sqlite3_txn_state(db, "main"), and what this
 * connection sees. Then COMMIT if the transaction is still open, and what a
 * second connection sees once it has.
 *
 *   N  NOMEM by the hard heap limit at memory_used + 1000, set after the
 *      prepare and kept in force across every step, then set back to 0
 *      (txn-errors' method, and M2 slice 4's)
 *   M  NOMEM by exactly one failing allocation: an SQLITE_CONFIG_MALLOC
 *      wrapper, armed just before the first step, fails the first
 *      allocation that reaches it and disarms itself (M1 to M4), or the
 *      first of at least 100,000 bytes (M5). M6 fails that one and every
 *      allocation after it until the step returns, as a limit left in force
 *      would. No heap limit is set.
 *   F  FULL: PRAGMA max_page_count set to PRAGMA page_count, read after the
 *      marker
 *   I  INTERRUPT: sqlite3_interrupt, called from a progress handler
 *   G  a column read's NOMEM: the heap limit set around that one call only,
 *      then sqlite3_reset or sqlite3_finalize
 *   L  an error that ends the transaction, and the writes after it
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;

/* The allocator wrapper of method M. It passes every call through to
 * SQLite's own allocator, except while armed: then the first xMalloc or
 * xRealloc of at least arm_min bytes fails, and the wrapper disarms itself.
 * With keep_failing, it instead fails that one and every call after it,
 * until the probe disarms it. */
static sqlite3_mem_methods real;
static int armed = 0, arm_min = 0, keep_failing = 0, failing = 0;
static int failed_count = 0, failed_size = 0;

static int should_fail(int n) {
  if (!armed) return 0;
  if (failing) { failed_count++; return 1; }
  if (n < arm_min) return 0;
  failed_size = n;
  failed_count = 1;
  if (keep_failing) failing = 1;
  else armed = 0;
  return 1;
}

static void *w_malloc(int n) {
  if (should_fail(n)) return NULL;
  return real.xMalloc(n);
}

static void *w_realloc(void *p, int n) {
  if (should_fail(n)) return NULL;
  return real.xRealloc(p, n);
}

static void install_wrapper(void) {
  int rc = sqlite3_config(SQLITE_CONFIG_GETMALLOC, &real);
  if (rc != SQLITE_OK) { fprintf(stderr, "SQLITE_CONFIG_GETMALLOC: rc %d\n", rc); exit(2); }
  sqlite3_mem_methods w = real;
  w.xMalloc = w_malloc;
  w.xRealloc = w_realloc;
  rc = sqlite3_config(SQLITE_CONFIG_MALLOC, &w);
  if (rc != SQLITE_OK) { fprintf(stderr, "SQLITE_CONFIG_MALLOC: rc %d\n", rc); exit(2); }
}

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

static void close_db(sqlite3 *db) {
  int rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

static void must(sqlite3 *db, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static const char *code_name(int rc) {
  switch (rc & 0xff) {
  case 0: return "OK"; case 1: return "ERROR"; case 4: return "ABORT";
  case 5: return "BUSY"; case 6: return "LOCKED"; case 7: return "NOMEM";
  case 9: return "INTERRUPT"; case 10: return "IOERR"; case 13: return "FULL";
  case 19: return "CONSTRAINT"; case 21: return "MISUSE";
  case 100: return "ROW"; case 101: return "DONE";
  default: return "?";
  }
}

static void print_failure(const char *what, sqlite3 *db, int rc) {
  printf("    %s: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
         what, rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

static const char *txn_name(int s) {
  switch (s) {
  case SQLITE_TXN_NONE: return "NONE"; case SQLITE_TXN_READ: return "READ";
  case SQLITE_TXN_WRITE: return "WRITE"; default: return "-1";
  }
}

static void state(sqlite3 *db) {
  printf("    state: autocommit %d, txn_state(main) %s\n",
         sqlite3_get_autocommit(db), txn_name(sqlite3_txn_state(db, "main")));
}

/* one_int: the first column of a statement's one row. */
static long long one_int(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) { fprintf(stderr, "%s: prepare rc %d\n", sql, rc); exit(2); }
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) { fprintf(stderr, "%s: step rc %d\n", sql, rc); exit(2); }
  long long v = sqlite3_column_int64(st, 0);
  rc = sqlite3_step(st);
  if (rc != SQLITE_DONE) { fprintf(stderr, "%s: second step rc %d\n", sql, rc); exit(2); }
  rc = sqlite3_finalize(st);
  if (rc != SQLITE_OK) { fprintf(stderr, "%s: finalize rc %d\n", sql, rc); exit(2); }
  return v;
}

/* seen: t's rows, b's and bn's counts, and src's rows and bytes, as WHO's
 * connection sees them, on one line. */
static void seen(sqlite3 *who_db, const char *who) {
  const char *sql =
    "SELECT (SELECT coalesce(group_concat(x, ','), '(none)') FROM (SELECT x FROM t ORDER BY x)), "
    "(SELECT count(*) FROM b), (SELECT count(*) FROM bn), "
    "(SELECT count(*) FROM src), (SELECT sum(length(x)) FROM src)";
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(who_db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("seen: prepare", who_db, rc); exit(2); }
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) { print_failure("seen: step", who_db, rc); exit(2); }
  const char *rows_of_t = (const char *)sqlite3_column_text(st, 0);
  long long in_b = sqlite3_column_int64(st, 1);
  long long in_bn = sqlite3_column_int64(st, 2);
  long long in_src = sqlite3_column_int64(st, 3);
  long long src_bytes = sqlite3_column_int64(st, 4);
  printf("    %s sees: t %s; b %lld rows; bn %lld rows; src %lld rows of %lld bytes\n", who,
         rows_of_t, in_b, in_bn, in_src, src_bytes);
  rc = sqlite3_step(st);
  if (rc != SQLITE_DONE) { print_failure("seen: second step", who_db, rc); exit(2); }
  rc = sqlite3_finalize(st);
  if (rc != SQLITE_OK) { print_failure("seen: finalize", who_db, rc); exit(2); }
}

enum method { PLAIN, HEAP_LIMIT, ONE_ALLOCATION, FROM_ONE_ON };

/* run_by: prepare one statement, step it to the end, finalize it, causing
 * NOMEM by the method named. MIN is the wrapper's arm_min. */
static int run_by(sqlite3 *db, const char *sql, enum method m, int min) {
  sqlite3_stmt *st = NULL;
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { print_failure("prepare", db, rc); return rc; }
  if (st == NULL) { printf("    prepare: rc 0, no statement\n"); return rc; }
  if (m == HEAP_LIMIT) {
    sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  } else if (m == ONE_ALLOCATION || m == FROM_ONE_ON) {
    long long soft = sqlite3_soft_heap_limit64(-1);
    long long hard = sqlite3_hard_heap_limit64(-1);
    printf("    (heap limits before arming: soft %lld, hard %lld)\n", soft, hard);
    failed_size = 0;
    failed_count = 0;
    failing = 0;
    arm_min = min;
    keep_failing = (m == FROM_ONE_ON);
    armed = 1;
  }
  int rows = 0;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) rows++;
  if (m == HEAP_LIMIT) {
    sqlite3_hard_heap_limit64(0);
    printf("    (the hard heap limit was memory_used + 1000 across every step; now %lld)\n",
           (long long)sqlite3_hard_heap_limit64(-1));
  } else if (m == ONE_ALLOCATION || m == FROM_ONE_ON) {
    int still = armed && !failing;
    armed = 0;
    failing = 0;
    if (still)
      printf("    (no allocation of at least %d bytes reached the allocator while it was armed)\n", min);
    else if (m == ONE_ALLOCATION)
      printf("    (one allocation failed, of %d bytes, and the allocator disarmed)\n", failed_size);
    else
      printf("    (the first allocation to fail was of %d bytes; %d failed in all, "
             "until the step returned)\n", failed_size, failed_count);
  }
  if (rows) printf("    rows: %d\n", rows);
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE\n");
  else print_failure("step", db, rc);
  int f = sqlite3_finalize(st);
  printf("    finalize: rc %d\n", f);
  return rc;
}

static int run(sqlite3 *db, const char *sql) { return run_by(db, sql, PLAIN, 0); }

static sqlite3 *db, *db2;

/* begin_case: a fresh file set up as the header says, a second connection
 * to it, then BEGIN and the marker. EXTRA is more setup, committed first. */
static void begin_case(const char *id, const char *title, const char *extra) {
  char name[64];
  snprintf(name, sizeof name, "%s.db", id);
  printf("\n%s. %s\n", id, title);
  db = open_at(name);
  db2 = open_at(name);
  must(db, "CREATE TABLE t(x); CREATE TABLE b(x); CREATE TABLE bn(x NOT NULL); CREATE TABLE src(x); "
           "INSERT INTO src SELECT replace(hex(zeroblob(1500)), '0', 'a') FROM "
           "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10) SELECT i FROM n);");
  if (extra) must(db, extra);
  must(db, "BEGIN; INSERT INTO t VALUES ('marker');");
  printf("  BEGIN; INSERT INTO t VALUES ('marker')\n");
  state(db);
}

/* end_case: the state after the statement; COMMIT if still open; what db2
 * sees. */
static void end_case(void) {
  state(db);
  seen(db, "db");
  if (!sqlite3_get_autocommit(db)) { run(db, "COMMIT"); state(db); }
  seen(db2, "db2, after");
  close_db(db2);
  close_db(db);
}

static void nomem_case(const char *id, const char *title, const char *sql, enum method m, int min) {
  begin_case(id, title, NULL);
  run_by(db, sql, m, min);
  end_case();
}

static void full_case(const char *id, const char *sql) {
  char pragma[64];
  begin_case(id, "FULL, max_page_count set to the page count after the marker", NULL);
  long long n = one_int(db, "PRAGMA page_count");
  snprintf(pragma, sizeof pragma, "PRAGMA max_page_count = %lld", n);
  long long m = one_int(db, pragma);
  printf("  PRAGMA page_count answered %lld; %s answered %lld\n", n, pragma, m);
  run(db, sql);
  end_case();
}

/* The progress handler of the I cases: sqlite3_interrupt at its 50th call. */
static int progress_calls = 0;

static int on_progress(void *arg) {
  progress_calls++;
  if (progress_calls == 50) sqlite3_interrupt((sqlite3 *)arg);
  return 0;
}

static void interrupt_case(const char *id, const char *sql) {
  begin_case(id, "INTERRUPT: sqlite3_interrupt at the 50th progress callback, one per 100 opcodes", NULL);
  progress_calls = 0;
  sqlite3_progress_handler(db, 100, on_progress, db);
  run(db, sql);
  sqlite3_progress_handler(db, 0, NULL, NULL);
  printf("    (progress callbacks: %d)\n", progress_calls);
  end_case();
}

/* column_case: a statement stepped to a row; one column read, under the heap
 * limit when LIMITED; then sqlite3_reset and sqlite3_finalize, or
 * sqlite3_finalize alone. BIG binds 100,000 bytes of TEXT to ?1, with their
 * length. WIDE reads by sqlite3_column_text16, else sqlite3_column_text. */
static void column_case(const char *id, const char *title, const char *sql,
                        int big, int wide, int limited, int reset_first) {
  begin_case(id, title, NULL);
  sqlite3_stmt *st = NULL;
  printf("  sql: %s\n", sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK || st == NULL) { print_failure("prepare", db, rc); exit(2); }
  if (big) {
    char *text = malloc(100000);
    if (text == NULL) { fprintf(stderr, "malloc\n"); exit(2); }
    memset(text, 'b', 100000);
    rc = sqlite3_bind_text(st, 1, text, 100000, SQLITE_TRANSIENT);
    free(text);
    if (rc != SQLITE_OK) { print_failure("bind", db, rc); exit(2); }
    printf("    bound ?1: 100000 bytes of TEXT, with their length\n");
  }
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) { print_failure("step", db, rc); exit(2); }
  printf("    step: rc 100 ROW\n");
  state(db);
  if (limited) sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  const void *p = wide ? sqlite3_column_text16(st, 0) : (const void *)sqlite3_column_text(st, 0);
  if (limited) sqlite3_hard_heap_limit64(0);
  printf("    %s%s: %s; errcode %d, extended_errcode %d, errmsg \"%s\"\n",
         wide ? "sqlite3_column_text16" : "sqlite3_column_text",
         limited ? ", the heap limit at memory_used + 1000 around this one call" : ", no limit",
         p ? "a pointer" : "NULL", sqlite3_errcode(db), sqlite3_extended_errcode(db),
         sqlite3_errmsg(db));
  state(db);
  if (reset_first) {
    rc = sqlite3_reset(st);
    printf("    sqlite3_reset: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
           rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
    state(db);
  }
  rc = sqlite3_finalize(st);
  printf("    sqlite3_finalize: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
         rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  end_case();
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: txn-special DIR\n"); return 2; }
  dir = argv[1];
  install_wrapper();
  version_lines();

  const char *nomem_sql[] = {
    "SELECT randomblob(100000) FROM src LIMIT 1",
    "SELECT randomblob(100000)",
    "INSERT INTO b SELECT randomblob(100000) FROM src LIMIT 3",
    "INSERT INTO b VALUES (randomblob(100000))",
  };
  for (int i = 0; i < 4; i++) {
    char id[8];
    snprintf(id, sizeof id, "N%d", i + 1);
    nomem_case(id, "NOMEM, the heap limit kept in force across the step", nomem_sql[i], HEAP_LIMIT, 0);
  }
  for (int i = 0; i < 4; i++) {
    char id[8];
    snprintf(id, sizeof id, "M%d", i + 1);
    nomem_case(id, "NOMEM, exactly one allocation failing: the first after arming", nomem_sql[i],
               ONE_ALLOCATION, 0);
  }
  nomem_case("M5", "NOMEM, exactly one allocation failing: the first of at least 100,000 bytes",
             nomem_sql[2], ONE_ALLOCATION, 100000);
  nomem_case("M6", "NOMEM, the first allocation of at least 100,000 bytes failing, "
             "and every allocation after it until the step returns",
             nomem_sql[2], FROM_ONE_ON, 100000);

  const char *full_sql[] = {
    "INSERT INTO b SELECT x FROM src",
    "INSERT INTO b SELECT lower(x) FROM src",
    "INSERT INTO bn SELECT x FROM src",
    "INSERT INTO b SELECT zeroblob(3000) FROM src",
    "INSERT INTO b VALUES (zeroblob(100000))",
    "UPDATE src SET x = x || x",
    "UPDATE src SET x = lower(x || x)",
    "UPDATE src SET x = zeroblob(9000)",
  };
  for (int i = 0; i < 8; i++) {
    char id[8];
    snprintf(id, sizeof id, "F%d", i + 1);
    full_case(id, full_sql[i]);
  }

  const char *interrupt_sql[] = {
    "INSERT INTO b WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 1000000) "
    "SELECT i FROM c",
    "INSERT INTO b WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 1000000) "
    "SELECT abs(i) FROM c",
    "WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 1000000) "
    "SELECT count(*) FROM c, src",
    "WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 1000000) "
    "SELECT count(*) FROM c",
  };
  for (int i = 0; i < 4; i++) {
    char id[8];
    snprintf(id, sizeof id, "I%d", i + 1);
    interrupt_case(id, interrupt_sql[i]);
  }

  column_case("G1", "A column read with no limit: the control", "SELECT hex(x) FROM src", 0, 1, 0, 1);
  column_case("G2", "A column read's NOMEM, a SELECT reading a table, then reset",
              "SELECT hex(x) FROM src", 0, 1, 1, 1);
  column_case("G3", "A column read's NOMEM, a SELECT reading a table, then finalize alone",
              "SELECT hex(x) FROM src", 0, 1, 1, 0);
  column_case("G4", "A column read's NOMEM, a SELECT reading no table, then reset",
              "SELECT ?1", 1, 0, 1, 1);
  column_case("G5", "A column read's NOMEM, a SELECT reading no table, then finalize alone",
              "SELECT ?1", 1, 0, 1, 0);
  column_case("G6", "A column read's NOMEM by sqlite3_column_text16, a SELECT reading no table, then reset",
              "SELECT ?1", 1, 1, 1, 1);

  begin_case("L1", "INSERT OR ROLLBACK ends the transaction; the writes after it",
             "CREATE TABLE u(x UNIQUE); INSERT INTO u VALUES (1);");
  run(db, "INSERT OR ROLLBACK INTO u VALUES (1)");
  state(db);
  run(db, "INSERT INTO t VALUES ('after 1')");
  state(db);
  seen(db2, "db2, at once");
  run(db, "INSERT INTO t VALUES ('after 2')");
  state(db);
  seen(db2, "db2, at once");
  run(db, "COMMIT");
  end_case();

  return 0;
}
