/* Trap repro: after a column read runs out of memory, the column reads as
 * NULL. sqlite3_column_text answers NULL and sets SQLITE_NOMEM; then
 * sqlite3_column_type answers SQLITE_NULL (5), a second sqlite3_column_text
 * answers NULL with the code still 7, and sqlite3_reset answers 7, though
 * the step had answered a row. Lookaside is off, so the one allocation the
 * read asks for (a NUL terminator's copy of a TEXT bound with its length)
 * reaches the refusing allocator.
 *
 *   scripts/guix-env sh -c '$CC -O1 -Wall -Werror -I$GUIX_ENVIRONMENT/include \
 *       -o build/m2s4/trap-oom-reread-guix .plans/research/m2-slice-4/trap-oom-reread.c \
 *       $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 -Wl,-rpath,$GUIX_ENVIRONMENT/lib \
 *     && build/m2s4/trap-oom-reread-guix'
 *   scripts/guix-env sh -c '$CC -O1 -Wall -Werror -Ibuild/m2s4-floor/sqlite-amalgamation-3450100 \
 *       -o build/m2s4/trap-oom-reread-floor .plans/research/m2-slice-4/trap-oom-reread.c \
 *       $PWD/build/m2s4-floor/libsqlite3-floor.so \
 *     && build/m2s4/trap-oom-reread-floor'
 */
#include <stdio.h>
#include <string.h>
#include <sqlite3.h>

static sqlite3_mem_methods real;
static volatile int failing = 0;
static void *fail_malloc(int n) { return failing ? 0 : real.xMalloc(n); }
static void *fail_realloc(void *p, int n) { return failing ? 0 : real.xRealloc(p, n); }

int main(void) {
  printf("libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    printf("the library is not the header's\n");
    return 2;
  }
  sqlite3_config(SQLITE_CONFIG_GETMALLOC, &real);
  sqlite3_mem_methods mine = real;
  mine.xMalloc = fail_malloc;
  mine.xRealloc = fail_realloc;
  sqlite3_config(SQLITE_CONFIG_MALLOC, &mine);
  sqlite3_config(SQLITE_CONFIG_LOOKASIDE, 0, 0);
  sqlite3_initialize();

  sqlite3 *db = 0;
  sqlite3_stmt *st = 0;
  sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE, 0);
  sqlite3_prepare_v3(db, "select ?1", -1, 0, &st, 0);
  sqlite3_bind_text64(st, 1, "abcde", 5, SQLITE_TRANSIENT, SQLITE_UTF8);
  int s = sqlite3_step(st);
  int t1 = sqlite3_column_type(st, 0);
  failing = 1;
  const unsigned char *p1 = sqlite3_column_text(st, 0);
  failing = 0;
  int e1 = sqlite3_extended_errcode(db);
  int t2 = sqlite3_column_type(st, 0);
  const unsigned char *p2 = sqlite3_column_text(st, 0);
  int e2 = sqlite3_extended_errcode(db);
  int r = sqlite3_reset(st);
  int s2 = sqlite3_step(st);
  /* The text is copied out before the finalize frees it. */
  const unsigned char *p3 = sqlite3_column_text(st, 0);
  char copy[16] = "NULL";
  if (p3) snprintf(copy, sizeof copy, "\"%s\"", (const char *)p3);
  int f = sqlite3_finalize(st);
  int c = sqlite3_close(db);
  printf("step %d, type %d\n", s, t1);
  printf("column_text while refusing: %s, extended %d\n", p1 ? "a pointer" : "NULL", e1);
  printf("then type %d; column_text again: %s, extended %d\n", t2, p2 ? "a pointer" : "NULL", e2);
  printf("reset %d; step %d; column_text: %s; finalize %d; close %d\n", r, s2, copy, f, c);
  return 0;
}
