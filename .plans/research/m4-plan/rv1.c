/* rv1.c: M4's plan review's probe, written by the review and rerun here
 * (the M4 plan, section 8; run-review.sh runs it).
 *   A. a failed load after a prior error: is the connection's error state kept?
 *   B. a replacing load beside a held row (research L8): the slot's text, and
 *      what the connection's errcode and errmsg say after it
 *   C. ADR-0018's six PRAGMAs, set and read back, on a fresh file, with the
 *      ops at the library's start, then with DEFENSIVE 1 and both DQS 0; and
 *      two controls outside the list, journal_mode = off and writable_schema
 * Usage: rv1 DIR   (DIR holds ext.so; files are made in DIR). run-review.sh
 * runs it from DIR's parent, with DIR written "DIR", so no output names a
 * machine's path.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>

static const int FLAGS = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE |
                         SQLITE_OPEN_FULLMUTEX;

static void state(sqlite3 *db, const char *label) {
  printf("  %-34s errcode %d, extended %d, errmsg \"%s\"\n", label, sqlite3_errcode(db),
         sqlite3_extended_errcode(db), sqlite3_errmsg(db));
}

static void load(sqlite3 *db, const char *path, const char *label) {
  char *msg = (char *)1;
  int rc = sqlite3_load_extension(db, path, 0, &msg);
  printf("  %-34s answered %d, slot %s%s%s\n", label, rc, msg ? "\"" : "NULL",
         msg ? msg : "", msg ? "\"" : "");
  if (msg) sqlite3_free(msg);
}

/* one statement, stepped to done; then its read, the first column as text */
static void pragma(sqlite3 *db, const char *set, const char *read) {
  sqlite3_stmt *s = 0;
  int rc = sqlite3_prepare_v2(db, set, -1, &s, 0);
  int step = -1;
  if (rc == SQLITE_OK) {
    while ((step = sqlite3_step(s)) == SQLITE_ROW) {}
  }
  int fin = sqlite3_finalize(s);
  printf("    %-36s prepare %d step %d finalize %d;", set, rc, step, fin);
  s = 0;
  rc = sqlite3_prepare_v2(db, read, -1, &s, 0);
  if (rc == SQLITE_OK && sqlite3_step(s) == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(s, 0);
    printf(" read %s\n", t ? (const char *)t : "NULL");
  } else {
    printf(" read: none (prepare %d)\n", rc);
  }
  sqlite3_finalize(s);
}

static int set_op(sqlite3 *db, int op, int v) {
  int cell = -77;
  int rc = sqlite3_db_config(db, op, v, &cell);
  return rc == SQLITE_OK && cell == v;
}

static void the_list(const char *dir, const char *name, int harden) {
  char path[4096];
  snprintf(path, sizeof path, "%s/%s.db", dir, name);
  remove(path);
  sqlite3 *db = 0;
  if (sqlite3_open_v2(path, &db, FLAGS, 0) != SQLITE_OK) { printf("open failed\n"); return; }
  if (harden) {
    int ok = set_op(db, SQLITE_DBCONFIG_DEFENSIVE, 1) && set_op(db, SQLITE_DBCONFIG_DQS_DML, 0) &&
             set_op(db, SQLITE_DBCONFIG_DQS_DDL, 0);
    printf("  DEFENSIVE 1, DQS_DML 0, DQS_DDL 0: %s\n", ok ? "set" : "FAILED");
  } else {
    printf("  the library's start\n");
  }
  /* a table, so the file has a schema, as an application's does */
  sqlite3_exec(db, "create table t(x)", 0, 0, 0);
  pragma(db, "PRAGMA busy_timeout = 5000", "PRAGMA busy_timeout");
  pragma(db, "PRAGMA foreign_keys = 1", "PRAGMA foreign_keys");
  pragma(db, "PRAGMA foreign_keys = 0", "PRAGMA foreign_keys");
  pragma(db, "PRAGMA synchronous = 0", "PRAGMA synchronous");
  pragma(db, "PRAGMA synchronous = 3", "PRAGMA synchronous");
  pragma(db, "PRAGMA temp_store = 2", "PRAGMA temp_store");
  pragma(db, "PRAGMA temp_store = 1", "PRAGMA temp_store");
  pragma(db, "PRAGMA trusted_schema = 0", "PRAGMA trusted_schema");
  pragma(db, "PRAGMA trusted_schema = 1", "PRAGMA trusted_schema");
  pragma(db, "PRAGMA journal_mode = truncate", "PRAGMA journal_mode");
  pragma(db, "PRAGMA journal_mode = persist", "PRAGMA journal_mode");
  pragma(db, "PRAGMA journal_mode = wal", "PRAGMA journal_mode");
  pragma(db, "PRAGMA journal_mode = delete", "PRAGMA journal_mode");
  printf("  controls, outside the list\n");
  pragma(db, "PRAGMA journal_mode = off", "PRAGMA journal_mode");
  pragma(db, "PRAGMA writable_schema = 1", "PRAGMA writable_schema");
  sqlite3_close(db);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: rv1 DIR\n"); return 2; }
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER ||
      strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "rv1: header %s, library %s\n", SQLITE_VERSION, sqlite3_libversion());
    return 2;
  }
  const char *dir = argv[1];
  char ext[4096], nosuch[4096];
  snprintf(ext, sizeof ext, "%s/ext.so", dir);
  snprintf(nosuch, sizeof nosuch, "%s/nosuch.so", dir);
  printf("libversion: %s\n", sqlite3_libversion());

  sqlite3 *db = 0;
  sqlite3_open_v2(":memory:", &db, FLAGS, 0);
  printf("A. a failed load after a prior error\n");
  printf("  ENABLE_LOAD_EXTENSION 1: %s\n",
         set_op(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 1) ? "set" : "FAILED");
  sqlite3_stmt *s = 0;
  int rc = sqlite3_prepare_v2(db, "select nosuch", -1, &s, 0);
  printf("  a prepare of select nosuch answered %d\n", rc);
  state(db, "after the prepare");
  load(db, nosuch, "load DIR/nosuch.so");
  state(db, "after the failed load");
  load(db, ext, "load DIR/ext.so");
  state(db, "after the successful load");

  printf("B. a replacing load beside a held row\n");
  s = 0;
  sqlite3_prepare_v2(db, "select 1 union all select 2", -1, &s, 0);
  printf("  held: step %d\n", sqlite3_step(s));
  state(db, "before the load");
  load(db, ext, "load DIR/ext.so again");
  state(db, "after it");
  sqlite3_finalize(s);
  sqlite3_close(db);

  printf("C. ADR-0018's PRAGMAs\n");
  the_list(dir, "start", 0);
  the_list(dir, "hardened", 1);
  return 0;
}
