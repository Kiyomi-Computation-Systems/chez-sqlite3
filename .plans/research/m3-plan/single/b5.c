/* B5: claims in the records about M3's topics that no research measured.
 *
 *   b5 DIR       DIR: a fresh directory for this run's databases
 *
 *   V1  ADR-0015, Context: "SQLite has no boolean; ... booleans are stored as
 *       the integers 0 and 1, and TRUE and FALSE are spellings of them."
 *   V2  ADR-0012, Context: "sqlite3_close refuses with SQLITE_BUSY while
 *       statements are unfinalized, and leaves the connection open." A
 *       statement cache holds statements its connection tracks (ADR-0014).
 *   (brief §2.7's journal_mode=wal on :memory: is pragmas.c's P11, and
 *    brief §4's entry points are entry-points.sps.)
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
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open %s: rc %d\n", name, rc); exit(2); }
  return db;
}

static void must(sqlite3 *db, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static void rows(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  printf("  %s\n", sql);
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) {
    printf("    prepare failed: %s\n", sqlite3_errmsg(db));
    return;
  }
  while (sqlite3_step(st) == SQLITE_ROW) {
    printf("    row:");
    for (int i = 0; i < sqlite3_column_count(st); i++) {
      switch (sqlite3_column_type(st, i)) {
      case SQLITE_INTEGER: printf(" int %lld", (long long)sqlite3_column_int64(st, i)); break;
      case SQLITE_TEXT: printf(" text '%s'", sqlite3_column_text(st, i)); break;
      case SQLITE_FLOAT: printf(" real %g", sqlite3_column_double(st, i)); break;
      case SQLITE_NULL: printf(" null"); break;
      default: printf(" blob"); break;
      }
    }
    printf("\n");
  }
  sqlite3_finalize(st);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: b5 DIR\n"); return 2; }
  dir = argv[1];
  version_lines();

  printf("\nV1. TRUE and FALSE\n");
  sqlite3 *db = open_at("v1.db");
  rows(db, "SELECT TRUE, typeof(TRUE), FALSE, typeof(FALSE), TRUE + TRUE, true = 1, false = 0");
  must(db, "CREATE TABLE bl(f BOOLEAN); INSERT INTO bl VALUES (TRUE), (FALSE), ('true'), (2);");
  rows(db, "SELECT f, typeof(f), f IS TRUE, f = TRUE FROM bl");
  if (sqlite3_close(db) != SQLITE_OK) return 2;

  printf("\nV2. sqlite3_close with an unfinalized statement\n");
  db = open_at("v2.db");
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2);");
  {
    sqlite3_stmt *st = NULL;
    sqlite3_prepare_v3(db, "SELECT x FROM t", -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
    int c1 = sqlite3_close(db);
    printf("  close with one prepared, unstepped: rc %d, errmsg \"%s\", next_stmt is the statement: %d\n",
           c1, sqlite3_errmsg(db), sqlite3_next_stmt(db, NULL) == st);
    int s = sqlite3_step(st);
    printf("  the connection still works: step rc %d\n", s);
    int c2 = sqlite3_close(db);
    printf("  close with it mid-row: rc %d, errmsg \"%s\"\n", c2, sqlite3_errmsg(db));
    int f = sqlite3_finalize(st);
    printf("  finalize: rc %d; next_stmt is NULL: %d\n", f, sqlite3_next_stmt(db, NULL) == NULL);
    int c3 = sqlite3_close(db);
    printf("  close: rc %d\n", c3);
  }
  return 0;
}
