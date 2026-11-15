/* P13: what a PRAGMA does to the other statements on its connection, as a
 * statement cache holds them. (The M3 plan, section 8 and section 4.6. The
 * adversarial review of the plan measured it first; this is that measurement
 * in the research's form, with the settings' values set to what they already
 * were as well as changed.)
 *
 *   p13-pragma-expire DIR TIMING     (TIMING unused: nothing here is timed)
 *
 * Each case: a fresh file holding t(x) with 2 rows. S = "SELECT x FROM t" is
 * prepared with SQLITE_PREPARE_PERSISTENT, stepped to done and reset. Then T
 * is prepared, stepped and finalized, or nothing runs, the control. Then S is
 * stepped to done again, with no prepare. The line gives S's
 * SQLITE_STMTSTATUS_REPREPARE count before and after its second step, and the
 * answers. A case "unchanged" first sets the setting to the value T then
 * sets, before S is prepared, so T changes nothing. P13b sets the other
 * values of foreign_keys and trusted_schema, which the plan's second review
 * found expire statements too.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;
static int case_number;

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n", SQLITE_VERSION_NUMBER,
            SQLITE_SOURCE_ID, sqlite3_libversion_number(), sqlite3_sourceid());
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

static int to_done(sqlite3_stmt *st) {
  int rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {}
  return rc;
}

/* one: T between S's two steps; FIRST, when given, run before S is
 * prepared. */
static void one(const char *first, const char *t, const char *label) {
  char file[64];
  snprintf(file, sizeof file, "p13-%d.db", case_number++);
  sqlite3 *db = open_at(file);
  must(db, "CREATE TABLE t(x); INSERT INTO t VALUES (1), (2)");
  if (first) must(db, first);
  sqlite3_stmt *s = NULL;
  if (sqlite3_prepare_v3(db, "SELECT x FROM t", -1, SQLITE_PREPARE_PERSISTENT, &s, NULL)
      != SQLITE_OK) exit(2);
  int r1 = to_done(s);
  int z1 = sqlite3_reset(s);
  int t_rc = -1;
  if (t) {
    sqlite3_stmt *ts = NULL;
    int p = sqlite3_prepare_v2(db, t, -1, &ts, NULL);
    if (p != SQLITE_OK) { fprintf(stderr, "T prepare %d\n", p); exit(2); }
    t_rc = to_done(ts);
    int f = sqlite3_finalize(ts);
    if (f != SQLITE_OK) { fprintf(stderr, "T finalize %d\n", f); exit(2); }
  }
  int before = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int r2 = to_done(s);
  int after = sqlite3_stmt_status(s, SQLITE_STMTSTATUS_REPREPARE, 0);
  int z2 = sqlite3_reset(s);
  int f = sqlite3_finalize(s);
  int c = sqlite3_close(db);
  if (c != SQLITE_OK || f != SQLITE_OK) { fprintf(stderr, "close %d finalize %d\n", c, f); exit(2); }
  printf("  %-44s S first %d, reset %d; T %d; S's reprepares %d, its second step %d, then %d;"
         " reset %d\n", label, r1, z1, t_rc, before, r2, after, z2);
}

struct pair { const char *set; const char *read; };

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: p13-pragma-expire DIR [TIMING]\n"); return 2; }
  dir = argv[1];
  version_lines();
  printf("\nP13. A PRAGMA between a held SELECT's two steps; codes as SQLite answers them\n");
  one(NULL, NULL, "T: nothing (the control)");
  one(NULL, "SELECT 1", "T: SELECT 1");
  static const struct pair changes[] = {
    {"PRAGMA busy_timeout = 5", "PRAGMA busy_timeout"},
    {"PRAGMA foreign_keys = 1", "PRAGMA foreign_keys"},
    {"PRAGMA journal_mode = wal", "PRAGMA journal_mode"},
    {"PRAGMA synchronous = 1", "PRAGMA synchronous"},
    {"PRAGMA temp_store = 2", "PRAGMA temp_store"},
    {"PRAGMA trusted_schema = 0", "PRAGMA trusted_schema"},
    {"PRAGMA cache_size = 123", "PRAGMA cache_size"},
  };
  char label[128];
  for (size_t i = 0; i < sizeof changes / sizeof changes[0]; i++) {
    snprintf(label, sizeof label, "T: %s, a change", changes[i].set);
    one(NULL, changes[i].set, label);
    snprintf(label, sizeof label, "T: %s, unchanged", changes[i].set);
    one(changes[i].set, changes[i].set, label);
    snprintf(label, sizeof label, "T: %s", changes[i].read);
    one(NULL, changes[i].read, label);
  }
  /* The other values of the two that expire: each set from the value it
     changes, and set again to the value it already has. */
  printf("\nP13b. The other values of foreign_keys and trusted_schema\n");
  one("PRAGMA foreign_keys = 1", "PRAGMA foreign_keys = 0", "T: PRAGMA foreign_keys = 0, a change");
  one("PRAGMA foreign_keys = 0", "PRAGMA foreign_keys = 0", "T: PRAGMA foreign_keys = 0, unchanged");
  one("PRAGMA foreign_keys = 1", "PRAGMA foreign_keys = off", "T: PRAGMA foreign_keys = off, a change");
  one("PRAGMA foreign_keys = 0", "PRAGMA foreign_keys = off", "T: PRAGMA foreign_keys = off, unchanged");
  one("PRAGMA trusted_schema = 0", "PRAGMA trusted_schema = 1", "T: PRAGMA trusted_schema = 1, a change");
  one("PRAGMA trusted_schema = 1", "PRAGMA trusted_schema = 1", "T: PRAGMA trusted_schema = 1, unchanged");
  return 0;
}
