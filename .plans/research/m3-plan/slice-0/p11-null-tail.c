/* P11: can a NULL statement leave SQL after its tail? (The M3 plan,
 * section 8; ADR-0016, decision 7.)
 *
 *   p11-null-tail DIR TIMING     (both unused: it opens :memory: only)
 *
 * Each input is prepared on a fresh :memory: connection, once by
 * sqlite3_prepare_v3 with flags 0, as ADR-0014's prepare passes them, and
 * once by sqlite3_prepare_v2, the research's script loop's (single, script).
 * Each line gives the answer, whether the statement is NULL, the tail's byte
 * offset against the input's length, and for a statement its text by
 * sqlite3_sql. The input's bytes are written with C escapes.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static void put_bytes(const char *s, int n) {
  for (int i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c == '\n') printf("\\n");
    else if (c == '\\') printf("\\\\");
    else if (c < 0x20 || c >= 0x7f) printf("\\x%02X", c);
    else putchar(c);
  }
}

static const char *inputs[] = {
  ";",
  ";;",
  " ; ",
  ";; select 2",
  "; select 2",
  "; ;select 2",
  "/* c */ ; select 2",
  "-- c\n; select 2",
  "-- c\nselect 2",
  "/* c */ select 2",
  "\xEF\xBB\xBF; select 2",
  ";;; -- c\n /* d */ ; select 2 ; select 3",
  "select 1; select 2",
  "select 1;; select 2",
};

static void one(const char *sql, int v3) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(":memory:", &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open: rc %d\n", rc); exit(2); }
  sqlite3_stmt *st = NULL;
  const char *tail = NULL;
  int n = (int)strlen(sql);
  if (v3) rc = sqlite3_prepare_v3(db, sql, n + 1, 0, &st, &tail);
  else rc = sqlite3_prepare_v2(db, sql, n + 1, &st, &tail);
  printf("  %s [", v3 ? "v3" : "v2");
  put_bytes(sql, n);
  printf("] (%d bytes): rc %d, %s", n, rc, st ? "a statement" : "NULL");
  if (tail) printf(", tail at byte %d", (int)(tail - sql));
  if (st) {
    const char *text = sqlite3_sql(st);
    printf(", sqlite3_sql [");
    if (text) put_bytes(text, (int)strlen(text));
    printf("]");
  }
  printf("\n");
  if (st) {
    rc = sqlite3_finalize(st);
    if (rc != SQLITE_OK) printf("    finalize rc %d\n", rc);
  }
  rc = sqlite3_close(db);
  if (rc != SQLITE_OK) { fprintf(stderr, "close: rc %d\n", rc); exit(2); }
}

int main(void) {
  version_lines();
  printf("\nP11. What a prepare's tail leaves, a NULL statement's above all\n");
  for (size_t i = 0; i < sizeof inputs / sizeof inputs[0]; i++) {
    one(inputs[i], 1);
    one(inputs[i], 0);
  }
  return 0;
}
