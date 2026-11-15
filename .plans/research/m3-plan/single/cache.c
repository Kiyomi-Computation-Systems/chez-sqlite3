/* B4: what a statement cache rests on.
 *
 *   cache DIR       DIR: a fresh directory for this run's databases
 *
 *   K1  sqlite3_prepare_v3 with and without SQLITE_PREPARE_PERSISTENT:
 *       sqlite3_db_status and sqlite3_memory_used while holding 50 statements
 *   K2  a prepared statement held across a schema change, made by the same
 *       connection and by a second one: CREATE INDEX, ADD COLUMN under a held
 *       SELECT *, DROP TABLE, DROP COLUMN, a held INSERT; and the legacy
 *       sqlite3_prepare for contrast
 *   K3  sqlite3_stmt_busy, sqlite3_stmt_readonly and sqlite3_stmt_isexplain at
 *       each state
 *   K4  sqlite3_sql against sqlite3_expanded_sql
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;

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
  if (strcmp(name, ":memory:") == 0) snprintf(path, sizeof path, "%s", name);
  else snprintf(path, sizeof path, "%s/%s", dir, name);
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
  case 8: return "READONLY"; case 13: return "FULL"; case 17: return "SCHEMA";
  case 19: return "CONSTRAINT"; case 21: return "MISUSE"; case 25: return "RANGE";
  case 100: return "ROW"; case 101: return "DONE";
  default: return "?";
  }
}

static void print_value(sqlite3_stmt *st, int i) {
  switch (sqlite3_column_type(st, i)) {
  case SQLITE_INTEGER: printf("%lld", (long long)sqlite3_column_int64(st, i)); break;
  case SQLITE_FLOAT: printf("%.17g", sqlite3_column_double(st, i)); break;
  case SQLITE_TEXT: printf("'%s'", (const char *)sqlite3_column_text(st, i)); break;
  case SQLITE_BLOB: printf("blob(%d)", sqlite3_column_bytes(st, i)); break;
  default: printf("NULL"); break;
  }
}

/* run: one statement, stepped to the end, on db. */
static int run(sqlite3 *db, const char *who, const char *sql) {
  sqlite3_stmt *st = NULL;
  printf("  %s: %s\n", who, sql);
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) {
    printf("    prepare: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
           rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
    return rc;
  }
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  if (rc == SQLITE_DONE) printf("    step: rc 101 DONE\n");
  else printf("    step: rc %d %s, extended_errcode %d, errmsg \"%s\"\n",
              rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  sqlite3_finalize(st);
  return rc;
}

/* show: what a held statement reports, without stepping it. */
static void show(sqlite3_stmt *st, const char *label) {
  int n = sqlite3_column_count(st);
  printf("    %s: column_count %d (", label, n);
  for (int i = 0; i < n; i++) printf("%s%s", i ? " " : "", sqlite3_column_name(st, i));
  printf("), reprepares %d\n", sqlite3_stmt_status(st, SQLITE_STMTSTATUS_REPREPARE, 0));
}

static int step_show(sqlite3_stmt *st, sqlite3 *db, const char *label) {
  int rc = sqlite3_step(st);
  printf("    %s: step rc %d %s", label, rc, code_name(rc));
  if (rc == SQLITE_ROW) {
    printf(", row");
    for (int i = 0; i < sqlite3_column_count(st); i++) { printf(" "); print_value(st, i); }
  } else if (rc != SQLITE_DONE) {
    printf(", extended_errcode %d, errmsg \"%s\"", sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  }
  printf("\n");
  return rc;
}

static sqlite3_stmt *hold(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "prepare %s: %d %s\n", sql, rc, sqlite3_errmsg(db)); exit(2); }
  printf("  held (prepare_v3, PERSISTENT): %s\n", sql);
  return st;
}

/* -------------------------------------------------------------------- K1 */

static void status_line(sqlite3 *db, const char *label, sqlite3_int64 mem0) {
  int lu_cur, lu_hi, su_cur, su_hi, hit_cur, hit, msz_cur, msz, mfull_cur, mfull;
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_USED, &lu_cur, &lu_hi, 0);
  sqlite3_db_status(db, SQLITE_DBSTATUS_STMT_USED, &su_cur, &su_hi, 0);
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_HIT, &hit_cur, &hit, 0);
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE, &msz_cur, &msz, 0);
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL, &mfull_cur, &mfull, 0);
  printf("    %-26s lookaside_used %4d (high %4d), stmt_used %7d, lookaside hit %5d,"
         " miss_size %4d, miss_full %4d, memory_used +%lld\n",
         label, lu_cur, lu_hi, su_cur, hit, msz, mfull,
         (long long)(sqlite3_memory_used() - mem0));
}

#define K1_N 50

static void k1_one(unsigned int flags, const char *title) {
  sqlite3_stmt *held[K1_N];
  printf("\n K1. %s\n", title);
  sqlite3 *db = open_at(":memory:");
  must(db, "CREATE TABLE t(x INTEGER PRIMARY KEY, y TEXT); INSERT INTO t VALUES (1, 'one');"
           "SELECT * FROM t;");
  sqlite3_int64 mem0 = sqlite3_memory_used();
  status_line(db, "before", mem0);
  long long stmt_mem = 0;
  for (int i = 0; i < K1_N; i++) {
    int rc = sqlite3_prepare_v3(db, "SELECT x, y FROM t WHERE x = ?1", -1, flags, &held[i], NULL);
    if (rc != SQLITE_OK) { fprintf(stderr, "prepare: %d\n", rc); exit(2); }
    if (i == 0) status_line(db, "holding 1", mem0);
    if (i == 9) status_line(db, "holding 10", mem0);
  }
  status_line(db, "holding 50", mem0);
  for (int i = 0; i < K1_N; i++) stmt_mem += sqlite3_stmt_status(held[i], SQLITE_STMTSTATUS_MEMUSED, 0);
  printf("    sum of SQLITE_STMTSTATUS_MEMUSED over the 50: %lld\n", stmt_mem);
  for (int i = 0; i < K1_N; i++) {
    sqlite3_bind_int64(held[i], 1, 1);
    int rc = sqlite3_step(held[i]);
    if (rc != SQLITE_ROW) printf("    step %d: rc %d\n", i, rc);
  }
  status_line(db, "50 stepped once", mem0);
  for (int i = 0; i < K1_N; i++) sqlite3_reset(held[i]);
  status_line(db, "50 reset", mem0);
  for (int i = 0; i < K1_N; i++) sqlite3_finalize(held[i]);
  status_line(db, "50 finalized", mem0);
  close_db(db);
}

static void k1(void) {
  printf("\nK1. prepare_v3 with and without SQLITE_PREPARE_PERSISTENT (each on a fresh :memory: connection)\n");
  k1_one(0, "flags 0");
  k1_one(SQLITE_PREPARE_PERSISTENT, "flags SQLITE_PREPARE_PERSISTENT");
  k1_one(0, "flags 0, again");
}

/* -------------------------------------------------------------------- K2 */

static void k2(void) {
  sqlite3_stmt *st;
  printf("\nK2. A prepared statement held across a schema change\n");
  sqlite3 *a = open_at("k2.db");
  sqlite3 *b = open_at("k2.db");
  for (int i = 1; i <= 10; i++) {
    char sql[160];
    snprintf(sql, sizeof sql, "CREATE TABLE t%d(a, b); INSERT INTO t%d VALUES (1, 'one'), (2, 'two');", i, i);
    must(a, sql);
  }

  printf("\n K2.1 Same connection: CREATE INDEX under a held SELECT, bound, never stepped\n");
  st = hold(a, "SELECT * FROM t1 WHERE a = ?1");
  sqlite3_bind_int64(st, 1, 2);
  show(st, "before");
  run(a, "a", "CREATE INDEX t1a ON t1(a)");
  show(st, "after the DDL, before a step");
  step_show(st, a, "step 1");
  show(st, "after step 1");
  { char *e = sqlite3_expanded_sql(st); printf("    expanded_sql: %s\n", e ? e : "(NULL)"); sqlite3_free(e); }
  sqlite3_finalize(st);

  printf("\n K2.2 Same connection: ADD COLUMN under a held SELECT *, run once and reset\n");
  st = hold(a, "SELECT * FROM t2");
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  show(st, "before");
  run(a, "a", "ALTER TABLE t2 ADD COLUMN c DEFAULT 'cee'");
  show(st, "after the DDL, before a step");
  step_show(st, a, "step 1");
  show(st, "after step 1");
  sqlite3_finalize(st);

  printf("\n K2.3 Same connection: ADD COLUMN while the held SELECT * has a row ready\n");
  st = hold(a, "SELECT * FROM t3");
  step_show(st, a, "step 1");
  run(a, "a", "ALTER TABLE t3 ADD COLUMN c DEFAULT 'cee'");
  show(st, "after the DDL");
  step_show(st, a, "step 2");
  step_show(st, a, "step 3");
  sqlite3_reset(st);
  step_show(st, a, "step 1 after reset");
  show(st, "after it");
  sqlite3_finalize(st);

  printf("\n K2.4 Same connection: DROP TABLE under a held SELECT, reset\n");
  st = hold(a, "SELECT * FROM t4");
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(a, "a", "DROP TABLE t4");
  show(st, "after the DDL, before a step");
  step_show(st, a, "step 1");
  show(st, "after the step");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  run(a, "a", "CREATE TABLE t4(a, b, c); INSERT INTO t4 VALUES (7, 8, 9)");
  run(a, "a", "INSERT INTO t4 VALUES (7, 8, 9)");
  step_show(st, a, "step 1 after the table is made again");
  show(st, "after it");
  printf("    finalize: rc %d\n", sqlite3_finalize(st));

  printf("\n K2.5 Same connection: DROP TABLE while a held SELECT on it has a row ready\n");
  st = hold(a, "SELECT * FROM t5");
  step_show(st, a, "step 1");
  run(a, "a", "DROP TABLE t5");
  step_show(st, a, "step 2");
  sqlite3_reset(st);
  run(a, "a", "DROP TABLE t5");
  sqlite3_finalize(st);

  printf("\n K2.6 Second connection: CREATE INDEX under a held SELECT\n");
  st = hold(a, "SELECT * FROM t6 WHERE a = ?1");
  sqlite3_bind_int64(st, 1, 1);
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(b, "b", "CREATE INDEX t6a ON t6(a)");
  show(st, "after b's DDL, before a step");
  step_show(st, a, "step 1");
  show(st, "after it");
  sqlite3_finalize(st);

  printf("\n K2.7 Second connection: ADD COLUMN under a held SELECT *, run once and reset\n");
  st = hold(a, "SELECT * FROM t7");
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(b, "b", "ALTER TABLE t7 ADD COLUMN c DEFAULT 'cee'");
  show(st, "after b's DDL, before a step");
  step_show(st, a, "step 1");
  show(st, "after it");
  sqlite3_finalize(st);

  printf("\n K2.8 Second connection: DROP TABLE under a held SELECT; then the table made again\n");
  st = hold(a, "SELECT * FROM t8");
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(b, "b", "DROP TABLE t8");
  step_show(st, a, "step 1");
  show(st, "after it");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  step_show(st, a, "step 1 again");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  run(b, "b", "CREATE TABLE t8(x)");
  run(b, "b", "INSERT INTO t8 VALUES ('new')");
  step_show(st, a, "step 1 after b made it again");
  show(st, "after it");
  printf("    finalize: rc %d\n", sqlite3_finalize(st));

  printf("\n K2.9 Second connection: DROP COLUMN under a held SELECT that names it\n");
  st = hold(a, "SELECT a, b FROM t9");
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(b, "b", "ALTER TABLE t9 DROP COLUMN b");
  step_show(st, a, "step 1");
  show(st, "after it");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  printf("    finalize: rc %d\n", sqlite3_finalize(st));

  printf("\n K2.10 Second connection: changes under a held INSERT\n");
  st = hold(a, "INSERT INTO t10 VALUES (?1, ?2)");
  sqlite3_bind_int64(st, 1, 3);
  sqlite3_bind_text(st, 2, "three", -1, SQLITE_TRANSIENT);
  step_show(st, a, "step 1");
  sqlite3_reset(st);
  run(b, "b", "ALTER TABLE t10 ADD COLUMN c DEFAULT 'cee'");
  step_show(st, a, "step 1 after b added a column");
  sqlite3_reset(st);
  run(b, "b", "DROP TABLE t10");
  run(b, "b", "CREATE TABLE t10(a, b, c, d)");
  step_show(st, a, "step 1 after b made t10 with 4 columns");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  run(a, "a", "SELECT count(*) FROM t10");
  step_show(st, a, "step 1 after a's own SELECT on t10");
  printf("    reset: rc %d\n", sqlite3_reset(st));
  sqlite3_finalize(st);

  printf("\n K2.11 The legacy sqlite3_prepare, for contrast: second connection adds a column\n");
  must(a, "CREATE TABLE t11(a); INSERT INTO t11 VALUES (1);");
  {
    int rc = sqlite3_prepare(a, "SELECT * FROM t11", -1, &st, NULL);
    printf("  held (legacy sqlite3_prepare): SELECT * FROM t11, rc %d\n", rc);
    step_show(st, a, "step 1");
    sqlite3_reset(st);
    run(b, "b", "ALTER TABLE t11 ADD COLUMN c");
    step_show(st, a, "step 1");
    int r = sqlite3_reset(st);
    printf("    reset: rc %d %s, then extended_errcode %d, errmsg \"%s\"\n",
           r, code_name(r), sqlite3_extended_errcode(a), sqlite3_errmsg(a));
    step_show(st, a, "step 1 again");
    show(st, "after it");
    sqlite3_finalize(st);
  }

  printf("\n K2.12 prepare_v2 against prepare_v3 PERSISTENT: second connection adds a column\n");
  must(a, "CREATE TABLE t12(a); INSERT INTO t12 VALUES (1);");
  {
    sqlite3_stmt *v2 = NULL, *v3 = NULL;
    sqlite3_prepare_v2(a, "SELECT * FROM t12", -1, &v2, NULL);
    sqlite3_prepare_v3(a, "SELECT * FROM t12", -1, SQLITE_PREPARE_PERSISTENT, &v3, NULL);
    run(b, "b", "ALTER TABLE t12 ADD COLUMN c");
    step_show(v2, a, "prepare_v2's step 1");
    show(v2, "prepare_v2's, after it");
    step_show(v3, a, "prepare_v3's step 1");
    show(v3, "prepare_v3's, after it");
    sqlite3_finalize(v2);
    sqlite3_finalize(v3);
  }

  close_db(b);
  close_db(a);
}

/* -------------------------------------------------------------------- K3 */

struct k3_case { const char *pre; const char *sql; const char *post; };

static void k3(void) {
  printf("\nK3. stmt_readonly, stmt_isexplain and stmt_busy at each state\n");
  printf("  (busy: prepared / after step 1 / after the last step / after reset)\n");
  sqlite3 *db = open_at("k3.db");
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3); CREATE TABLE u(x UNIQUE); INSERT INTO u VALUES (1);");
  const struct k3_case cases[] = {
    {NULL, "SELECT x FROM t", NULL},
    {NULL, "SELECT x FROM t WHERE x = 99", NULL},
    {NULL, "SELECT 1", NULL},
    {NULL, "SELECT changes()", NULL},
    {NULL, "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT i FROM n", NULL},
    {NULL, "INSERT INTO t VALUES (9)", NULL},
    {NULL, "INSERT INTO t VALUES (10) RETURNING x", NULL},
    {NULL, "UPDATE t SET x = x RETURNING x", NULL},
    {NULL, "DELETE FROM t WHERE x > 8", NULL},
    {NULL, "INSERT INTO u VALUES (1)", NULL},
    {NULL, "BEGIN", "ROLLBACK"},
    {"BEGIN", "COMMIT", NULL},
    {"BEGIN", "ROLLBACK", NULL},
    {NULL, "SAVEPOINT s", "RELEASE s"},
    {"SAVEPOINT s", "RELEASE s", NULL},
    {"SAVEPOINT s", "ROLLBACK TO s", "RELEASE s"},
    {NULL, "PRAGMA user_version", NULL},
    {NULL, "PRAGMA user_version = 3", NULL},
    {NULL, "PRAGMA foreign_keys = ON", NULL},
    {NULL, "PRAGMA foreign_keys", NULL},
    {NULL, "PRAGMA journal_mode", NULL},
    {NULL, "PRAGMA journal_mode = DELETE", NULL},
    {NULL, "PRAGMA busy_timeout = 10", NULL},
    {NULL, "PRAGMA cache_size = 100", NULL},
    {NULL, "PRAGMA table_info(t)", NULL},
    {NULL, "CREATE TABLE z(x)", NULL},
    {NULL, "DROP TABLE z", NULL},
    {NULL, "CREATE TEMP TABLE tz(x)", NULL},
    {NULL, "INSERT INTO tz VALUES (1)", NULL},
    {NULL, "EXPLAIN SELECT 1", NULL},
    {NULL, "EXPLAIN INSERT INTO t VALUES (1)", NULL},
    {NULL, "EXPLAIN QUERY PLAN SELECT x FROM t", NULL},
    {NULL, "ATTACH ':memory:' AS aux", "DETACH aux"},
    {"ATTACH ':memory:' AS aux", "DETACH aux", NULL},
    {NULL, "ANALYZE", NULL},
    {NULL, "VACUUM", NULL},
    {NULL, "REINDEX", NULL},
  };
  int n = (int)(sizeof cases / sizeof cases[0]);
  for (int i = 0; i < n; i++) {
    sqlite3_stmt *st = NULL;
    if (cases[i].pre) must(db, cases[i].pre);
    int rc = sqlite3_prepare_v2(db, cases[i].sql, -1, &st, NULL);
    if (rc != SQLITE_OK) { printf("  %s: prepare rc %d %s\n", cases[i].sql, rc, sqlite3_errmsg(db)); continue; }
    int ro = sqlite3_stmt_readonly(st), ex = sqlite3_stmt_isexplain(st);
    int b0 = sqlite3_stmt_busy(st);
    int r1 = sqlite3_step(st);
    int b1 = sqlite3_stmt_busy(st);
    int rows = r1 == SQLITE_ROW;
    int rl = r1;
    while (rl == SQLITE_ROW) { rl = sqlite3_step(st); if (rl == SQLITE_ROW) rows++; }
    int bl = sqlite3_stmt_busy(st);
    int rr = sqlite3_reset(st);
    int br = sqlite3_stmt_busy(st);
    sqlite3_finalize(st);
    if (cases[i].post) must(db, cases[i].post);
    printf("  %-60s readonly %d, isexplain %d; busy %d/%d/%d/%d; step 1 rc %d, last rc %d, rows %d, reset rc %d\n",
           cases[i].sql, ro, ex, b0, b1, bl, br, r1, rl, rows, rr);
  }
  close_db(db);
}

/* -------------------------------------------------------------------- K4 */

static void show_sql(sqlite3_stmt *st, const char *label) {
  char *e = sqlite3_expanded_sql(st);
  printf("    %s\n      sql:          [%s]\n      expanded_sql: [%s]\n", label,
         sqlite3_sql(st), e ? e : "(NULL)");
  sqlite3_free(e);
}

static void k4(void) {
  sqlite3_stmt *st;
  printf("\nK4. sqlite3_sql against sqlite3_expanded_sql\n");
  sqlite3 *db = open_at(":memory:");

  printf("\n K4.1 Every kind of value, and a parameter left unbound\n");
  sqlite3_prepare_v2(db, "SELECT ?1, ?2, :n, @m, $d, ?", -1, &st, NULL);
  show_sql(st, "before any bind");
  sqlite3_bind_int64(st, 1, 42);
  sqlite3_bind_double(st, 2, 1.5);
  sqlite3_bind_text(st, 3, "it's", -1, SQLITE_TRANSIENT);
  sqlite3_bind_blob(st, 4, "\x00\xff", 2, SQLITE_TRANSIENT);
  sqlite3_bind_null(st, 5);
  show_sql(st, "bound 42, 1.5, 'it''s', x'00ff', NULL; the sixth unbound");
  sqlite3_step(st);
  show_sql(st, "after a step");
  sqlite3_reset(st);
  show_sql(st, "after reset");
  sqlite3_clear_bindings(st);
  show_sql(st, "after clear_bindings");
  sqlite3_finalize(st);

  printf("\n K4.2 Whitespace, a comment, and a tail\n");
  sqlite3_prepare_v2(db, "  SELECT 1 /* c */ ;  SELECT 2", -1, &st, NULL);
  show_sql(st, "prepared from \"  SELECT 1 /* c */ ;  SELECT 2\"");
  sqlite3_finalize(st);
  sqlite3_prepare_v2(db, "SELECT 'a''b', \"x\" -- tail comment\n", -1, &st, NULL);
  show_sql(st, "prepared from \"SELECT 'a''b', \\\"x\\\" -- tail comment\\n\"");
  sqlite3_finalize(st);

  printf("\n K4.3 Reals\n");
  {
    const double reals[] = {0.1, -0.0, 1e100, 1.0, 100.0, 12345678901234567890.0, 1.0 / 3.0};
    for (int i = 0; i < (int)(sizeof reals / sizeof reals[0]); i++) {
      char label[64];
      sqlite3_prepare_v2(db, "SELECT ?", -1, &st, NULL);
      sqlite3_bind_double(st, 1, reals[i]);
      snprintf(label, sizeof label, "bound %.17g", reals[i]);
      show_sql(st, label);
      sqlite3_finalize(st);
    }
    sqlite3_prepare_v2(db, "SELECT ?, ?", -1, &st, NULL);
    sqlite3_bind_double(st, 1, 1e308 * 10.0);
    sqlite3_bind_double(st, 2, -1e308 * 10.0);
    show_sql(st, "bound +inf and -inf");
    sqlite3_finalize(st);
  }

  printf("\n K4.4 Integers and text\n");
  sqlite3_prepare_v2(db, "SELECT ?, ?, ?, ?, ?", -1, &st, NULL);
  sqlite3_bind_int64(st, 1, (sqlite3_int64)(-9223372036854775807LL - 1));
  sqlite3_bind_text(st, 2, "line1\nline2", -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(st, 3, "\xc3\xa9", -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(st, 4, "a\0b", 3, SQLITE_TRANSIENT);
  sqlite3_bind_text(st, 5, "\xff\x41", 2, SQLITE_TRANSIENT);
  show_sql(st, "bound -2^63, 'line1\\nline2', U+00E9, 'a' NUL 'b' (3 bytes), bytes FF 41");
  sqlite3_finalize(st);

  printf("\n K4.5 A parameter used twice, and numbered out of order\n");
  sqlite3_prepare_v2(db, "SELECT ?1 + ?1, ?3, ?2", -1, &st, NULL);
  sqlite3_bind_int64(st, 1, 5);
  sqlite3_bind_int64(st, 2, 6);
  sqlite3_bind_int64(st, 3, 7);
  show_sql(st, "bound 5, 6, 7");
  sqlite3_finalize(st);

  printf("\n K4.6 Over SQLITE_LIMIT_LENGTH\n");
  {
    char big[201];
    memset(big, 'x', 200); big[200] = 0;
    int was = sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 100);
    printf("    limit was %d, now %d\n", was, sqlite3_limit(db, SQLITE_LIMIT_LENGTH, -1));
    sqlite3_prepare_v2(db, "SELECT ?", -1, &st, NULL);
    sqlite3_bind_text(st, 1, big, 90, SQLITE_TRANSIENT);
    show_sql(st, "bound 90 bytes: the expanded text is 99 bytes");
    sqlite3_finalize(st);
    sqlite3_prepare_v2(db, "SELECT ?", -1, &st, NULL);
    sqlite3_bind_text(st, 1, big, 95, SQLITE_TRANSIENT);
    show_sql(st, "bound 95 bytes: the expanded text would be 104 bytes");
    sqlite3_finalize(st);
    sqlite3_limit(db, SQLITE_LIMIT_LENGTH, was);
  }
  close_db(db);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: cache DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  k1();
  k2();
  k3();
  k4();
  return 0;
}
