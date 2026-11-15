/* Traps: behaviours that would mislead a builder, each in a minimal form,
 * reproduced twice in a run, each time on a fresh database file.
 *
 *   traps DIR       DIR: a fresh directory for this run's databases
 *
 *   T1  a BEGIN IMMEDIATE or BEGIN EXCLUSIVE refused inside a transaction
 *       still takes its lock
 *   T2  after ROLLBACK, an open SELECT keeps answering rows, rolled-back ones
 *       among them
 *   T3  COMMIT answers SQLITE_BUSY with no other connection, while a write
 *       statement of its own is unfinished
 *   T4  PRAGMA foreign_keys = <an unrecognised word> turns foreign keys off,
 *       and a misspelled PRAGMA name does nothing; neither is an error
 *   T5  inside a transaction, PRAGMA foreign_keys does nothing and says
 *       nothing; journal_mode=WAL fails before the transaction has written,
 *       and does nothing, saying nothing, after
 *   T6  a statement whose re-prepare failed reports a stale schema
 *   T7  last_insert_rowid names a row that was rolled back
 *   T8  SQLITE_FULL ends the transaction, or undoes only the statement, by
 *       whether the statement calls a function: INSERT ... SELECT x against
 *       INSERT ... SELECT lower(x)
 *   T9  PRAGMA soft_heap_limit and hard_heap_limit are process-wide, and
 *       hard_heap_limit can't be raised or cleared through the PRAGMA
 *   T10 sqlite3_exec's error offset counts from the failing statement
 *   T11 sqlite3_stmt_busy stays 1 after an EXPLAIN answers DONE
 *   T12 a NOMEM caused by a heap limit left in force across the step ends
 *       the transaction where the same failing allocation alone undoes only
 *       the statement
 *   T13 a column read's NOMEM ends the transaction at the statement's reset
 *
 * T12 fails one allocation through an SQLITE_CONFIG_MALLOC wrapper, installed
 * before anything else; it passes every other call through.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;
static int file_number = 0;

/* The allocator wrapper: while armed, the first xMalloc or xRealloc of at
 * least arm_min bytes fails, and the wrapper disarms itself. */
static sqlite3_mem_methods real;
static int armed = 0, arm_min = 0, failed_size = 0;

static void *w_malloc(int n) {
  if (armed && n >= arm_min) { armed = 0; failed_size = n; return NULL; }
  return real.xMalloc(n);
}

static void *w_realloc(void *p, int n) {
  if (armed && n >= arm_min) { armed = 0; failed_size = n; return NULL; }
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

static sqlite3 *open_named(const char *name) {
  char path[4096];
  sqlite3 *db = NULL;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open %s: rc %d\n", name, rc); exit(2); }
  return db;
}

/* fresh: a new file name for this repetition; *name receives it. */
static sqlite3 *fresh(char *name, size_t size) {
  snprintf(name, size, "trap%02d.db", ++file_number);
  return open_named(name);
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

/* run: one statement to the end; prints its answer on one line. */
static int run(sqlite3 *db, const char *who, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  printf("    %s: %-44s", who, sql);
  if (rc != SQLITE_OK) { printf(" prepare rc %d \"%s\"\n", rc, sqlite3_errmsg(db)); return rc; }
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
    printf(" row");
    for (int i = 0; i < sqlite3_column_count(st); i++) {
      const unsigned char *t = sqlite3_column_text(st, i);
      printf(" %s", t ? (const char *)t : "NULL");
    }
    printf(";");
  }
  if (rc == SQLITE_DONE) printf(" DONE\n");
  else printf(" step rc %d \"%s\"\n", rc, sqlite3_errmsg(db));
  sqlite3_finalize(st);
  return rc;
}

static const char *txn_name(int s) {
  return s == SQLITE_TXN_NONE ? "NONE" : s == SQLITE_TXN_READ ? "READ" : s == SQLITE_TXN_WRITE ? "WRITE" : "-1";
}

static void state(sqlite3 *db) {
  printf("      autocommit %d, txn_state(main) %s\n",
         sqlite3_get_autocommit(db), txn_name(sqlite3_txn_state(db, "main")));
}

static int step_print(sqlite3_stmt *st, sqlite3 *db) {
  int rc = sqlite3_step(st);
  if (rc == SQLITE_ROW) printf(" %lld", (long long)sqlite3_column_int64(st, 0));
  else if (rc == SQLITE_DONE) printf(" DONE");
  else printf(" rc %d \"%s\"", rc, sqlite3_errmsg(db));
  return rc;
}

static void t1(int rep) {
  char name[32];
  printf("\n T1 rep %d: a BEGIN IMMEDIATE refused inside a transaction\n", rep);
  sqlite3 *a = fresh(name, sizeof name);
  sqlite3 *b = open_named(name);
  must(a, "CREATE TABLE t(x)");
  run(a, "a", "BEGIN");
  state(a);
  run(a, "a", "BEGIN IMMEDIATE");
  state(a);
  run(b, "b", "BEGIN IMMEDIATE");
  run(a, "a", "ROLLBACK");
  run(b, "b", "BEGIN IMMEDIATE");
  run(b, "b", "ROLLBACK");
  printf("  T1 rep %d: a BEGIN EXCLUSIVE refused inside a transaction\n", rep);
  run(a, "a", "BEGIN");
  run(a, "a", "BEGIN EXCLUSIVE");
  state(a);
  run(b, "b", "SELECT count(*) FROM t");
  run(a, "a", "ROLLBACK");
  run(b, "b", "SELECT count(*) FROM t");
  close_db(b);
  close_db(a);
}

static void t2(int rep) {
  char name[32];
  sqlite3_stmt *st;
  printf("\n T2 rep %d: an open SELECT, then ROLLBACK of a transaction that inserted 4 and 5\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3);");
  const char *selects[] = {"SELECT x FROM t ORDER BY x", "SELECT x FROM t"};
  for (int k = 0; k < 2; k++) {
    must(db, "BEGIN; INSERT INTO t VALUES (4), (5);");
    sqlite3_prepare_v2(db, selects[k], -1, &st, NULL);
    printf("    %s: step 1", selects[k]);
    step_print(st, db);
    must(db, "ROLLBACK");
    printf("; ROLLBACK; the next steps:");
    while (step_print(st, db) == SQLITE_ROW) {}
    printf("\n");
    sqlite3_finalize(st);
  }
  run(db, "db", "SELECT group_concat(x) FROM t");
  close_db(db);
}

static void t3(int rep) {
  char name[32];
  sqlite3_stmt *st;
  printf("\n T3 rep %d: COMMIT while an INSERT ... RETURNING of its own has answered one row\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  must(db, "CREATE TABLE t(x)");
  run(db, "db", "BEGIN");
  sqlite3_prepare_v2(db, "INSERT INTO t VALUES (1), (2) RETURNING x", -1, &st, NULL);
  printf("    db: INSERT INTO t VALUES (1), (2) RETURNING x, step 1:");
  step_print(st, db);
  printf("\n");
  run(db, "db", "COMMIT");
  printf("      extended_errcode %d\n", sqlite3_extended_errcode(db));
  run(db, "db", "COMMIT");
  state(db);
  sqlite3_reset(st);
  run(db, "db", "COMMIT");
  state(db);
  sqlite3_finalize(st);
  close_db(db);
}

static void t4(int rep) {
  char name[32];
  printf("\n T4 rep %d: an unrecognised word for foreign_keys, and a misspelled name\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  run(db, "db", "PRAGMA foreign_keys = ON");
  run(db, "db", "PRAGMA foreign_keys");
  run(db, "db", "PRAGMA foreign_keys = enable");
  run(db, "db", "PRAGMA foreign_keys");
  run(db, "db", "PRAGMA foreign_keys = ON");
  run(db, "db", "PRAGMA foreign_keys = DEFAULT");
  run(db, "db", "PRAGMA foreign_keys");
  run(db, "db", "PRAGMA foreign_key = ON");
  run(db, "db", "PRAGMA foreign_keys");
  close_db(db);
}

static void t5(int rep) {
  char name[32];
  printf("\n T5 rep %d: settings changed inside a transaction that hasn't written\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  must(db, "CREATE TABLE t(x)");
  run(db, "db", "BEGIN");
  run(db, "db", "PRAGMA foreign_keys = ON");
  run(db, "db", "PRAGMA journal_mode = WAL");
  run(db, "db", "PRAGMA synchronous = OFF");
  run(db, "db", "COMMIT");
  run(db, "db", "PRAGMA foreign_keys");
  run(db, "db", "PRAGMA journal_mode");
  printf("  T5 rep %d: the same, inside a transaction that has written\n", rep);
  run(db, "db", "BEGIN");
  run(db, "db", "INSERT INTO t VALUES (1)");
  run(db, "db", "PRAGMA foreign_keys = ON");
  run(db, "db", "PRAGMA journal_mode = WAL");
  run(db, "db", "PRAGMA synchronous = OFF");
  run(db, "db", "COMMIT");
  run(db, "db", "PRAGMA foreign_keys");
  run(db, "db", "PRAGMA journal_mode");
  close_db(db);
}

static void t6(int rep) {
  char name[32];
  sqlite3_stmt *st;
  printf("\n T6 rep %d: a held INSERT; b adds a column, then rebuilds the table with 4 columns\n", rep);
  sqlite3 *a = fresh(name, sizeof name);
  sqlite3 *b = open_named(name);
  must(a, "CREATE TABLE t(p, q)");
  sqlite3_prepare_v3(a, "INSERT INTO t VALUES (1, 2)", -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  printf("    a: held INSERT INTO t VALUES (1, 2), step:");
  step_print(st, a); sqlite3_reset(st); printf("\n");
  run(b, "b", "ALTER TABLE t ADD COLUMN r");
  printf("    a: the held INSERT, step:"); step_print(st, a); sqlite3_reset(st); printf("\n");
  run(b, "b", "DROP TABLE t");
  run(b, "b", "CREATE TABLE t(p, q, r, s)");
  printf("    a: the held INSERT, step:"); step_print(st, a); sqlite3_reset(st); printf("\n");
  printf("    a: the held INSERT, step:"); step_print(st, a); sqlite3_reset(st); printf("\n");
  run(a, "a", "SELECT count(*) FROM t");
  printf("    a: the held INSERT, step:"); step_print(st, a); sqlite3_reset(st); printf("\n");
  sqlite3_finalize(st);
  close_db(b);
  close_db(a);
}

static long long count_of(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  long long n = -1;
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW)
    n = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st);
  return n;
}

static void t7(int rep) {
  char name[32];
  printf("\n T7 rep %d: last_insert_rowid after rolled-back rows\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  must(db, "CREATE TABLE t(x UNIQUE); INSERT INTO t(rowid, x) VALUES (1, 1);");
  printf("      last_insert_rowid %lld\n", (long long)sqlite3_last_insert_rowid(db));
  run(db, "db", "INSERT INTO t(rowid, x) VALUES (50, 50), (51, 1)");
  long long r = sqlite3_last_insert_rowid(db);
  printf("      last_insert_rowid %lld; rows with rowid 50: %lld\n", r,
         count_of(db, "SELECT count(*) FROM t WHERE rowid = 50"));
  must(db, "BEGIN; INSERT INTO t(rowid, x) VALUES (60, 60); ROLLBACK;");
  r = sqlite3_last_insert_rowid(db);
  printf("      after BEGIN; INSERT rowid 60; ROLLBACK: last_insert_rowid %lld; rows with rowid 60: %lld\n", r,
         count_of(db, "SELECT count(*) FROM t WHERE rowid = 60"));
  close_db(db);
}

/* with_src: a fresh file holding t, b, and src of 10 rows of 3,000 bytes of
 * 'a', committed; then BEGIN and INSERT INTO t VALUES (10). */
static sqlite3 *with_src(char *name, size_t size) {
  sqlite3 *db = fresh(name, size);
  must(db, "CREATE TABLE t(x); CREATE TABLE b(x); CREATE TABLE src(x); "
           "INSERT INTO src SELECT replace(hex(zeroblob(1500)), '0', 'a') FROM "
           "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10) SELECT i FROM n);");
  must(db, "BEGIN; INSERT INTO t VALUES (10);");
  return db;
}

static void t8(int rep) {
  char name[32], pragma[64];
  printf("\n T8 rep %d: SQLITE_FULL inside a transaction, with and without a function call\n", rep);
  const char *inserts[] = {"INSERT INTO b SELECT x FROM src",
                           "INSERT INTO b SELECT lower(x) FROM src"};
  for (int k = 0; k < 2; k++) {
    sqlite3 *db = with_src(name, sizeof name);
    snprintf(pragma, sizeof pragma, "PRAGMA max_page_count = %lld", count_of(db, "PRAGMA page_count"));
    run(db, "db", pragma);
    run(db, "db", inserts[k]);
    state(db);
    run(db, "db", "SELECT count(*) FROM t");
    if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
    close_db(db);
  }
}

static void t9(int rep) {
  char name[32];
  printf("\n T9 rep %d: heap limits set through one connection's PRAGMA\n", rep);
  sqlite3 *a = fresh(name, sizeof name);
  sqlite3 *b = fresh(name, sizeof name);
  run(a, "a", "PRAGMA soft_heap_limit = 50000000");
  run(b, "b", "PRAGMA soft_heap_limit");
  run(a, "a", "PRAGMA hard_heap_limit = 60000000");
  run(b, "b", "PRAGMA hard_heap_limit");
  run(a, "a", "PRAGMA hard_heap_limit = 0");
  run(a, "a", "PRAGMA hard_heap_limit = 90000000");
  run(a, "a", "PRAGMA soft_heap_limit = 0");
  close_db(a);
  close_db(b);
  sqlite3_hard_heap_limit64(0);
  printf("    after both closed, and sqlite3_hard_heap_limit64(0): soft %lld, hard %lld\n",
         (long long)sqlite3_soft_heap_limit64(-1), (long long)sqlite3_hard_heap_limit64(-1));
}

static void t10(int rep) {
  char name[32];
  printf("\n T10 rep %d: sqlite3_exec's error offset for a syntax error at byte 27 of the script\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  must(db, "CREATE TABLE t(x)");
  const char *script = "INSERT INTO t VALUES (1);  SELEKT 1;";
  int rc = sqlite3_exec(db, script, NULL, NULL, NULL);
  printf("    exec rc %d, errmsg \"%s\", error_offset %d; the script's byte %d starts \"%.6s\"\n",
         rc, sqlite3_errmsg(db), sqlite3_error_offset(db), 27, script + 27);
  close_db(db);
}

static void t11(int rep) {
  char name[32];
  sqlite3_stmt *st;
  printf("\n T11 rep %d: sqlite3_stmt_busy after the last step\n", rep);
  sqlite3 *db = fresh(name, sizeof name);
  const char *sqls[] = {"SELECT 1", "EXPLAIN SELECT 1", "EXPLAIN QUERY PLAN SELECT 1"};
  for (int k = 0; k < 3; k++) {
    int rc, n = 0;
    sqlite3_prepare_v2(db, sqls[k], -1, &st, NULL);
    while ((rc = sqlite3_step(st)) == SQLITE_ROW) n++;
    int busy = sqlite3_stmt_busy(st);
    sqlite3_reset(st);
    printf("    %-28s %d rows, last step rc %d, then stmt_busy %d; after reset %d\n",
           sqls[k], n, rc, busy, sqlite3_stmt_busy(st));
    sqlite3_finalize(st);
  }
  close_db(db);
}

/* step_all: every step of ST; prints the last step's answer. */
static void step_all(sqlite3 *db, sqlite3_stmt *st) {
  int rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  if (rc == SQLITE_DONE) printf(" DONE");
  else printf(" step rc %d \"%s\"", rc, sqlite3_errmsg(db));
}

static void t12(int rep) {
  char name[32];
  const char *sql = "INSERT INTO b SELECT randomblob(100000) FROM src LIMIT 3";
  printf("\n T12 rep %d: NOMEM in a statement with a statement journal, by two methods\n", rep);
  for (int k = 0; k < 2; k++) {
    sqlite3 *db = with_src(name, sizeof name);
    sqlite3_stmt *st = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
    if (rc != SQLITE_OK) { printf("    prepare rc %d \"%s\"\n", rc, sqlite3_errmsg(db)); exit(2); }
    if (k == 0) {
      printf("    db: %s, the hard heap limit at memory_used + 1000 across the step:", sql);
      sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
      step_all(db, st);
      sqlite3_hard_heap_limit64(0);
      printf("\n");
    } else {
      printf("    db: %s, the first allocation of at least 100000 bytes failing, alone:", sql);
      arm_min = 100000;
      failed_size = 0;
      armed = 1;
      step_all(db, st);
      printf("; %s, of %d bytes\n", armed ? "none failed" : "one failed", failed_size);
      armed = 0;
    }
    printf("      finalize rc %d\n", sqlite3_finalize(st));
    state(db);
    run(db, "db", "SELECT count(*) FROM t");
    if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
    close_db(db);
  }
}

static void t13(int rep) {
  char name[32];
  sqlite3_stmt *st = NULL;
  printf("\n T13 rep %d: a column read's NOMEM, then reset\n", rep);
  sqlite3 *db = with_src(name, sizeof name);
  int rc = sqlite3_prepare_v2(db, "SELECT hex(x) FROM src", -1, &st, NULL);
  if (rc != SQLITE_OK) { printf("    prepare rc %d \"%s\"\n", rc, sqlite3_errmsg(db)); exit(2); }
  printf("    db: SELECT hex(x) FROM src, step 1:");
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) { printf(" rc %d\n", rc); exit(2); }
  printf(" ROW\n");
  sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  const void *p = sqlite3_column_text16(st, 0);
  sqlite3_hard_heap_limit64(0);
  printf("    sqlite3_column_text16 under the heap limit: %s, extended_errcode %d\n",
         p ? "a pointer" : "NULL", sqlite3_extended_errcode(db));
  state(db);
  printf("    sqlite3_reset: rc %d\n", sqlite3_reset(st));
  state(db);
  printf("    sqlite3_finalize: rc %d\n", sqlite3_finalize(st));
  run(db, "db", "SELECT count(*) FROM t");
  if (!sqlite3_get_autocommit(db)) must(db, "ROLLBACK");
  close_db(db);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: traps DIR\n"); return 2; }
  dir = argv[1];
  install_wrapper();
  version_lines();
  void (*traps[])(int) = {t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13};
  for (int i = 0; i < (int)(sizeof traps / sizeof traps[0]); i++) {
    printf("\nT%d\n", i + 1);
    traps[i](1);
    traps[i](2);
  }
  return 0;
}
