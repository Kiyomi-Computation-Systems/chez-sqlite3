/* The same, for a statement that reads no table: select ?1, TEXT bound with
   its length, read with column_text (which must NUL-terminate a copy). */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int ex(sqlite3 *db, const char *s) { return sqlite3_exec(db, s, NULL, NULL, NULL); }
static long long one(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st; long long v = -1;
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) return -2;
  if (sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st); return v;
}
int main(int argc, char **argv) {
  char path[4096]; sqlite3 *db; sqlite3_stmt *st; int rc, n = 100000; char *v;
  if (argc < 2) return 2;
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) return 4;
  printf("library %s\n", sqlite3_libversion());
  snprintf(path, sizeof path, "%s/d.db", argv[1]);
  sqlite3_open(path, &db);
  ex(db, "create table u(x)");
  ex(db, "begin; insert into u values ('marker')");
  v = malloc(n); memset(v, 'y', n);
  sqlite3_prepare_v2(db, "select ?1", -1, &st, NULL);
  sqlite3_bind_text64(st, 1, v, n, SQLITE_TRANSIENT, SQLITE_UTF8);
  rc = sqlite3_step(st);
  sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  printf("select ?1: step %d, column_text %s", rc, sqlite3_column_text(st, 0) ? "a pointer" : "NULL");
  sqlite3_hard_heap_limit64(0);
  printf(", extended %d\n", sqlite3_extended_errcode(db));
  rc = sqlite3_reset(st);
  printf("  reset %d, autocommit %d, marker rows %lld\n", rc, sqlite3_get_autocommit(db),
         one(db, "select count(*) from u"));
  sqlite3_finalize(st); free(v);
  if (!sqlite3_get_autocommit(db)) ex(db, "rollback");
  sqlite3_close(db);
  return 0;
}
