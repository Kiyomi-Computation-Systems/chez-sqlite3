/* rv3.c: M4's plan review's probe, rerun here (the M4 plan, section 8;
 * run-review.sh runs it): a bare name to sqlite3_load_extension, from a
 * working directory that does not hold it; LD_LIBRARY_PATH as the caller's
 * environment sets it. */
#include <sqlite3.h>
#include <stdio.h>
int main(int argc, char **argv) {
  sqlite3 *db = 0; int cell = -77; char *msg = (char *)1;
  if (argc != 2) return 2;
  sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, 0);
  sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 1, &cell);
  int rc = sqlite3_load_extension(db, argv[1], 0, &msg);
  printf("load(%s) answered %d, slot %s\n", argv[1], rc, msg ? msg : "NULL");
  sqlite3_free(msg); sqlite3_close(db); return 0;
}
