/* D1: sqlite3_db_config's four v1 options on a fresh connection, as an open
 * with settings would set them (the M4 plan, sections 4.1 and 8).
 *
 *   d1-db-config-open DIR TIMING
 *
 * DIR holds this run's files. TIMING receives every time this probe reads;
 * the main output holds no time, so two runs of it compare byte for byte.
 * Every connection opens as chez-sqlite3 opens one: READWRITE | CREATE |
 * EXRESCODE | FULLMUTEX (ADR-0010), unless a case says otherwise. Every call
 * goes through dbc(), the one shape v1 binds, (db op int int*), with its
 * cell set to a sentinel of the call's own first, -(1000 + n), so a cell
 * the call left shows as "untouched".
 *
 *   D1  whether a set expires the connection's other statements: a
 *       PERSISTENT SELECT, stepped to done and reset, then the set, then the
 *       SELECT stepped again with no prepare; its SQLITE_STMTSTATUS_REPREPARE
 *       count before and after. For each op: a change, the same value again,
 *       and a read (-1). The control runs nothing between.
 *  D1b  the same with the SELECT held at a row across the set.
 *   D2  what a re-prepare after a change does: a statement prepared with DQS
 *       on, then DQS_DML (or DQS_DDL) turned off, then reset and stepped.
 *   D3  the connection's error state around a refused call: errcode,
 *       extended errcode and errmsg after a failed statement, then after an
 *       unknown op (1999), then after a set that succeeds.
 *   D4  a set under another connection's EXCLUSIVE lock, with a 1500 ms busy
 *       timeout: its answer here, its time in TIMING.
 *   D5  each op's round trip on connections the open can make: :memory:, a
 *       file whose schema no statement has read, a READONLY open, NOMUTEX,
 *       inside a transaction, beside a statement held at a row.
 *   D6  onoff values v1 never passes: 2, -2.
 *
 * No call with a side effect stands beside another in one argument list:
 * each answer is read into a variable first (AGENTS.md).
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *dir;
static FILE *timing;
static int case_number;
static int call_number;

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
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static const struct { const char *name; int op; } ops[] = {
  {"ENABLE_LOAD_EXTENSION", SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION},
  {"DEFENSIVE", SQLITE_DBCONFIG_DEFENSIVE},
  {"DQS_DML", SQLITE_DBCONFIG_DQS_DML},
  {"DQS_DDL", SQLITE_DBCONFIG_DQS_DDL},
};
#define NOPS ((int)(sizeof ops / sizeof ops[0]))

static sqlite3 *open_flags(const char *name, int flags) {
  char path[4096];
  sqlite3 *db = NULL;
  if (strcmp(name, ":memory:") == 0)
    snprintf(path, sizeof path, "%s", name);
  else
    snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &db, flags, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open %s: rc %d\n", name, rc); exit(2); }
  return db;
}

static sqlite3 *open_at(const char *name) {
  return open_flags(name, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE
                    | SQLITE_OPEN_FULLMUTEX);
}

static void must(sqlite3 *db, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static void close_or_die(sqlite3 *db) {
  int c = sqlite3_close(db);
  if (c != SQLITE_OK) { fprintf(stderr, "close: %d\n", c); exit(2); }
}

/* dbc: one call of the v1 shape; writes the cell's text into OUT. */
static int dbc(sqlite3 *db, int op, int onoff, char *out, size_t n) {
  int sentinel = -(1000 + call_number++);
  int cell = sentinel;
  int rc = sqlite3_db_config(db, op, onoff, &cell);
  if (cell == sentinel) snprintf(out, n, "untouched");
  else snprintf(out, n, "%d", cell);
  return rc;
}

static int to_done(sqlite3_stmt *st) {
  int rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  return rc;
}

static int read_flag(sqlite3 *db, int op) {
  int cell = -7;
  int rc = sqlite3_db_config(db, op, -1, &cell);
  if (rc != SQLITE_OK || (cell != 0 && cell != 1)) {
    fprintf(stderr, "read of op %d: rc %d cell %d\n", op, rc, cell);
    exit(2);
  }
  return cell;
}

/* --- D1 ------------------------------------------------------------------ */

/* expire_case: S stepped to done and reset, then OP set to ONOFF (or nothing
   when OP is 0), then S stepped again. HELD: S is held at its first row
   across the set instead. FIRST, when not -2, sets OP to FIRST before S is
   prepared. */
static void expire_case(int op, int first, int onoff, int held, const char *label) {
  char file[64];
  char cell[32] = "-";
  snprintf(file, sizeof file, "d1-%d.db", case_number++);
  sqlite3 *db = open_at(file);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2)");
  if (op != 0 && first != -2) {
    char ignored[32];
    int f = dbc(db, op, first, ignored, sizeof ignored);
    if (f != SQLITE_OK) { fprintf(stderr, "first set: %d\n", f); exit(2); }
  }
  sqlite3_stmt *s = NULL;
  if (sqlite3_prepare_v3(db, "SELECT x FROM t", -1, SQLITE_PREPARE_PERSISTENT, &s, NULL)
      != SQLITE_OK) exit(2);
  int r1, z1 = -1;
  if (held) {
    r1 = sqlite3_step(s);
  } else {
    r1 = to_done(s);
    z1 = sqlite3_reset(s);
  }
  int set_rc = -1;
  if (op != 0) set_rc = dbc(db, op, onoff, cell, sizeof cell);
  int before = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int r2 = to_done(s);
  int after = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int z2 = sqlite3_reset(s);
  int r3 = to_done(s);
  int after2 = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int f = sqlite3_finalize(s);
  if (f != SQLITE_OK) { fprintf(stderr, "finalize %d\n", f); exit(2); }
  close_or_die(db);
  if (held)
    printf("  %-46s S at a row %d; set %d cell %s; S's reprepares %d, to done %d, then %d;"
           " reset %d, again %d, then %d\n", label, r1, set_rc, cell, before, r2, after, z2, r3,
           after2);
  else
    printf("  %-46s S %d, reset %d; set %d cell %s; S's reprepares %d, its second run %d,"
           " then %d\n", label, r1, z1, set_rc, cell, before, r2, after);
}

static void d1(int held) {
  char label[96];
  expire_case(0, -2, 0, held, "nothing (the control)");
  for (int i = 0; i < NOPS; i++) {
    /* Each op's start, read on a connection of its own. */
    sqlite3 *probe = open_at("d1-start.db");
    int start = read_flag(probe, ops[i].op);
    close_or_die(probe);
    snprintf(label, sizeof label, "%s %d -> %d, a change", ops[i].name, start, !start);
    expire_case(ops[i].op, -2, !start, held, label);
    snprintf(label, sizeof label, "%s %d -> %d, unchanged", ops[i].name, start, start);
    expire_case(ops[i].op, -2, start, held, label);
    snprintf(label, sizeof label, "%s read (-1)", ops[i].name);
    expire_case(ops[i].op, -2, -1, held, label);
  }
}

/* --- D2 ------------------------------------------------------------------ */

static void d2_case(int op, const char *setup, const char *sql, const char *label) {
  char file[64];
  char cell[32];
  snprintf(file, sizeof file, "d2-%d.db", case_number++);
  sqlite3 *db = open_at(file);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  if (setup) must(db, setup);
  sqlite3_stmt *s = NULL;
  int p = sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &s, NULL);
  if (p != SQLITE_OK) { fprintf(stderr, "d2 prepare %d: %s\n", p, sqlite3_errmsg(db)); exit(2); }
  int r1 = to_done(s);
  int z1 = sqlite3_reset(s);
  int set_rc = dbc(db, op, 0, cell, sizeof cell);
  int r2 = to_done(s);
  int e2 = sqlite3_extended_errcode(db);
  char msg[256];
  snprintf(msg, sizeof msg, "%s", sqlite3_errmsg(db));
  int after = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int z2 = sqlite3_reset(s);
  int f = sqlite3_finalize(s);
  close_or_die(db);
  printf("  %-40s first run %d, reset %d; set 0: %d cell %s; second run %d (extended %d, %s);"
         " reprepares %d; reset %d; finalize %d\n", label, r1, z1, set_rc, cell, r2, e2, msg,
         after, z2, f);
}

/* --- D3 ------------------------------------------------------------------ */

static void error_state(sqlite3 *db, const char *after) {
  printf("  after %-36s errcode %d, extended %d, errmsg \"%s\"\n", after, sqlite3_errcode(db),
         sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

static void d3(void) {
  char cell[32];
  sqlite3 *db = open_at(":memory:");
  error_state(db, "the open");
  sqlite3_stmt *s = NULL;
  int p = sqlite3_prepare_v2(db, "select nosuch", -1, &s, NULL);
  printf("  a failing prepare answered %d\n", p);
  error_state(db, "it");
  int u = dbc(db, 1999, 1, cell, sizeof cell);
  printf("  op 1999 answered %d, cell %s; sqlite3_errstr(%d) is \"%s\"\n", u, cell, u,
         sqlite3_errstr(u));
  error_state(db, "op 1999");
  int ok = dbc(db, SQLITE_DBCONFIG_DEFENSIVE, 1, cell, sizeof cell);
  printf("  DEFENSIVE 1 answered %d, cell %s\n", ok, cell);
  error_state(db, "DEFENSIVE 1");
  close_or_die(db);
  /* The same on a connection whose last call succeeded. */
  db = open_at(":memory:");
  must(db, "select 1");
  error_state(db, "a fresh open and select 1");
  u = dbc(db, 1999, 0, cell, sizeof cell);
  printf("  op 1999 answered %d, cell %s\n", u, cell);
  error_state(db, "op 1999");
  close_or_die(db);
}

/* --- D4 ------------------------------------------------------------------ */

static void d4(void) {
  char cell[32];
  sqlite3 *holder = open_at("d4.db");
  must(holder, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  must(holder, "PRAGMA journal_mode = delete");
  must(holder, "BEGIN EXCLUSIVE; INSERT INTO t VALUES (2)");
  sqlite3 *db = open_at("d4.db");
  must(db, "PRAGMA busy_timeout = 1500");
  for (int i = 0; i < NOPS; i++) {
    int vals[2] = {1, 0};
    for (int v = 0; v < 2; v++) {
      double t0 = now_ms();
      int rc = dbc(db, ops[i].op, vals[v], cell, sizeof cell);
      double t1 = now_ms();
      printf("  under EXCLUSIVE, busy_timeout 1500: %s %d answered %d, cell %s\n", ops[i].name,
             vals[v], rc, cell);
      fprintf(timing, "D4 %s %d: %.3f ms\n", ops[i].name, vals[v], t1 - t0);
    }
  }
  sqlite3_stmt *s = NULL;
  double t0 = now_ms();
  int p = sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &s, NULL);
  double t1 = now_ms();
  printf("  the control: a SELECT's prepare there answered %d (extended %d)\n", p,
         sqlite3_extended_errcode(db));
  fprintf(timing, "D4 control SELECT prepare: %.3f ms\n", t1 - t0);
  if (s) sqlite3_finalize(s);
  close_or_die(db);
  must(holder, "ROLLBACK");
  close_or_die(holder);
}

/* --- D5 ------------------------------------------------------------------ */

static void round_trip(sqlite3 *db, const char *where) {
  for (int i = 0; i < NOPS; i++) {
    char c0[32], c1[32], c2[32], c3[32];
    int start = read_flag(db, ops[i].op);
    int a = dbc(db, ops[i].op, !start, c0, sizeof c0);
    int b = dbc(db, ops[i].op, -1, c1, sizeof c1);
    int c = dbc(db, ops[i].op, start, c2, sizeof c2);
    int d = dbc(db, ops[i].op, -1, c3, sizeof c3);
    printf("  %-34s %-22s start %d; set %d: %d cell %s; read %d cell %s; set %d: %d cell %s;"
           " read %d cell %s\n", where, ops[i].name, start, !start, a, c0, b, c1, start, c, c2, d,
           c3);
  }
}

static void d5(void) {
  sqlite3 *db = open_at(":memory:");
  round_trip(db, ":memory:");
  close_or_die(db);

  sqlite3 *maker = open_at("d5.db");
  must(maker, "CREATE TABLE t(x); INSERT INTO t VALUES (1)");
  close_or_die(maker);

  db = open_at("d5.db");
  round_trip(db, "a file, schema unread");
  must(db, "SELECT x FROM t");
  close_or_die(db);

  db = open_flags("d5.db", SQLITE_OPEN_READONLY | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX);
  round_trip(db, "READONLY");
  close_or_die(db);

  db = open_flags("d5.db", SQLITE_OPEN_READWRITE | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_NOMUTEX);
  round_trip(db, "NOMUTEX");
  close_or_die(db);

  db = open_at("d5.db");
  must(db, "BEGIN; INSERT INTO t VALUES (2)");
  round_trip(db, "inside a transaction that wrote");
  must(db, "ROLLBACK");
  close_or_die(db);

  db = open_at("d5.db");
  sqlite3_stmt *s = NULL;
  if (sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &s, NULL) != SQLITE_OK) exit(2);
  int r = sqlite3_step(s);
  printf("  (a SELECT stepped: %d)\n", r);
  round_trip(db, "beside a statement at a row");
  sqlite3_finalize(s);
  close_or_die(db);
}

/* --- D6 ------------------------------------------------------------------ */

static void d6(void) {
  sqlite3 *db = open_at(":memory:");
  for (int i = 0; i < NOPS; i++) {
    char c0[32], c1[32], c2[32], c3[32];
    int a = dbc(db, ops[i].op, 0, c0, sizeof c0);
    int b = dbc(db, ops[i].op, 2, c1, sizeof c1);
    int c = dbc(db, ops[i].op, -2, c2, sizeof c2);
    int d = dbc(db, ops[i].op, 0, c3, sizeof c3);
    printf("  %-22s set 0: %d cell %s; set 2: %d cell %s; set -2: %d cell %s; set 0: %d cell %s\n",
           ops[i].name, a, c0, b, c1, c, c2, d, c3);
  }
  close_or_die(db);
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: d1-db-config-open DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { perror(argv[2]); return 2; }
  version_lines();
  printf("constants: ENABLE_LOAD_EXTENSION %d, DEFENSIVE %d, DQS_DML %d, DQS_DDL %d,"
         " SQLITE_DBCONFIG_MAX %d, STMTSTATUS_REPREPARE %d\n",
         SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, SQLITE_DBCONFIG_DEFENSIVE, SQLITE_DBCONFIG_DQS_DML,
         SQLITE_DBCONFIG_DQS_DDL, SQLITE_DBCONFIG_MAX, SQLITE_STMTSTATUS_REPREPARE);

  printf("\nD1. A set between a SELECT's two runs; codes as SQLite answers them\n");
  d1(0);
  printf("\nD1b. A set while the SELECT is held at its first row\n");
  d1(1);

  printf("\nD2. A statement prepared with DQS on, then DQS turned off, then run again\n");
  d2_case(SQLITE_DBCONFIG_DQS_DML, NULL, "select \"no_such_column\"", "DQS_DML: select \"no_such_column\"");
  d2_case(SQLITE_DBCONFIG_DQS_DDL, NULL, "create index if not exists i on t(\"no_such_column\")",
          "DQS_DDL: create index ... (\"no_such_column\")");
  d2_case(SQLITE_DBCONFIG_DQS_DML, NULL, "select x from t", "DQS_DML: select x from t (control)");

  printf("\nD3. The connection's error state around db_config\n");
  d3();

  printf("\nD4. A set under another connection's EXCLUSIVE lock\n");
  d4();

  printf("\nD5. Each op's round trip, on connections the open can make\n");
  d5();

  printf("\nD6. onoff values v1 never passes\n");
  d6();
  fclose(timing);
  return 0;
}
