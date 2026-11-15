/* B3: the per-connection settings, through PRAGMAs.
 *
 *   pragmas DIR       DIR: a fresh directory for this run's databases
 *
 *   P1  each PRAGMA: its default, what `PRAGMA name = value` answers, what
 *       `PRAGMA name` reads back, and what a new connection to the same file
 *       reads after a close: reset with the connection, or kept in the file
 *   P2  the same, for settings that are process-wide, not per connection
 *   P3  which PRAGMAs take effect at prepare, unstepped
 *   P4  invalid values, each from a non-default base of its own
 *   P5  unknown names, and a misspelling
 *   P6  foreign_keys inside a transaction; defer_foreign_keys across one;
 *       journal_mode and synchronous inside one, before and after it writes
 *   P7  bound parameters, a schema name, and the grammar of a value
 *   P8  case, in names and values, and in what comes back
 *   P9  reading settings through table-valued pragma functions
 *   P10 query_only refusing a write
 *   P11 journal_mode=wal on :memory:
 *   P12 page_size, auto_vacuum and encoding on a file holding a table, then
 *       VACUUM on the same connection, then a reopen
 *   P13 journal_mode set while a SELECT on the same connection holds a row
 *
 * Every answer line gives the columns' names, then each row's values with
 * their storage class, then the step's code if it wasn't DONE.
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
  case 8: return "READONLY"; case 13: return "FULL"; case 19: return "CONSTRAINT";
  case 21: return "MISUSE"; case 25: return "RANGE"; case 100: return "ROW"; case 101: return "DONE";
  default: return "?";
  }
}

static void print_typed(sqlite3_stmt *st, int i) {
  switch (sqlite3_column_type(st, i)) {
  case SQLITE_INTEGER: printf(" int %lld", (long long)sqlite3_column_int64(st, i)); break;
  case SQLITE_FLOAT: printf(" real %.17g", sqlite3_column_double(st, i)); break;
  case SQLITE_TEXT: printf(" text '%s'", (const char *)sqlite3_column_text(st, i)); break;
  case SQLITE_BLOB: printf(" blob(%d)", sqlite3_column_bytes(st, i)); break;
  default: printf(" null"); break;
  }
}

/* answer: run one statement and print everything it answers, on one line. */
static void answer_bound(sqlite3 *db, const char *sql, const char *bind_text) {
  sqlite3_stmt *st = NULL;
  printf("  %s", sql);
  if (bind_text) printf("   [?1 bound to '%s']", bind_text);
  printf("\n");
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) {
    printf("    -> prepare rc %d %s, extended %d, errmsg \"%s\", error_offset %d\n",
           rc, code_name(rc), sqlite3_extended_errcode(db), sqlite3_errmsg(db),
           sqlite3_error_offset(db));
    return;
  }
  if (st == NULL) { printf("    -> prepare rc 0, no statement\n"); return; }
  if (bind_text) {
    int b = sqlite3_bind_text(st, 1, bind_text, -1, SQLITE_TRANSIENT);
    if (b != SQLITE_OK) printf("    bind rc %d\n", b);
  }
  int n = sqlite3_column_count(st);
  printf("    -> columns %d:", n);
  for (int i = 0; i < n; i++) printf(" \"%s\"", sqlite3_column_name(st, i));
  int rows = 0;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
    rows++;
    printf("; row");
    for (int i = 0; i < n; i++) print_typed(st, i);
  }
  if (rows == 0) printf("; no rows");
  if (rc != SQLITE_DONE)
    printf("; step rc %d %s, extended %d, errmsg \"%s\"", rc, code_name(rc),
           sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  printf("\n");
  int f = sqlite3_finalize(st);
  if (f != SQLITE_OK && rc == SQLITE_DONE) printf("    finalize rc %d\n", f);
}

static void answer(sqlite3 *db, const char *sql) { answer_bound(db, sql, NULL); }

/* read_value: the first column of `PRAGMA name`'s first row, as text. */
static void read_value(sqlite3 *db, const char *name, char *out, size_t size) {
  char sql[256];
  sqlite3_stmt *st = NULL;
  snprintf(sql, sizeof sql, "PRAGMA %s", name);
  snprintf(out, size, "(no row)");
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) { snprintf(out, size, "(prepare failed)"); return; }
  if (sqlite3_step(st) == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    snprintf(out, size, "%s", t ? (const char *)t : "NULL");
  }
  sqlite3_finalize(st);
}

struct setting { const char *name; const char *value; };

static const struct setting per_connection[] = {
  {"foreign_keys", "ON"},
  {"busy_timeout", "1234"},
  {"synchronous", "NORMAL"},
  {"cache_size", "-4321"},
  {"temp_store", "MEMORY"},
  {"recursive_triggers", "ON"},
  {"defer_foreign_keys", "ON"},
  {"query_only", "ON"},
  {"trusted_schema", "OFF"},
  {"secure_delete", "FAST"},
  {"automatic_index", "OFF"},
  {"journal_mode", "WAL"},
  {"journal_mode", "TRUNCATE"},
  {"user_version", "42"},
  {"application_id", "1234567"},
  {"locking_mode", "EXCLUSIVE"},
  {"cache_spill", "OFF"},
  {"cell_size_check", "ON"},
  {"max_page_count", "5000"},
  {"wal_autocheckpoint", "77"},
  {"journal_size_limit", "65536"},
  {"mmap_size", "1048576"},
  {"legacy_alter_table", "ON"},
  {"reverse_unordered_selects", "ON"},
  {"ignore_check_constraints", "ON"},
  {"case_sensitive_like", "ON"},
  {"threads", "2"},
  {"count_changes", "ON"},
  {"analysis_limit", "100"},
  {"auto_vacuum", "FULL"},
  {"page_size", "8192"},
  {"encoding", "'UTF-16le'"},
};

static void p1(void) {
  printf("\nP1. Set, read back, close, reopen the same file, read again\n");
  printf("  (each on a database file of its own, which holds one table before the PRAGMA)\n");
  int n = (int)(sizeof per_connection / sizeof per_connection[0]);
  for (int i = 0; i < n; i++) {
    char file[64], sql[256];
    const struct setting *s = &per_connection[i];
    snprintf(file, sizeof file, "p1-%02d.db", i);
    printf("\n P1.%d %s = %s\n", i + 1, s->name, s->value);
    sqlite3 *a = open_at(file);
    must(a, "CREATE TABLE k(x)");
    snprintf(sql, sizeof sql, "PRAGMA %s", s->name);
    printf("  [default]"); answer(a, sql);
    snprintf(sql, sizeof sql, "PRAGMA %s = %s", s->name, s->value);
    printf("  [set]    "); answer(a, sql);
    snprintf(sql, sizeof sql, "PRAGMA %s", s->name);
    printf("  [read]   "); answer(a, sql);
    close_db(a);
    sqlite3 *b = open_at(file);
    printf("  [reopen] "); answer(b, sql);
    close_db(b);
  }
}

static void p2(void) {
  printf("\nP2. Process-wide settings: set on one connection, read on others\n");
  sqlite3 *a = open_at("p2a.db");
  sqlite3 *b = open_at("p2b.db");
  answer(b, "PRAGMA soft_heap_limit");
  answer(a, "PRAGMA soft_heap_limit = 50000000");
  answer(b, "PRAGMA soft_heap_limit");
  close_db(a);
  sqlite3 *c = open_at("p2c.db");
  answer(c, "PRAGMA soft_heap_limit");
  printf("  sqlite3_soft_heap_limit64(-1) reads %lld\n", (long long)sqlite3_soft_heap_limit64(-1));
  answer(c, "PRAGMA soft_heap_limit = 0");
  answer(b, "PRAGMA soft_heap_limit");
  answer(b, "PRAGMA hard_heap_limit");
  answer(c, "PRAGMA hard_heap_limit = 60000000");
  answer(b, "PRAGMA hard_heap_limit");
  answer(c, "PRAGMA hard_heap_limit = 70000000");
  answer(c, "PRAGMA hard_heap_limit = 0");
  answer(b, "PRAGMA hard_heap_limit");
  sqlite3_hard_heap_limit64(0);
  printf("  sqlite3_hard_heap_limit64(0); then hard_heap_limit reads:\n");
  answer(b, "PRAGMA hard_heap_limit");
  close_db(c);
  close_db(b);
}

static void p3(void) {
  printf("\nP3. Prepared, never stepped: does the setting change?\n");
  printf("  (each on a fresh file; the value read before the prepare, while it is held, and after its finalize)\n");
  int n = (int)(sizeof per_connection / sizeof per_connection[0]);
  for (int i = 0; i < n; i++) {
    char file[64], sql[256], before[128], held[128], after[128];
    const struct setting *s = &per_connection[i];
    if (strcmp(s->name, "case_sensitive_like") == 0) continue;  /* no read form */
    snprintf(file, sizeof file, "p3-%02d.db", i);
    sqlite3 *a = open_at(file);
    must(a, "CREATE TABLE k(x)");
    read_value(a, s->name, before, sizeof before);
    snprintf(sql, sizeof sql, "PRAGMA %s = %s", s->name, s->value);
    sqlite3_stmt *st = NULL;
    int rc = sqlite3_prepare_v2(a, sql, -1, &st, NULL);
    read_value(a, s->name, held, sizeof held);
    int f = sqlite3_finalize(st);
    read_value(a, s->name, after, sizeof after);
    printf("  %-40s prepare rc %d, finalize rc %d: before %s, held %s, after %s -> %s\n",
           sql, rc, f, before, held, after,
           strcmp(before, after) == 0 ? "unchanged" : "CHANGED AT PREPARE");
    close_db(a);
  }
}

/* invalid: from a base of the caller's choosing, set a value, read it back. */
static void invalid(sqlite3 *db, const char *name, const char *base, const char *value) {
  char sql[256], b[128], got[128];
  snprintf(sql, sizeof sql, "PRAGMA %s = %s", name, base);
  must(db, sql);
  read_value(db, name, b, sizeof b);
  snprintf(sql, sizeof sql, "PRAGMA %s = %s", name, value);
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) {
    read_value(db, name, got, sizeof got);
    printf("  base %-8s %-42s prepare rc %d \"%s\"; reads %s\n", b, sql, rc, sqlite3_errmsg(db), got);
    return;
  }
  int step = SQLITE_DONE, rows = 0;
  char ans[128] = "";
  while ((step = sqlite3_step(st)) == SQLITE_ROW) {
    rows++;
    const unsigned char *t = sqlite3_column_text(st, 0);
    snprintf(ans, sizeof ans, "%s", t ? (const char *)t : "NULL");
  }
  char stepinfo[160] = "";
  if (step != SQLITE_DONE) snprintf(stepinfo, sizeof stepinfo, " step rc %d \"%s\";", step, sqlite3_errmsg(db));
  sqlite3_finalize(st);
  read_value(db, name, got, sizeof got);
  printf("  base %-8s %-42s%s answers %s; reads %s -> %s\n", b, sql, stepinfo,
         rows ? ans : "(no rows)", got,
         strcmp(b, got) == 0 ? "kept" : "changed");
}

static void p4(void) {
  printf("\nP4. Invalid values, each from a non-default base of its own\n");
  sqlite3 *db = open_at("p4.db");
  must(db, "CREATE TABLE k(x)");
  const char *sync_values[] = {"bogus", "''", "-1", "4", "99", "1.5", "'2abc'", "normal", "NORMAL", "Full", "0x1", "DEFAULT", "ON", "yes", NULL};
  for (int i = 0; sync_values[i]; i++) invalid(db, "synchronous", "EXTRA", sync_values[i]);
  const char *fk_on_values[] = {"bogus", "''", "enable", "'off'", "0.5", "DEFAULT", "-1", NULL};
  for (int i = 0; fk_on_values[i]; i++) invalid(db, "foreign_keys", "ON", fk_on_values[i]);
  const char *fk_off_values[] = {"2", "-1", "yes", "true", "TRUE", "On", "'on'", "1.5", "256", "0x1", NULL};
  for (int i = 0; fk_off_values[i]; i++) invalid(db, "foreign_keys", "OFF", fk_off_values[i]);
  const char *cache_values[] = {"'abc'", "''", "-100", "'12abc'", "1.9", "9223372036854775807",
                                "-9223372036854775808", "99999999999", "DEFAULT", "0x10", "1e3", NULL};
  for (int i = 0; cache_values[i]; i++) invalid(db, "cache_size", "777", cache_values[i]);
  const char *busy_values[] = {"-5", "'abc'", "''", "2147483648", "1.5", "0", NULL};
  for (int i = 0; busy_values[i]; i++) invalid(db, "busy_timeout", "1234", busy_values[i]);
  const char *temp_values[] = {"7", "-1", "'bogus'", "file", "3", NULL};
  for (int i = 0; temp_values[i]; i++) invalid(db, "temp_store", "MEMORY", temp_values[i]);
  const char *uv_values[] = {"-1", "'abc'", "4294967296", "2147483648", "1.5", "''", "'42'", "+42", "0x2A", NULL};
  for (int i = 0; uv_values[i]; i++) invalid(db, "user_version", "42", uv_values[i]);
  const char *aid_values[] = {"-1", "'abc'", "4294967297", NULL};
  for (int i = 0; aid_values[i]; i++) invalid(db, "application_id", "7", aid_values[i]);
  const char *jm_values[] = {"bogus", "''", "'WAL '", "1", NULL};
  for (int i = 0; jm_values[i]; i++) invalid(db, "journal_mode", "TRUNCATE", jm_values[i]);
  const char *lm_values[] = {"bogus", "''", "1", NULL};
  for (int i = 0; lm_values[i]; i++) invalid(db, "locking_mode", "NORMAL", lm_values[i]);
  const char *sd_values[] = {"bogus", "5", "-1", NULL};
  for (int i = 0; sd_values[i]; i++) invalid(db, "secure_delete", "FAST", sd_values[i]);
  const char *bools[] = {"recursive_triggers", "query_only", "trusted_schema", "automatic_index",
                         "defer_foreign_keys", "cell_size_check", NULL};
  for (int i = 0; bools[i]; i++) {
    invalid(db, bools[i], "ON", "bogus");
    invalid(db, bools[i], "OFF", "2");
  }
  must(db, "PRAGMA query_only = OFF");
  close_db(db);
}

static void p5(void) {
  printf("\nP5. Unknown names, in the set form and the read form, and a misspelling\n");
  sqlite3 *db = open_at("p5.db");
  must(db, "CREATE TABLE k(x)");
  answer(db, "PRAGMA nosuch");
  answer(db, "PRAGMA nosuch = 1");
  answer(db, "PRAGMA nosuch(1)");
  answer(db, "PRAGMA main.nosuch");
  answer(db, "PRAGMA foreign_key");
  answer(db, "PRAGMA foreign_key = ON");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "PRAGMA busytimeout = 100");
  answer(db, "PRAGMA busy_timeout");
  answer(db, "PRAGMA nosuchschema.user_version");
  answer(db, "PRAGMA nosuchschema.user_version = 3");
  answer(db, "PRAGMA nosuchschema.foreign_keys = ON");
  answer(db, "PRAGMA nosuchschema.busy_timeout = 5");
  answer(db, "PRAGMA temp.foreign_keys = ON");
  answer(db, "PRAGMA foreign_keys");
  must(db, "PRAGMA foreign_keys = OFF");
  close_db(db);
}

static void p6(void) {
  printf("\nP6. foreign_keys inside a transaction\n");
  sqlite3 *db = open_at("p6.db");
  must(db, "CREATE TABLE p(id INTEGER PRIMARY KEY); CREATE TABLE c(pid REFERENCES p(id));");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "BEGIN");
  answer(db, "PRAGMA foreign_keys = ON");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "INSERT INTO c VALUES (99)");
  answer(db, "COMMIT");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "PRAGMA foreign_keys = ON");
  answer(db, "SAVEPOINT s");
  answer(db, "PRAGMA foreign_keys = OFF");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "INSERT INTO c VALUES (98)");
  answer(db, "ROLLBACK");
  answer(db, "PRAGMA foreign_keys");

  printf("\nP6b. defer_foreign_keys across statements and transactions\n");
  answer(db, "PRAGMA defer_foreign_keys = ON");
  answer(db, "PRAGMA defer_foreign_keys");
  answer(db, "SELECT 1");
  answer(db, "PRAGMA defer_foreign_keys");
  answer(db, "INSERT INTO p VALUES (1)");
  answer(db, "PRAGMA defer_foreign_keys");
  answer(db, "BEGIN");
  answer(db, "PRAGMA defer_foreign_keys = ON");
  answer(db, "INSERT INTO c VALUES (2)");
  answer(db, "INSERT INTO p VALUES (2)");
  answer(db, "PRAGMA defer_foreign_keys");
  answer(db, "COMMIT");
  answer(db, "PRAGMA defer_foreign_keys");
  answer(db, "BEGIN");
  answer(db, "PRAGMA defer_foreign_keys = ON");
  answer(db, "ROLLBACK");
  answer(db, "PRAGMA defer_foreign_keys");

  printf("\nP6c. journal_mode and synchronous inside a transaction that hasn't written\n");
  answer(db, "BEGIN");
  answer(db, "PRAGMA journal_mode = WAL");
  answer(db, "PRAGMA journal_mode = TRUNCATE");
  answer(db, "PRAGMA journal_mode");
  answer(db, "PRAGMA synchronous = OFF");
  answer(db, "ROLLBACK");
  answer(db, "PRAGMA journal_mode = DELETE");

  printf("\nP6d. journal_mode and other settings inside a transaction that has written\n");
  answer(db, "BEGIN");
  answer(db, "INSERT INTO p VALUES (3)");
  answer(db, "PRAGMA journal_mode = WAL");
  answer(db, "PRAGMA journal_mode");
  answer(db, "PRAGMA synchronous = OFF");
  answer(db, "PRAGMA synchronous");
  answer(db, "PRAGMA busy_timeout = 250");
  answer(db, "PRAGMA user_version = 9");
  answer(db, "ROLLBACK");
  answer(db, "PRAGMA synchronous");
  answer(db, "PRAGMA busy_timeout");
  answer(db, "PRAGMA user_version");
  close_db(db);
}

static void p7(void) {
  printf("\nP7. Bound parameters, a schema name, and the grammar of a value\n");
  sqlite3 *db = open_at("p7.db");
  must(db, "CREATE TABLE k(x)");
  answer(db, "PRAGMA busy_timeout = ?");
  answer(db, "PRAGMA busy_timeout = ?1");
  answer(db, "PRAGMA busy_timeout = :t");
  answer(db, "PRAGMA busy_timeout(?)");
  answer(db, "PRAGMA user_version = ?");
  answer(db, "PRAGMA main.user_version = ?");
  answer(db, "PRAGMA main.user_version = 5");
  answer(db, "PRAGMA main.user_version");
  answer(db, "PRAGMA \"main\".user_version");
  answer(db, "PRAGMA user_version");
  answer(db, "PRAGMA temp.user_version");
  answer(db, "PRAGMA main.busy_timeout = 77");
  answer(db, "PRAGMA busy_timeout");
  answer(db, "PRAGMA main.foreign_keys = ON");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "PRAGMA foreign_keys = OFF");
  answer(db, "PRAGMA busy_timeout = 1 + 1");
  answer(db, "PRAGMA busy_timeout = (5)");
  answer(db, "PRAGMA busy_timeout = NULL");
  answer(db, "PRAGMA busy_timeout =");
  answer(db, "PRAGMA busy_timeout()");
  answer(db, "PRAGMA busy_timeout = -0");
  answer(db, "PRAGMA busy_timeout = +300");
  answer(db, "PRAGMA busy_timeout(400)");
  answer(db, "PRAGMA busy_timeout = '500'");
  answer(db, "PRAGMA busy_timeout = \"600\"");
  answer(db, "PRAGMA busy_timeout = x'37'");
  answer(db, "PRAGMA busy_timeout = 700;");
  answer(db, "PRAGMA busy_timeout = 800 -- a comment");
  answer(db, "PRAGMA journal_mode = DELETE");
  answer(db, "PRAGMA cache_size = DEFAULT");
  answer(db, "PRAGMA cache_size");
  answer(db, "PRAGMA foreign_keys = ON");
  answer(db, "PRAGMA foreign_keys = DEFAULT");
  answer(db, "PRAGMA foreign_keys");
  close_db(db);
}

static void p8(void) {
  printf("\nP8. Case, in names and values, and in what comes back\n");
  sqlite3 *db = open_at("p8.db");
  must(db, "CREATE TABLE k(x)");
  answer(db, "PRAGMA FOREIGN_KEYS = on");
  answer(db, "PRAGMA Foreign_Keys");
  answer(db, "PRAGMA foreign_keys = Off");
  answer(db, "PRAGMA foreign_keys");
  answer(db, "PRAGMA Journal_Mode = Wal");
  answer(db, "PRAGMA journal_mode = 'DELETE'");
  answer(db, "PRAGMA journal_mode = \"Truncate\"");
  answer(db, "PRAGMA JOURNAL_MODE");
  answer(db, "PRAGMA journal_mode = delete");
  answer(db, "PRAGMA locking_mode = Exclusive");
  answer(db, "PRAGMA LOCKING_MODE");
  answer(db, "PRAGMA locking_mode = normal");
  answer(db, "PRAGMA synchronous = Normal");
  answer(db, "PRAGMA SYNCHRONOUS");
  answer(db, "PRAGMA temp_store = Memory");
  answer(db, "PRAGMA temp_store");
  answer(db, "PRAGMA secure_delete = FAST");
  answer(db, "PRAGMA secure_delete");
  answer(db, "PRAGMA MAIN.User_Version = 3");
  answer(db, "PRAGMA Main.USER_VERSION");
  answer(db, "PRAGMA BUSY_TIMEOUT = 10");
  answer(db, "PRAGMA Busy_Timeout");
  close_db(db);
}

static void p9(void) {
  printf("\nP9. Reading settings through table-valued pragma functions\n");
  sqlite3 *db = open_at("p9.db");
  must(db, "CREATE TABLE k(x); PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 321; PRAGMA user_version = 8;");
  const char *names[] = {"foreign_keys", "busy_timeout", "synchronous", "cache_size", "temp_store",
                         "recursive_triggers", "defer_foreign_keys", "query_only", "trusted_schema",
                         "secure_delete", "automatic_index", "journal_mode", "user_version",
                         "application_id", "locking_mode", NULL};
  for (int i = 0; names[i]; i++) {
    char sql[128];
    snprintf(sql, sizeof sql, "SELECT * FROM pragma_%s", names[i]);
    answer(db, sql);
  }
  answer(db, "SELECT * FROM pragma_user_version('main')");
  answer(db, "SELECT * FROM pragma_user_version(5)");
  answer(db, "PRAGMA user_version");
  answer(db, "SELECT * FROM pragma_busy_timeout(5)");
  answer(db, "SELECT * FROM pragma_cache_size(?)");
  answer_bound(db, "SELECT name FROM pragma_table_info(?)", "k");
  answer_bound(db, "SELECT * FROM pragma_user_version(?)", "main");
  answer(db, "SELECT * FROM main.pragma_user_version");
  close_db(db);
}

static void p10(void) {
  printf("\nP10. query_only refusing a write\n");
  sqlite3 *db = open_at("p10.db");
  must(db, "CREATE TABLE k(x)");
  answer(db, "PRAGMA query_only = ON");
  answer(db, "INSERT INTO k VALUES (1)");
  answer(db, "CREATE TABLE k2(x)");
  answer(db, "PRAGMA user_version = 4");
  answer(db, "PRAGMA user_version");
  answer(db, "BEGIN IMMEDIATE");
  answer(db, "ROLLBACK");
  answer(db, "CREATE TEMP TABLE tt(x)");
  answer(db, "PRAGMA query_only = OFF");
  close_db(db);
}

static void p11(void) {
  printf("\nP11. journal_mode=wal on :memory:, and on a temporary database\n");
  sqlite3 *db = open_at(":memory:");
  answer(db, "PRAGMA journal_mode");
  answer(db, "PRAGMA journal_mode = wal");
  answer(db, "PRAGMA journal_mode");
  answer(db, "PRAGMA journal_mode = delete");
  answer(db, "PRAGMA journal_mode = off");
  answer(db, "PRAGMA journal_mode");
  close_db(db);
}

static void p12(void) {
  printf("\nP12. Set on a file holding a table, then VACUUM, then a reopen\n");
  const struct setting deferred[] = {
    {"page_size", "8192"}, {"auto_vacuum", "FULL"}, {"encoding", "'UTF-16le'"},
  };
  for (int i = 0; i < 3; i++) {
    char file[64], sql[256];
    const struct setting *s = &deferred[i];
    snprintf(file, sizeof file, "p12-%d.db", i);
    printf("\n P12.%d %s = %s\n", i + 1, s->name, s->value);
    sqlite3 *a = open_at(file);
    must(a, "CREATE TABLE k(x); INSERT INTO k VALUES ('one'), ('two');");
    snprintf(sql, sizeof sql, "PRAGMA %s", s->name);
    printf("  [default]"); answer(a, sql);
    snprintf(sql, sizeof sql, "PRAGMA %s = %s", s->name, s->value);
    printf("  [set]    "); answer(a, sql);
    snprintf(sql, sizeof sql, "PRAGMA %s", s->name);
    printf("  [read]   "); answer(a, sql);
    printf("  [vacuum] "); answer(a, "VACUUM");
    printf("  [read]   "); answer(a, sql);
    printf("  [rows]   "); answer(a, "SELECT group_concat(x) FROM k");
    close_db(a);
    sqlite3 *b = open_at(file);
    printf("  [reopen] "); answer(b, sql);
    close_db(b);
  }
}

static void txn_line(sqlite3 *db) {
  int s = sqlite3_txn_state(db, "main");
  printf("    autocommit %d, txn_state(main) %s\n", sqlite3_get_autocommit(db),
         s == SQLITE_TXN_NONE ? "NONE" : s == SQLITE_TXN_READ ? "READ" : s == SQLITE_TXN_WRITE ? "WRITE" : "-1");
}

static void p13(void) {
  printf("\nP13. journal_mode set in autocommit while a SELECT on the same connection holds a row\n");
  const char *modes[] = {"wal", "truncate"};
  for (int i = 0; i < 2; i++) {
    char file[64], sql[64];
    snprintf(file, sizeof file, "p13-%d.db", i);
    snprintf(sql, sizeof sql, "PRAGMA journal_mode = %s", modes[i]);
    printf("\n P13.%d %s\n", i + 1, sql);
    sqlite3 *db = open_at(file);
    must(db, "CREATE TABLE k(x); INSERT INTO k VALUES (1), (2);");
    sqlite3_stmt *reader = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT x FROM k", -1, &reader, NULL);
    if (rc != SQLITE_OK) { fprintf(stderr, "p13 prepare: rc %d\n", rc); exit(2); }
    rc = sqlite3_step(reader);
    printf("  reader: SELECT x FROM k, step 1: rc %d %s\n", rc, code_name(rc));
    if (rc != SQLITE_ROW) exit(2);
    txn_line(db);
    answer(db, sql);
    answer(db, "PRAGMA journal_mode");
    txn_line(db);
    rc = sqlite3_finalize(reader);
    printf("  reader: finalize rc %d\n", rc);
    txn_line(db);
    answer(db, "PRAGMA journal_mode");
    answer(db, sql);
    answer(db, "PRAGMA journal_mode");
    close_db(db);
  }
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: pragmas DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  p1(); p2(); p3(); p4(); p5(); p6(); p7(); p8(); p9(); p10(); p11(); p12(); p13();
  return 0;
}
