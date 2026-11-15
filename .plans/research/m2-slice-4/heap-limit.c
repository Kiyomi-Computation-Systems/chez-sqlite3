/* M2 slice 4 research: can running out of memory be caused at run time,
   after sqlite3_initialize, with no allocator of our own? It sets
   sqlite3_hard_heap_limit64 just above sqlite3_memory_used, between a step
   and a column read, as a suite could through the FFI.

   With the argument memstatus-off, it first turns SQLite's memory count off
   (sqlite3_config(SQLITE_CONFIG_MEMSTATUS, 0), before initialize), as a
   build with SQLITE_DEFAULT_MEMSTATUS=0 has it, such as Apple's.

   Build and run, from the worktree's root, inside scripts/guix-env:
     $CC -O1 -Wall -Werror -I$GUIX_ENVIRONMENT/include -o build/m2s4/heap-limit-guix \
       .plans/research/m2-slice-4/heap-limit.c $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 \
       -Wl,-rpath,$GUIX_ENVIRONMENT/lib
     $CC -O1 -Wall -Werror -Ibuild/m2s4-floor/sqlite-amalgamation-3450100 \
       -o build/m2s4/heap-limit-floor .plans/research/m2-slice-4/heap-limit.c \
       $PWD/build/m2s4-floor/libsqlite3-floor.so -Wl,-rpath,$PWD/build/m2s4-floor
   then each binary with no argument, and with memstatus-off. */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void one_read(sqlite3 *db, int n) {
  sqlite3_stmt *st = NULL;
  char *v = malloc(n);
  int rc;
  memset(v, 'y', n);
  rc = sqlite3_prepare_v2(db, "select ?1", -1, &st, NULL);
  printf("  prepare %d\n", rc);
  rc = sqlite3_bind_text64(st, 1, v, n, SQLITE_TRANSIENT, SQLITE_UTF8);
  printf("  bind text64 of %d bytes with its length %d\n", n, rc);
  rc = sqlite3_step(st);
  printf("  step %d, type %d\n", rc, sqlite3_column_type(st, 0));
  {
    sqlite3_int64 used = sqlite3_memory_used();
    sqlite3_int64 was = sqlite3_hard_heap_limit64(used + 1000);
    sqlite3_int64 now = sqlite3_hard_heap_limit64(-1);
    const unsigned char *t;
    printf("  memory_used %s; hard limit was %lld, set to used + 1000, reads %s\n",
           used > 0 ? "above 0" : "0", (long long)was,
           now == used + 1000 ? "used + 1000" : "something else");
    t = sqlite3_column_text(st, 0);
    printf("  column_text %s; errcode %d, extended %d, errmsg \"%s\"\n",
           t ? "a pointer" : "NULL", sqlite3_errcode(db), sqlite3_extended_errcode(db),
           sqlite3_errmsg(db));
    printf("  type after %d\n", sqlite3_column_type(st, 0));
    sqlite3_hard_heap_limit64(0);
    printf("  hard limit back to %lld\n", (long long)sqlite3_hard_heap_limit64(-1));
  }
  rc = sqlite3_reset(st);
  printf("  reset %d\n", rc);
  rc = sqlite3_reset(st);
  printf("  reset again %d\n", rc);
  rc = sqlite3_step(st);
  printf("  step %d, column_text %s\n", rc, sqlite3_column_text(st, 0) ? "a pointer" : "NULL");
  rc = sqlite3_finalize(st);
  printf("  finalize %d\n", rc);
  free(v);
}

int main(int argc, char **argv) {
  sqlite3 *db;
  int off = argc > 1 && strcmp(argv[1], "memstatus-off") == 0;
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    printf("header %d, library %d: refused\n", SQLITE_VERSION_NUMBER, sqlite3_libversion_number());
    return 4;
  }
  printf("libversion %s\nsourceid %s\n", sqlite3_libversion(), sqlite3_sourceid());
  if (off) printf("config MEMSTATUS 0: %d\n", sqlite3_config(SQLITE_CONFIG_MEMSTATUS, 0));
  printf("initialize %d\n", sqlite3_initialize());
  if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 5;
  printf("memory count %s\n", off ? "off" : "on (the default)");
  printf("[a 100000-byte TEXT read through select ?1]\n");
  one_read(db, 100000);
  printf("[a 5-byte TEXT read through select ?1]\n");
  one_read(db, 5);
  printf("close %d\n", sqlite3_close(db));
  return 0;
}
