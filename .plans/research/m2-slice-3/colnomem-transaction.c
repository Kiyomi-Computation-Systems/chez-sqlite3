/* Does a column read's NOMEM, inside BEGIN, end the transaction at the next
   reset? The heap limit is in force for the column_text call only. */
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>
static int ex(sqlite3 *db, const char *s) { return sqlite3_exec(db, s, NULL, NULL, NULL); }
static long long one(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st; long long v = -1;
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) return -2;
  if (sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st); return v;
}
static void one_case(const char *dir, int finalize_instead) {
  char path[4096]; sqlite3 *db; sqlite3_stmt *st; int rc; const void *t;
  snprintf(path, sizeof path, "%s/c%d.db", dir, finalize_instead);
  sqlite3_open(path, &db);
  ex(db, "create table src(x); create table u(x)");
  ex(db, "insert into src values (randomblob(100000))");
  ex(db, "begin; insert into u values ('marker')");
  sqlite3_prepare_v2(db, "select hex(x) from src", -1, &st, NULL);
  rc = sqlite3_step(st);
  printf("%s: step %d, autocommit %d\n", finalize_instead ? "finalize case" : "reset case", rc,
         sqlite3_get_autocommit(db));
  sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000);
  t = sqlite3_column_text16(st, 0); /* a conversion, so it must allocate */
  sqlite3_hard_heap_limit64(0);
  printf("  column_text16 %s, extended %d\n", t ? "a pointer" : "NULL", sqlite3_extended_errcode(db));
  rc = finalize_instead ? sqlite3_finalize(st) : sqlite3_reset(st);
  printf("  %s %d, autocommit %d, marker rows %lld\n", finalize_instead ? "finalize" : "reset", rc,
         sqlite3_get_autocommit(db), one(db, "select count(*) from u"));
  if (!finalize_instead) sqlite3_finalize(st);
  if (!sqlite3_get_autocommit(db)) ex(db, "rollback");
  sqlite3_close(db);
}
int main(int argc, char **argv) {
  if (argc < 2) return 2;
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) return 4;
  printf("library %s\n", sqlite3_libversion());
  one_case(argv[1], 0);
  one_case(argv[1], 1);
  return 0;
}
