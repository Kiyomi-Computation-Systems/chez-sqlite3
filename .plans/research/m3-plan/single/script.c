/* B4: a script of several statements, run by sqlite3_exec and by a loop of
 * sqlite3_prepare_v2 over the tail.
 *
 *   script DIR       DIR: a fresh directory for this run's databases
 *
 * Each script runs twice, on a database file of its own each time: once by
 * sqlite3_exec, once by the loop. After each run: the answer, the error
 * message exec hands back, sqlite3_errmsg, sqlite3_extended_errcode and
 * sqlite3_error_offset, sqlite3_get_autocommit, and the rows of s.
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

/* printable: the SQL with newlines shown as \n. */
static void put_sql(const char *s, int n) {
  for (int i = 0; i < n && s[i]; i++) {
    if (s[i] == '\n') printf("\\n"); else putchar(s[i]);
  }
}

static void after(sqlite3 *db) {
  sqlite3_stmt *st = NULL;
  printf("    errmsg \"%s\", extended_errcode %d, error_offset %d, autocommit %d\n",
         sqlite3_errmsg(db), sqlite3_extended_errcode(db), sqlite3_error_offset(db),
         sqlite3_get_autocommit(db));
  if (sqlite3_prepare_v2(db, "SELECT coalesce(group_concat(x, ','), '(none)') FROM (SELECT x FROM s ORDER BY x)",
                         -1, &st, NULL) != SQLITE_OK) {
    printf("    rows of s: (no table s)\n");
    return;
  }
  if (sqlite3_step(st) == SQLITE_ROW) printf("    rows of s: %s\n", sqlite3_column_text(st, 0));
  sqlite3_finalize(st);
  if (!sqlite3_get_autocommit(db)) {
    must(db, "ROLLBACK");
    printf("    (rolled back to close the probe's connection)\n");
  }
}

static int callback_rows;
static int callback_stop_at;

static int on_row(void *unused, int n, char **values, char **names) {
  (void)unused;
  callback_rows++;
  printf("    callback row %d:", callback_rows);
  for (int i = 0; i < n; i++) printf(" %s=%s", names[i], values[i] ? values[i] : "NULL");
  printf("\n");
  return callback_rows == callback_stop_at;
}

static int case_number = 0;

static void by_exec(const char *setup, const char *script, int with_callback, int stop_at) {
  char name[32];
  snprintf(name, sizeof name, "x%02d-exec.db", case_number);
  sqlite3 *db = open_at(name);
  if (setup) must(db, setup);
  char *msg = NULL;
  callback_rows = 0;
  callback_stop_at = stop_at;
  int rc = sqlite3_exec(db, script, with_callback ? on_row : NULL, NULL, &msg);
  printf("  sqlite3_exec%s: rc %d, its message %s%s%s\n",
         with_callback ? (stop_at ? " (callback stops at its row 1)" : " (callback)") : " (no callback)",
         rc, msg ? "\"" : "", msg ? msg : "NULL", msg ? "\"" : "");
  sqlite3_free(msg);
  after(db);
  close_db(db);
}

static void by_loop(const char *setup, const char *script) {
  char name[32];
  snprintf(name, sizeof name, "x%02d-loop.db", case_number);
  sqlite3 *db = open_at(name);
  if (setup) must(db, setup);
  const char *at = script;
  printf("  prepare_v2 loop:\n");
  for (;;) {
    sqlite3_stmt *st = NULL;
    const char *tail = NULL;
    int rc = sqlite3_prepare_v2(db, at, -1, &st, &tail);
    if (rc != SQLITE_OK) {
      printf("    at byte %d: prepare rc %d, errmsg \"%s\", error_offset %d (from the script's start: %d)\n",
             (int)(at - script), rc, sqlite3_errmsg(db), sqlite3_error_offset(db),
             (int)(at - script) + sqlite3_error_offset(db));
      break;
    }
    if (st == NULL) {
      printf("    at byte %d: no statement; tail at byte %d, end of script\n", (int)(at - script), (int)(tail - script));
      break;
    }
    printf("    at byte %d: [", (int)(at - script));
    put_sql(at, (int)(tail - at));
    printf("]");
    int rows = 0;
    while ((rc = sqlite3_step(st)) == SQLITE_ROW) rows++;
    printf(" step rc %d, rows %d", rc, rows);
    int f = sqlite3_finalize(st);
    printf(", finalize rc %d\n", f);
    if (rc != SQLITE_DONE) break;
    at = tail;
    if (*at == 0) { printf("    end of script\n"); break; }
  }
  after(db);
  close_db(db);
}

static void both(const char *title, const char *setup, const char *script) {
  case_number++;
  printf("\nX%d. %s\n  script: [", case_number, title);
  put_sql(script, (int)strlen(script));
  printf("]\n");
  by_exec(setup, script, 0, 0);
  by_loop(setup, script);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: script DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  const char *s = "CREATE TABLE s(x UNIQUE);";

  both("A constraint failure midway, in autocommit", NULL,
       "CREATE TABLE s(x UNIQUE); INSERT INTO s VALUES (1); INSERT INTO s VALUES (2); "
       "INSERT INTO s VALUES (1); INSERT INTO s VALUES (3);");
  both("A constraint failure midway, inside BEGIN ... COMMIT", s,
       "BEGIN; INSERT INTO s VALUES (10); INSERT INTO s VALUES (10); INSERT INTO s VALUES (11); COMMIT;");
  both("A constraint failure midway, inside SAVEPOINT ... RELEASE", s,
       "SAVEPOINT sp; INSERT INTO s VALUES (20); INSERT INTO s VALUES (20); RELEASE sp;");
  both("INSERT OR ROLLBACK failing midway, inside BEGIN ... COMMIT", s,
       "BEGIN; INSERT INTO s VALUES (30); INSERT OR ROLLBACK INTO s VALUES (30); INSERT INTO s VALUES (31); COMMIT;");
  both("A syntax error in the second of three statements", s,
       "INSERT INTO s VALUES (40); SELEKT 1; INSERT INTO s VALUES (41);");
  both("No such table in the second of three statements", s,
       "INSERT INTO s VALUES (50);\nINSERT INTO nosuch VALUES (1);\nINSERT INTO s VALUES (51);");
  both("Statements that return rows, among writes", s,
       "SELECT 1; INSERT INTO s VALUES (60); SELECT x FROM s; INSERT INTO s VALUES (61); SELECT count(*) FROM s;");
  both("An incomplete last statement", s,
       "INSERT INTO s VALUES (70); INSERT INTO s VALUES (");
  both("A trailing comment and whitespace", s,
       "INSERT INTO s VALUES (80);  -- done\n  ");
  both("Empty, only semicolons, only a comment", s, "");
  both("Only semicolons", s, ";;;");
  both("Only a comment", s, "-- nothing");
  both("A statement with no semicolon at its end", s, "INSERT INTO s VALUES (90)");
  both("PRAGMAs in a script", s,
       "PRAGMA foreign_keys = ON; PRAGMA user_version = 9; INSERT INTO s SELECT user_version FROM pragma_user_version;");
  both("A runtime error (integer overflow) midway", s,
       "INSERT INTO s VALUES (100); SELECT abs(-9223372036854775807 - 1); INSERT INTO s VALUES (101);");
  both("A failed COMMIT (a deferred foreign key) midway", "CREATE TABLE s(x UNIQUE); PRAGMA foreign_keys = ON;"
       "CREATE TABLE p(id INTEGER PRIMARY KEY); CREATE TABLE c(pid REFERENCES p(id) DEFERRABLE INITIALLY DEFERRED);",
       "BEGIN; INSERT INTO s VALUES (110); INSERT INTO c VALUES (7); COMMIT; INSERT INTO s VALUES (111);");

  case_number++;
  printf("\nX%d. sqlite3_exec with a callback\n", case_number);
  by_exec(s, "INSERT INTO s VALUES (120), (121); SELECT x FROM s ORDER BY x; INSERT INTO s VALUES (122);", 1, 0);
  case_number++;
  printf("\nX%d. sqlite3_exec with a callback that answers nonzero at its first row\n", case_number);
  by_exec(s, "INSERT INTO s VALUES (130), (131); SELECT x FROM s ORDER BY x; INSERT INTO s VALUES (132);", 1, 1);

  case_number++;
  printf("\nX%d. sqlite3_exec with no out-parameter for its message\n", case_number);
  {
    sqlite3 *db = open_at("x-null.db");
    must(db, s);
    int rc = sqlite3_exec(db, "INSERT INTO s VALUES (1); INSERT INTO s VALUES (1);", NULL, NULL, NULL);
    printf("  sqlite3_exec: rc %d\n", rc);
    after(db);
    close_db(db);
  }
  return 0;
}
