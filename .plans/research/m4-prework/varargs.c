/* varargs.c: the C oracle for varargs.sps (M4's pre-work).
 *
 * It makes varargs.sps's varargs calls in C, where the compiler knows
 * sqlite3_db_config is variadic, and prints them as varargs.sps does, under
 * the label c: the round trips, the unknown op, the behaviour and the
 * LOOKASIDE shape, in the same order, with the same sentinels and the same
 * SQL. run.sh compares its lines with the probe's.
 *
 * Build it against one header and the library that header describes, e.g.
 *   $CC -Wall -Wextra -Werror -I DIR/include -o varargs varargs.c LIBRARY \
 *       -Wl,-rpath,LIBDIR
 * It prints the header's SQLITE_VERSION and the library's
 * sqlite3_libversion() first, so a mismatched pair shows.
 *
 * Text is printed as varargs.sps's byte-text prints it: printable ASCII but %
 * as itself, any other byte as %HH, in a string written as Chez's write
 * writes one, with \ and " escaped. Every database is :memory:. */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define UNKNOWN_OP 1999

/* put_bytes: N bytes at P as a written string; N < 0 reads to the NUL. */
static void put_bytes(const unsigned char *p, int n) {
  int i;
  putchar('"');
  for (i = 0; n < 0 ? p[i] != 0 : i < n; i++) {
    unsigned char b = p[i];
    if (b >= 0x20 && b <= 0x7e && b != '%') {
      if (b == '"' || b == '\\') putchar('\\');
      putchar(b);
    } else {
      printf("%%%02X", b);
    }
  }
  putchar('"');
}

/* put_text: a NUL-terminated string, or null for NULL. */
static void put_text(const char *s) {
  if (s == NULL) fputs("null", stdout);
  else put_bytes((const unsigned char *)s, -1);
}

static void done_line(void) {
  putchar(')');
  putchar('\n');
  fflush(stdout);
}

static sqlite3 *open_memory(void) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  if (rc != SQLITE_OK) {
    printf("(open-failed %d)\n", rc);
    if (db != NULL) sqlite3_close(db);
    exit(1);
  }
  return db;
}

static void close_db(sqlite3 *db) {
  int rc = sqlite3_close(db);
  if (rc != SQLITE_OK) {
    printf("(close-failed %d)\n", rc);
    exit(1);
  }
}

/* run_sql: prepares SQL on DB, steps it once and prints the answer as
 * varargs.sps's run-sql gives it, then finalizes. */
static void run_sql(sqlite3 *db, const char *sql) {
  sqlite3_stmt *stmt = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK) {
    printf("(prepare-error %d ", rc);
    put_text(sqlite3_errmsg(db));
    putchar(')');
    return;
  }
  rc = sqlite3_step(stmt);
  if (rc == SQLITE_ROW) {
    const unsigned char *text = sqlite3_column_text(stmt, 0);
    int n = sqlite3_column_bytes(stmt, 0);
    fputs("(row ", stdout);
    if (text == NULL) fputs("null", stdout);
    else put_bytes(text, n);
    putchar(')');
  } else if (rc == SQLITE_DONE) {
    fputs("(done)", stdout);
  } else {
    printf("(step-error %d ", rc);
    put_text(sqlite3_errmsg(db));
    putchar(')');
  }
  sqlite3_finalize(stmt);
}

/* print_sql_line: PREFIX, the SQL as a string, then its answer. */
static void print_sql_line(const char *prefix, sqlite3 *db, const char *sql) {
  fputs(prefix, stdout);
  put_text(sql);
  putchar(' ');
  run_sql(db, sql);
  done_line();
}

/* put_out: the cell's value, or untouched when it still holds SENTINEL. */
static void put_out(int out, int sentinel) {
  if (out == sentinel) fputs("untouched", stdout);
  else printf("%d", out);
}

struct op { const char *name; int op; };

static const struct op ops[] = {
  { "ENABLE_LOAD_EXTENSION", SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION },
  { "DEFENSIVE", SQLITE_DBCONFIG_DEFENSIVE },
  { "DQS_DML", SQLITE_DBCONFIG_DQS_DML },
  { "DQS_DDL", SQLITE_DBCONFIG_DQS_DDL },
  { "TRUSTED_SCHEMA", SQLITE_DBCONFIG_TRUSTED_SCHEMA },
};
#define NOPS ((int)(sizeof ops / sizeof ops[0]))

/* The seven calls of a round trip; START stands for the first read's value. */
#define START 2
static const struct { const char *name; int onoff; } steps[] = {
  { "start", -1 }, { "set-0", 0 }, { "read-0", -1 }, { "set-1", 1 },
  { "read-1", -1 }, { "restore", START }, { "read-restored", -1 },
};
#define NSTEPS ((int)(sizeof steps / sizeof steps[0]))

static void round_trip(const struct op *o) {
  sqlite3 *db = open_memory();
  int i, start = 0, start_known = 0, start_untouched = 0, ok = 1;
  for (i = 0; i < NSTEPS; i++) {
    int sentinel = -(100 + i);
    int cell = sentinel;
    int onoff = steps[i].onoff;
    int rc, out, untouched, good;
    if (onoff == START) onoff = (start_known && (start == 0 || start == 1)) ? start : -1;
    rc = sqlite3_db_config(db, o->op, onoff, &cell);
    out = cell;
    untouched = out == sentinel;
    if (i == 0) {
      start = out;
      start_known = !untouched;
      start_untouched = untouched;
    }
    if (i == 0) good = !untouched && (out == 0 || out == 1);
    else if (i == 1 || i == 2) good = !untouched && out == 0;
    else if (i == 3 || i == 4) good = !untouched && out == 1;
    else good = start_untouched ? untouched : (!untouched && out == start);
    good = good && rc == SQLITE_OK;
    ok = ok && good;
    printf("(c round-trip %s %s onoff %d rc %d out ", o->name, steps[i].name, onoff, rc);
    put_out(out, sentinel);
    done_line();
  }
  printf("(c verdict %s %s", o->name, ok ? "ok" : "fails");
  done_line();
  close_db(db);
}

static void unknown(void) {
  sqlite3 *db = open_memory();
  int cell = -150;
  int rc = sqlite3_db_config(db, UNKNOWN_OP, -1, &cell);
  printf("(c unknown-op %d rc %d out ", UNKNOWN_OP, rc);
  put_out(cell, -150);
  done_line();
  close_db(db);
}

static const char *const sql_load[] = { "select load_extension('x')", NULL };
static const char *const sql_defensive[] = {
  "create table t(a)",
  "PRAGMA writable_schema = 1",
  "PRAGMA writable_schema",
  "update sqlite_schema set sql = sql where name = 't'",
  "PRAGMA writable_schema = 0",
  NULL,
};
static const char *const sql_dqs_dml[] = { "select \"no_such_column\"", NULL };
static const char *const sql_dqs_ddl[] = {
  "create table t(a)",
  "create index i on t(\"no_such_column\")",
  NULL,
};

static const char *const *behaviour_sql(const char *name) {
  if (strcmp(name, "ENABLE_LOAD_EXTENSION") == 0) return sql_load;
  if (strcmp(name, "DEFENSIVE") == 0) return sql_defensive;
  if (strcmp(name, "DQS_DML") == 0) return sql_dqs_dml;
  if (strcmp(name, "DQS_DDL") == 0) return sql_dqs_ddl;
  return NULL;
}

static void behaviour(const struct op *o, int value) {
  const char *const *sql = behaviour_sql(o->name);
  sqlite3 *db = open_memory();
  int cell = -200;
  int rc = sqlite3_db_config(db, o->op, value, &cell);
  char prefix[128];
  printf("(c behaviour %s %d config rc %d out ", o->name, value, rc);
  put_out(cell, -200);
  done_line();
  snprintf(prefix, sizeof prefix, "(c behaviour %s %d ", o->name, value);
  for (; *sql != NULL; sql++) print_sql_line(prefix, db, *sql);
  close_db(db);
}

static const char *const lookaside_workload[] = {
  "create table t(a, b)",
  "insert into t values (1, 'one'), (2, 'two'), (3, 'three')",
  "select count(*) from t",
};

static const struct { const char *name; int op; } lookaside_stats[] = {
  { "used", SQLITE_DBSTATUS_LOOKASIDE_USED },
  { "hit", SQLITE_DBSTATUS_LOOKASIDE_HIT },
  { "miss-size", SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE },
  { "miss-full", SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL },
};

static void lookaside(int sz, int cnt) {
  sqlite3 *db = open_memory();
  sqlite3_stmt *stmt = NULL;
  char prefix[64];
  int i, rc, prepared, held, after;
  rc = sqlite3_db_config(db, SQLITE_DBCONFIG_LOOKASIDE, (void *)0, sz, cnt);
  printf("(c lookaside %d %d config rc %d", sz, cnt, rc);
  done_line();
  snprintf(prefix, sizeof prefix, "(c lookaside %d %d ", sz, cnt);
  for (i = 0; i < 3; i++) print_sql_line(prefix, db, lookaside_workload[i]);
  for (i = 0; i < 4; i++) {
    int cur = -300, hi = -301;
    rc = sqlite3_db_status(db, lookaside_stats[i].op, &cur, &hi, 0);
    printf("(c lookaside %d %d status %s rc %d cur %d hi %d", sz, cnt, lookaside_stats[i].name,
           rc, cur, hi);
    done_line();
  }
  prepared = sqlite3_prepare_v2(db, "select a from t", -1, &stmt, NULL);
  printf("(c lookaside %d %d reconfigure prepare %d step ", sz, cnt, prepared);
  if (prepared == SQLITE_OK) printf("%d", sqlite3_step(stmt));
  else fputs("not-prepared", stdout);
  held = sqlite3_db_config(db, SQLITE_DBCONFIG_LOOKASIDE, (void *)0, 120, 3);
  printf(" held-rc %d finalize ", held);
  if (stmt == NULL) fputs("no-statement", stdout);
  else printf("%d", sqlite3_finalize(stmt));
  after = sqlite3_db_config(db, SQLITE_DBCONFIG_LOOKASIDE, (void *)0, 120, 3);
  printf(" after-rc %d", after);
  done_line();
  close_db(db);
}

int main(void) {
  int i;
  printf("(c-header-version \"%s\")\n", SQLITE_VERSION);
  printf("(c-libversion \"%s\")\n", sqlite3_libversion());
  printf("(c-sourceid \"%s\")\n", sqlite3_sourceid());
  fflush(stdout);
  for (i = 0; i < NOPS; i++) round_trip(&ops[i]);
  unknown();
  for (i = 0; i < NOPS; i++) {
    if (behaviour_sql(ops[i].name) != NULL) {
      behaviour(&ops[i], 0);
      behaviour(&ops[i], 1);
    }
  }
  lookaside(120, 7);
  lookaside(120, 5);
  lookaside(200, 7);
  lookaside(0, 0);
  puts("(c-finished)");
  return 0;
}
