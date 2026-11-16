/* levels.c: the failures M3 slice 4 cites, run inside with-transaction's
 * own statements, at the outer level and at a nested one, each followed by
 * what ADR-0017 has with-transaction issue on that exit.
 *
 *   levels DIR       DIR: a fresh directory for this run's databases
 *
 * The research measured these failures inside a deferred BEGIN, or a
 * SAVEPOINT that began the transaction (single txn-errors, txn-special,
 * txn-open-stmts). with-transaction begins with BEGIN IMMEDIATE by default,
 * and nests with SAVEPOINT chez_sqlite3_N inside a transaction already open.
 *
 *   outer   BEGIN IMMEDIATE; INSERT INTO t VALUES ('outer'); the failure
 *   nested  BEGIN IMMEDIATE; INSERT INTO t VALUES ('outer');
 *           SAVEPOINT chez_sqlite3_1; INSERT INTO t VALUES ('inner'); the failure
 *
 * Then, for a body that raises: autocommit read; at 0 the level rolled back,
 * ROLLBACK, or ROLLBACK TO chez_sqlite3_1 then RELEASE chez_sqlite3_1; at 1
 * nothing issued. For a body that returns: autocommit read; at 0 the level
 * committed, COMMIT or RELEASE chez_sqlite3_1; a commit that fails with
 * autocommit 0 after it rolled back as a raise's; at 1 nothing issued
 * (&sqlite-transaction-ended). After a nested level, the outer level is
 * still the caller's: what this connection sees, then COMMIT, as a caller
 * that caught the condition, and a commit that fails rolled back.
 *
 * Where nothing is issued, the statement a mutant that reads no autocommit
 * would issue is run last, after every view, and its answer printed: the
 * rows of the M3 plan's section 4.8 that read the connection's extended code.
 *
 * Methods, as the research's:
 *   plain   prepare, step until not ROW, finalize
 *   heap    the hard heap limit at memory_used + 1000, set after the prepare
 *           and kept across the step, then set back to 0 (txn-special N),
 *           and the soft limit set to 0 after it: the hard limit's lift
 *           alone leaves SQLite's memory pressure on for the process, and a
 *           writer's page fetches then took the lock another connection's
 *           read needs (peer-view.c, J1 against J2)
 *   column  a statement stepped to a row; sqlite3_column_text under the heap
 *           limit around that one call (as chez-sqlite3 reads TEXT); then
 *           reset, finalize, or nothing until the exit has run (unfinished)
 *   intr    sqlite3_interrupt from a progress handler at its 50th call, one
 *           call per 100 opcodes (txn-special I)
 *   full    PRAGMA max_page_count set to PRAGMA page_count after the markers
 *   held    an INSERT ... RETURNING stepped once and held across the exit
 *
 * No call with a side effect stands beside another in one argument list:
 * each answer is read into a variable first.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dir;
static sqlite3 *db, *db2;

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
  sqlite3 *d = NULL;
  snprintf(path, sizeof path, "%s/%s", dir, name);
  int rc = sqlite3_open_v2(path, &d, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open %s: rc %d\n", name, rc); exit(2); }
  return d;
}

static void must(sqlite3 *d, const char *sql) {
  char *msg = NULL;
  if (sqlite3_exec(d, sql, NULL, NULL, &msg) != SQLITE_OK) {
    fprintf(stderr, "setup failed: %s: %s\n", sql, msg ? msg : "?");
    exit(2);
  }
}

static long long one_int(sqlite3 *d, const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(d, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "%s: prepare %d\n", sql, rc); exit(2); }
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) { fprintf(stderr, "%s: step %d\n", sql, rc); exit(2); }
  long long v = sqlite3_column_int64(st, 0);
  rc = sqlite3_finalize(st);
  if (rc != SQLITE_OK) { fprintf(stderr, "%s: finalize %d\n", sql, rc); exit(2); }
  return v;
}

static void state(const char *when) {
  int ac = sqlite3_get_autocommit(db);
  printf("    %s: autocommit %d\n", when, ac);
}

static void seen(sqlite3 *d, const char *who) {
  const char *sql = "SELECT (SELECT coalesce(group_concat(x, ','), '(none)') FROM "
                    "(SELECT x FROM t ORDER BY x)), (SELECT count(*) FROM b), "
                    "(SELECT count(*) FROM r), "
                    "(SELECT group_concat(x, ',') FROM (SELECT x FROM u ORDER BY x)), "
                    "(SELECT count(*) FROM bn), (SELECT count(*) FROM uc), "
                    "(SELECT count(*) FROM ua), (SELECT count(*) FROM uf), "
                    "(SELECT count(*) FROM ui), (SELECT count(*) FROM ci), "
                    "(SELECT sum(length(x)) FROM src)";
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(d, sql, -1, &st, NULL);
  if (rc != SQLITE_OK) { printf("    %s sees: prepare rc %d \"%s\"\n", who, rc, sqlite3_errmsg(d)); return; }
  rc = sqlite3_step(st);
  if (rc != SQLITE_ROW) {
    printf("    %s sees: step rc %d \"%s\"\n", who, rc, sqlite3_errmsg(d));
    sqlite3_finalize(st);
    return;
  }
  const char *rows = (const char *)sqlite3_column_text(st, 0);
  char copy[256];
  snprintf(copy, sizeof copy, "%s", rows ? rows : "NULL");
  long long nb = sqlite3_column_int64(st, 1);
  long long nr = sqlite3_column_int64(st, 2);
  const char *urows = (const char *)sqlite3_column_text(st, 3);
  char ucopy[256];
  snprintf(ucopy, sizeof ucopy, "%s", urows ? urows : "NULL");
  long long n4 = sqlite3_column_int64(st, 4), n5 = sqlite3_column_int64(st, 5);
  long long n6 = sqlite3_column_int64(st, 6), n7 = sqlite3_column_int64(st, 7);
  long long n8 = sqlite3_column_int64(st, 8), n9 = sqlite3_column_int64(st, 9);
  long long n10 = sqlite3_column_int64(st, 10);
  rc = sqlite3_finalize(st);
  printf("    %s sees: t %s; b %lld rows; r %lld rows; u %s; bn %lld, uc %lld, ua %lld, uf %lld, "
         "ui %lld, ci %lld rows; src %lld bytes\n", who, copy, nb, nr, ucopy, n4, n5, n6, n7, n8, n9, n10);
}

/* issue: one of with-transaction's own statements, prepared PERSISTENT as
 * the cache prepares, stepped once, finalized. Its step's code. */
static int issue(const char *sql) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &st, NULL);
  if (rc != SQLITE_OK) {
    int ext = sqlite3_extended_errcode(db);
    printf("    issue %s: prepare rc %d, extended %d, \"%s\"\n", sql, rc, ext, sqlite3_errmsg(db));
    return rc;
  }
  rc = sqlite3_step(st);
  int ext = sqlite3_extended_errcode(db);
  if (rc == SQLITE_DONE) printf("    issue %s: 101\n", sql);
  else printf("    issue %s: step rc %d, extended %d, \"%s\"\n", sql, rc, ext, sqlite3_errmsg(db));
  int f = sqlite3_finalize(st);
  int fext = sqlite3_extended_errcode(db);
  if (f != SQLITE_OK) printf("      its finalize: rc %d, extended %d\n", f, fext);
  return rc;
}

enum method { PLAIN, HEAP, COLUMN_RESET, COLUMN_FINALIZE, COLUMN_UNFINISHED, INTR, FULL, HELD };
enum exit_how { RAISE, RETURN };

static int progress_calls = 0;
static int on_progress(void *arg) {
  (void)arg;
  progress_calls++;
  if (progress_calls == 50) sqlite3_interrupt(db);
  return 0;
}

static const char *big_text;   /* 100,000 bytes of 'a' */
static sqlite3_stmt *pending;  /* a statement the exit runs beside */

/* failure: the body's failing statement by METHOD. Prints its answer, its
 * finalize's, and the connection's extended code after the finalize. */
static void failure(const char *sql, enum method m) {
  sqlite3_stmt *st = NULL;
  printf("  the body: %s\n", sql);
  if (m == FULL) {
    long long pages = one_int(db, "PRAGMA page_count");
    char set[64];
    snprintf(set, sizeof set, "PRAGMA max_page_count = %lld", pages);
    long long now = one_int(db, set);
    printf("    (max_page_count set to page_count: %lld)\n", now);
  }
  int rc = sqlite3_prepare_v3(db, sql, -1, 0, &st, NULL);
  if (rc != SQLITE_OK) {
    int ext = sqlite3_extended_errcode(db);
    printf("    prepare: rc %d, extended %d, \"%s\"\n", rc, ext, sqlite3_errmsg(db));
    return;
  }
  if (strstr(sql, "?1")) {
    int b = sqlite3_bind_text64(st, 1, big_text, 100000, SQLITE_STATIC, SQLITE_UTF8);
    if (b != SQLITE_OK) { fprintf(stderr, "bind %d\n", b); exit(2); }
  }
  if (m == COLUMN_RESET || m == COLUMN_FINALIZE || m == COLUMN_UNFINISHED) {
    rc = sqlite3_step(st);
    printf("    step: rc %d\n", rc);
    long long limit = sqlite3_memory_used() + 1000;
    sqlite3_hard_heap_limit64(limit);
    const unsigned char *p = sqlite3_column_text(st, 0);
    int ext = sqlite3_extended_errcode(db);
    long long kept = sqlite3_hard_heap_limit64(-1);
    sqlite3_hard_heap_limit64(0);
    sqlite3_soft_heap_limit64(0);
    long long lifted = sqlite3_hard_heap_limit64(-1);
    printf("    sqlite3_column_text under the limit: %s, extended %d; the limit %s straight after, %lld once lifted\n",
           p ? "a pointer" : "NULL", ext, kept == limit ? "still in force" : "changed", lifted);
    state("after the read");
    if (m == COLUMN_RESET) {
      int r = sqlite3_reset(st);
      printf("    reset: rc %d\n", r);
      state("after the reset");
      int f = sqlite3_finalize(st);
      printf("    finalize: rc %d\n", f);
    } else if (m == COLUMN_FINALIZE) {
      int f = sqlite3_finalize(st);
      printf("    finalize: rc %d\n", f);
    } else {
      int busy = sqlite3_stmt_busy(st);
      printf("    left unfinished: stmt_busy %d\n", busy);
      pending = st;
    }
    return;
  }
  if (m == HELD) {
    rc = sqlite3_step(st);
    int busy = sqlite3_stmt_busy(st);
    printf("    step: rc %d, row %d, stmt_busy %d; held\n", rc,
           rc == SQLITE_ROW ? sqlite3_column_int(st, 0) : -1, busy);
    pending = st;
    return;
  }
  long long limit = 0, kept = 0;
  if (m == HEAP) { limit = sqlite3_memory_used() + 1000; sqlite3_hard_heap_limit64(limit); }
  if (m == INTR) { progress_calls = 0; sqlite3_progress_handler(db, 100, on_progress, NULL); }
  int rows = 0;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) rows++;
  int ext = sqlite3_extended_errcode(db);
  char msg[256];
  snprintf(msg, sizeof msg, "%s", sqlite3_errmsg(db));
  if (m == HEAP) {
    kept = sqlite3_hard_heap_limit64(-1);
    sqlite3_hard_heap_limit64(0);
    sqlite3_soft_heap_limit64(0);
    long long lifted = sqlite3_hard_heap_limit64(-1);
    printf("    (the limit %s when the step returned; %lld once lifted)\n",
           kept == limit ? "still in force" : "changed", lifted);
  }
  if (m == INTR) {
    sqlite3_progress_handler(db, 0, NULL, NULL);
    printf("    (progress calls: %d)\n", progress_calls);
  }
  if (rows) printf("    rows: %d\n", rows);
  if (rc == SQLITE_DONE) printf("    step: 101\n");
  else printf("    step: rc %d, extended %d, \"%s\"\n", rc, ext, msg);
  int f = sqlite3_finalize(st);
  int fext = sqlite3_extended_errcode(db);
  printf("    finalize: rc %d; the connection's extended code then %d\n", f, fext);
}

static void finish_pending(void) {
  if (!pending) return;
  int r = sqlite3_step(pending);
  int f = sqlite3_finalize(pending);
  int fext = sqlite3_extended_errcode(db);
  printf("    the held statement afterwards: step rc %d, finalize rc %d, extended then %d\n", r, f, fext);
  pending = NULL;
}

/* the level's statements */
static const char *commit_of(int nested) { return nested ? "RELEASE chez_sqlite3_1" : "COMMIT"; }

static void rollback_level(int nested) {
  if (nested) { issue("ROLLBACK TO chez_sqlite3_1"); issue("RELEASE chez_sqlite3_1"); }
  else issue("ROLLBACK");
}

static void one(const char *id, const char *title, const char *extra, const char *sql,
                enum method m, enum exit_how how, int nested, const char *after_sql) {
  char name[64];
  snprintf(name, sizeof name, "%s-%s.db", id, nested ? "nested" : "outer");
  printf("\n%s, %s. %s\n", id, nested ? "nested" : "outer", title);
  db = open_at(name);
  db2 = open_at(name);
  must(db, "PRAGMA foreign_keys = ON");
  must(db, "CREATE TABLE t(x); CREATE TABLE b(x); CREATE TABLE r(x); CREATE TABLE u(x UNIQUE); "
           "INSERT INTO u VALUES (1), (2); CREATE TABLE src(x); "
           "INSERT INTO src SELECT replace(hex(zeroblob(1500)), '0', 'a') FROM "
           "(WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10) SELECT i FROM n); "
           "CREATE TABLE p(id INTEGER PRIMARY KEY); "
           "CREATE TABLE c(pid REFERENCES p(id) DEFERRABLE INITIALLY DEFERRED); "
           "CREATE TRIGGER tr BEFORE INSERT ON u WHEN new.x = 99 "
           "BEGIN SELECT RAISE(ROLLBACK, 'trigger said rollback'); END; "
           "CREATE TABLE bn(x NOT NULL); "
           "CREATE TABLE uc(x UNIQUE NOT NULL CHECK (x < 1000)); INSERT INTO uc VALUES (1); "
           "CREATE TABLE ua(x); CREATE TRIGGER ta BEFORE INSERT ON ua WHEN new.x = 99 "
           "BEGIN SELECT RAISE(ABORT, 'trigger said abort'); END; "
           "CREATE TABLE uf(x); CREATE TRIGGER tf BEFORE INSERT ON uf WHEN new.x = 99 "
           "BEGIN SELECT RAISE(FAIL, 'trigger said fail'); END; "
           "CREATE TABLE ui(x); CREATE TRIGGER ti BEFORE INSERT ON ui WHEN new.x = 99 "
           "BEGIN SELECT RAISE(IGNORE); END; "
           "CREATE TABLE ci(pid REFERENCES p(id));");
  if (extra) must(db, extra);
  issue("BEGIN IMMEDIATE");
  must(db, "INSERT INTO t VALUES ('outer')");
  if (nested) { issue("SAVEPOINT chez_sqlite3_1"); must(db, "INSERT INTO t VALUES ('inner')"); }
  state("the level begun, its marker written");
  failure(sql, m);
  if (after_sql) {
    printf("  the body carries on: %s\n", after_sql);
    must(db, after_sql);
  }
  int ac = sqlite3_get_autocommit(db);
  printf("  the body %s; autocommit read: %d\n", how == RAISE ? "raises" : "returns", ac);
  const char *mutant = NULL;
  if (how == RAISE) {
    if (ac == 0) { printf("  the exit: the level rolled back\n"); rollback_level(nested); }
    else { printf("  the exit: nothing issued\n"); mutant = nested ? "ROLLBACK TO chez_sqlite3_1" : "ROLLBACK"; }
  } else {
    if (ac == 0) {
      printf("  the exit: the level committed\n");
      int rc = issue(commit_of(nested));
      if (rc != SQLITE_DONE) {
        int ac2 = sqlite3_get_autocommit(db);
        printf("  the commit failed; autocommit read: %d\n", ac2);
        if (ac2 == 0) { printf("  the failed commit: the level rolled back, then its failure raised\n"); rollback_level(nested); }
        else printf("  the failed commit: nothing more issued, its failure raised\n");
      }
    } else {
      printf("  the exit: nothing issued, &sqlite-transaction-ended\n");
      mutant = commit_of(nested);
    }
  }
  state("after the exit");
  seen(db, "db");
  seen(db2, "db2");
  if (nested && sqlite3_get_autocommit(db) == 0) {
    printf("  the outer level, the caller's: COMMIT\n");
    int rc = issue("COMMIT");
    if (rc != SQLITE_DONE && sqlite3_get_autocommit(db) == 0) {
      printf("  the outer COMMIT failed with the transaction open: ROLLBACK\n");
      issue("ROLLBACK");
    }
    state("after the outer level");
    seen(db2, "db2");
  }
  finish_pending();
  if (mutant) {
    printf("  a mutant that reads no autocommit issues:\n");
    issue(mutant);
    int ext = sqlite3_extended_errcode(db);
    printf("    the connection's extended code then: %d\n", ext);
  }
  int rc2 = sqlite3_close(db2);
  int rc1 = sqlite3_close(db);
  if (rc1 != SQLITE_OK || rc2 != SQLITE_OK) { fprintf(stderr, "close %d %d\n", rc1, rc2); exit(2); }
}

static void both(const char *id, const char *title, const char *extra, const char *sql,
                 enum method m, enum exit_how how, const char *after_sql) {
  one(id, title, extra, sql, m, how, 0, after_sql);
  one(id, title, extra, sql, m, how, 1, after_sql);
}

#define CTE "WITH RECURSIVE k(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM k WHERE i < 1000000) "

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: levels DIR\n"); return 2; }
  dir = argv[1];
  version_lines();
  char *text = malloc(100000);
  if (!text) return 2;
  memset(text, 'a', 100000);
  big_text = text;
  int irc = sqlite3_initialize();
  if (irc != SQLITE_OK) { fprintf(stderr, "initialize %d\n", irc); return 2; }

  both("E1", "UNIQUE, default conflict (ABORT)", NULL, "INSERT INTO u VALUES (1)", PLAIN, RAISE, NULL);
  both("E4", "INSERT OR ROLLBACK", NULL, "INSERT OR ROLLBACK INTO u VALUES (1)", PLAIN, RAISE, NULL);
  both("E8", "a trigger's RAISE(ROLLBACK)", NULL, "INSERT INTO u VALUES (99)", PLAIN, RAISE, NULL);
  both("E24", "refused at prepare: no such table", NULL, "INSERT INTO nosuch VALUES (1)", PLAIN, RAISE, NULL);
  both("F1", "FULL, no function, no constraint", NULL, "INSERT INTO b SELECT x FROM src", FULL, RAISE, NULL);
  both("F2", "FULL, one function call", NULL, "INSERT INTO b SELECT lower(x) FROM src", FULL, RAISE, NULL);
  both("N1", "NOMEM by the heap limit, a SELECT reading a table", NULL,
       "SELECT randomblob(100000) FROM src LIMIT 1", HEAP, RAISE, NULL);
  both("N2", "NOMEM by the heap limit, a SELECT reading no table", NULL,
       "SELECT randomblob(100000)", HEAP, RAISE, NULL);
  both("N3", "NOMEM by the heap limit, a multi-row INSERT with a statement journal", NULL,
       "INSERT INTO b SELECT randomblob(100000) FROM src LIMIT 3", HEAP, RAISE, NULL);
  both("N4", "NOMEM by the heap limit, a one-row INSERT", NULL,
       "INSERT INTO b VALUES (randomblob(100000))", HEAP, RAISE, NULL);
  both("G2", "a column read's NOMEM, a SELECT reading a table, then reset", NULL,
       "SELECT ?1 FROM src LIMIT 1", COLUMN_RESET, RAISE, NULL);
  both("G3", "a column read's NOMEM, a SELECT reading a table, then finalize", NULL,
       "SELECT ?1 FROM src LIMIT 1", COLUMN_FINALIZE, RAISE, NULL);
  both("G2u", "a column read's NOMEM, a SELECT reading a table, left unfinished through the exit", NULL,
       "SELECT ?1 FROM src LIMIT 1", COLUMN_UNFINISHED, RAISE, NULL);
  both("G4", "a column read's NOMEM, a SELECT reading no table, then reset", NULL,
       "SELECT ?1", COLUMN_RESET, RAISE, NULL);
  both("G4u", "a column read's NOMEM, a SELECT reading no table, left unfinished through the exit", NULL,
       "SELECT ?1", COLUMN_UNFINISHED, RAISE, NULL);
  both("I1", "an interrupted write", NULL, "INSERT INTO b " CTE "SELECT i FROM k", INTR, RAISE, NULL);
  both("I3", "an interrupted SELECT reading a table", NULL, CTE "SELECT count(*) FROM k, src", INTR, RAISE, NULL);
  both("E13", "a deferred foreign key, the body returns", NULL, "INSERT INTO c VALUES (7)", PLAIN, RETURN, NULL);
  both("O7", "an INSERT ... RETURNING held at its row, the body returns", NULL,
       "INSERT INTO r VALUES (6), (7) RETURNING x", HELD, RETURN, NULL);
  both("L1", "INSERT OR ROLLBACK caught, a later write, the body returns", NULL,
       "INSERT OR ROLLBACK INTO u VALUES (1)", PLAIN, RETURN, "INSERT INTO t VALUES ('after')");
  both("C0", "the control: a write, the body returns", NULL, "INSERT INTO b VALUES (1)", PLAIN, RETURN, NULL);
  both("R0", "the control: a write, the body raises", NULL, "INSERT INTO b VALUES (1)", PLAIN, RAISE, NULL);

  /* The rest of single txn-errors E1 to E25 and txn-special F, G and I,
   * at with-transaction's two levels; the M method needs sqlite3_config,
   * which no suite can call, and E5 and E25 are transactions SAVEPOINT
   * began, which with-transaction never begins. G6 reads by
   * sqlite3_column_text16, which chez-sqlite3 never calls. */
  both("E2", "UNIQUE at the 3rd row of 4, default conflict", NULL,
       "INSERT INTO u VALUES (20), (21), (1), (22)", PLAIN, RAISE, NULL);
  both("E3a", "NOT NULL", NULL, "INSERT INTO bn VALUES (NULL)", PLAIN, RAISE, NULL);
  both("E3b", "CHECK", NULL, "INSERT INTO uc VALUES (5000)", PLAIN, RAISE, NULL);
  both("E6", "INSERT OR FAIL at the 3rd row of 4", NULL,
       "INSERT OR FAIL INTO u VALUES (30), (31), (1), (32)", PLAIN, RAISE, NULL);
  both("E7", "UPDATE OR ROLLBACK", NULL, "UPDATE OR ROLLBACK u SET x = 1 WHERE x = 2", PLAIN, RAISE, NULL);
  both("E9", "a trigger's RAISE(ABORT) at the 3rd row of 4", NULL,
       "INSERT INTO ua VALUES (40), (41), (99), (42)", PLAIN, RAISE, NULL);
  both("E10", "a trigger's RAISE(FAIL) at the 3rd row of 4", NULL,
       "INSERT INTO uf VALUES (50), (51), (99), (52)", PLAIN, RAISE, NULL);
  both("E11", "a trigger's RAISE(IGNORE) at the 3rd row of 4, the body returns", NULL,
       "INSERT INTO ui VALUES (60), (61), (99), (62)", PLAIN, RETURN, NULL);
  both("E12", "an immediate foreign key", NULL, "INSERT INTO ci VALUES (7)", PLAIN, RAISE, NULL);
  both("E14", "integer overflow at the 3rd row of 4", NULL,
       "INSERT INTO b SELECT CASE WHEN v = 3 THEN abs(-9223372036854775807 - 1) ELSE 100 + v END "
       "FROM (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4)", PLAIN, RAISE, NULL);
  both("E15", "FULL, one row, no constraints", NULL, "INSERT INTO b VALUES (zeroblob(100000))", FULL, RAISE, NULL);
  both("E16", "FULL, 100 rows of zeroblob(3000), no constraints", NULL,
       "INSERT INTO b SELECT zeroblob(3000) FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL "
       "SELECT i + 1 FROM n WHERE i < 100) SELECT i FROM n)", FULL, RAISE, NULL);
  both("E17", "FULL, one row, a NOT NULL column", NULL, "INSERT INTO bn VALUES (zeroblob(100000))", FULL, RAISE, NULL);
  both("E18", "FULL, 100 rows of zeroblob(3000), a NOT NULL column", NULL,
       "INSERT INTO bn SELECT zeroblob(3000) FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL "
       "SELECT i + 1 FROM n WHERE i < 100) SELECT i FROM n)", FULL, RAISE, NULL);
  both("E19", "FULL, 800 rows, no function, UNIQUE, NOT NULL and CHECK", NULL,
       "INSERT INTO uc SELECT 100 + i FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL "
       "SELECT i + 1 FROM n WHERE i < 800) SELECT i FROM n)", FULL, RAISE, NULL);
  both("E21", "NOMEM by the heap limit, 3 rows calling randomblob, a NOT NULL column", NULL,
       "INSERT INTO bn SELECT randomblob(100000) FROM (SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3)",
       HEAP, RAISE, NULL);
  both("E22", "NOMEM by the heap limit, 3 rows, UNIQUE, NOT NULL and CHECK", NULL,
       "INSERT INTO uc SELECT 100 + v + 0 * length(randomblob(100000)) FROM "
       "(SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3)", HEAP, RAISE, NULL);
  both("F3", "FULL, one constraint (NOT NULL), no function", NULL, "INSERT INTO bn SELECT x FROM src", FULL, RAISE, NULL);
  both("F4", "FULL, zeroblob(3000) per row of src", NULL, "INSERT INTO b SELECT zeroblob(3000) FROM src", FULL, RAISE, NULL);
  both("F5", "FULL, zeroblob(100000), one row", NULL, "INSERT INTO b VALUES (zeroblob(100000))", FULL, RAISE, NULL);
  both("F6", "FULL, an UPDATE calling no function", NULL, "UPDATE src SET x = x || x", FULL, RAISE, NULL);
  both("F7", "FULL, an UPDATE calling lower", NULL, "UPDATE src SET x = lower(x || x)", FULL, RAISE, NULL);
  both("F8", "FULL, an UPDATE calling zeroblob", NULL, "UPDATE src SET x = zeroblob(9000)", FULL, RAISE, NULL);
  both("G5", "a column read's NOMEM, a SELECT reading no table, then finalize", NULL,
       "SELECT ?1", COLUMN_FINALIZE, RAISE, NULL);
  both("I2", "an interrupted write calling a function (a statement journal)", NULL,
       "INSERT INTO b " CTE "SELECT abs(i) FROM k", INTR, RAISE, NULL);
  both("I4", "an interrupted SELECT reading no table", NULL, CTE "SELECT count(*) FROM k", INTR, RAISE, NULL);
  free(text);
  return 0;
}
