/* M2 slice 4's research, item 6: running out of memory in a column read, on
 * demand, through SQLite's own allocator interface.
 *
 * Before sqlite3_initialize, sqlite3_config(SQLITE_CONFIG_MALLOC) installs
 * SQLite's default allocator wrapped by one that refuses every xMalloc and
 * xRealloc while `failing` is set, and SQLITE_CONFIG_LOOKASIDE turns
 * lookaside off (argv[1] "lookaside-default" keeps it), so a refusal is
 * seen. Each row sets `failing` around one call alone, clears it, and then
 * reads sqlite3_errcode, sqlite3_extended_errcode and sqlite3_errmsg at
 * once. Running out of memory is a failure SQLite is built to survive; no
 * call here is documented as undefined.
 *
 * It is compiled against one library's sqlite3.h and linked to that
 * library, and refuses to run (exit 2) unless sqlite3_libversion_number and
 * sqlite3_sourceid match the header's. dladdr names the file that answered.
 *
 *   scripts/guix-env sh -c '$CC -O1 -Wall -Werror -I$GUIX_ENVIRONMENT/include \
 *       -o build/m2s4/oom-guix .plans/research/m2-slice-4/oom.c \
 *       $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 -Wl,-rpath,$GUIX_ENVIRONMENT/lib -ldl \
 *     && build/m2s4/oom-guix'
 *   scripts/guix-env sh -c '$CC -O1 -Wall -Werror -Ibuild/m2s4-floor/sqlite-amalgamation-3450100 \
 *       -o build/m2s4/oom-floor .plans/research/m2-slice-4/oom.c \
 *       $PWD/build/m2s4-floor/libsqlite3-floor.so -ldl \
 *     && build/m2s4/oom-floor'
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

static sqlite3_mem_methods real;
static volatile int failing = 0;
static long refused = 0;

static void *fail_malloc(int n) {
  if (failing) { refused++; return 0; }
  return real.xMalloc(n);
}
static void *fail_realloc(void *p, int n) {
  if (failing) { refused++; return 0; }
  return real.xRealloc(p, n);
}

/* shown: printable ASCII as itself, any other byte as \xHH, in quotes. */
static void shown(const unsigned char *s, int n) {
  if (!s) { printf("NULL"); return; }
  putchar('"');
  for (int i = 0; i < n; i++) {
    if (s[i] >= 32 && s[i] < 127 && s[i] != '"' && s[i] != '\\') putchar(s[i]);
    else printf("\\x%02x", s[i]);
  }
  putchar('"');
}
static void shown_c(const char *s) { shown((const unsigned char *)s, s ? (int)strlen(s) : 0); }

static void state(sqlite3 *db) {
  int code = sqlite3_errcode(db);
  int ext = sqlite3_extended_errcode(db);
  const char *msg = sqlite3_errmsg(db);
  printf("errcode %d, extended %d, errmsg ", code, ext);
  shown_c(msg);
}

static sqlite3_stmt *prep(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = 0;
  int rc = sqlite3_prepare_v3(db, sql, -1, 0, &st, 0);
  if (rc != SQLITE_OK) { printf("prepare of %s failed: %d %s\n", sql, rc, sqlite3_errmsg(db)); exit(3); }
  return st;
}
static void exec(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = prep(db, sql);
  int s = sqlite3_step(st);
  sqlite3_finalize(st);
  if (s != SQLITE_DONE) { printf("exec of %s: step %d\n", sql, s); exit(3); }
}
/* done_with: steps ST once more, then finalizes it, in that order. */
static void done_with(sqlite3_stmt *st) {
  int s = sqlite3_step(st);
  int f = sqlite3_finalize(st);
  printf("  step %d, finalize %d\n", s, f);
}

/* A column read under refusal: TEXT through column_text or BLOB through
 * column_blob, the code read straight after, then the same read again with
 * nothing refused. */
static void read_row(sqlite3 *db, sqlite3_stmt *st, const char *label, int blob) {
  int type_before = sqlite3_column_type(st, 0);
  long refused_before = refused;
  failing = 1;
  const void *p = blob ? sqlite3_column_blob(st, 0) : (const void *)sqlite3_column_text(st, 0);
  failing = 0;
  printf("[%s] type %d; %s while refusing: %s, %ld allocation(s) refused; ", label, type_before,
         blob ? "column_blob" : "column_text", p ? "a pointer" : "NULL", refused - refused_before);
  state(db);
  int n = sqlite3_column_bytes(st, 0);
  int type_after = sqlite3_column_type(st, 0);
  const void *q = blob ? sqlite3_column_blob(st, 0) : (const void *)sqlite3_column_text(st, 0);
  int n2 = sqlite3_column_bytes(st, 0);
  printf("\n  then column_bytes %d, type %d; read again with nothing refused: %s, %d bytes; ",
         n, type_after, q ? "a pointer" : "NULL", n2);
  state(db);
  printf("\n");
}

int main(int argc, char **argv) {
  Dl_info info;
  int keep_lookaside = argc > 1 && strcmp(argv[1], "lookaside-default") == 0;
  printf("libversion: \"%s\"\nsourceid: \"%s\"\n", sqlite3_libversion(), sqlite3_sourceid());
  printf("header: \"%s\" %d \"%s\"\n", SQLITE_VERSION, SQLITE_VERSION_NUMBER, SQLITE_SOURCE_ID);
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    printf("the library is not the header's\n");
    return 2;
  }
  /* The source id's text lies in the library's own data, so dladdr of it
   * names the library; a function's address, taken here, would name this
   * program's PLT stub. The last two components of the path are printed. */
  if (dladdr((const void *)sqlite3_sourceid(), &info) && info.dli_fname) {
    const char *end = strrchr(info.dli_fname, '/');
    const char *from = info.dli_fname;
    if (end) {
      for (const char *q = info.dli_fname; q < end; q++) if (*q == '/') from = q;
    }
    printf("sqlite3_sourceid's text is in: ...%s\n", from);
  }
  printf("config GETMALLOC %d", sqlite3_config(SQLITE_CONFIG_GETMALLOC, &real));
  sqlite3_mem_methods mine = real;
  mine.xMalloc = fail_malloc;
  mine.xRealloc = fail_realloc;
  printf(", MALLOC %d", sqlite3_config(SQLITE_CONFIG_MALLOC, &mine));
  if (keep_lookaside) printf(", lookaside kept");
  else printf(", LOOKASIDE 0 0: %d", sqlite3_config(SQLITE_CONFIG_LOOKASIDE, 0, 0));
  printf(", initialize %d\n", sqlite3_initialize());

  sqlite3 *db = 0;
  int rc = sqlite3_open_v2(":memory:", &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_MEMORY | SQLITE_OPEN_EXRESCODE, 0);
  if (rc != SQLITE_OK) { printf("open %d\n", rc); return 3; }
  printf("errstr(7): ");
  shown_c(sqlite3_errstr(7));
  printf("\n");

  enum { N = 5000 };
  char *text = malloc(N);
  memset(text, 'a', N);

  /* 1. TEXT bound with its length, then read straight back through select ?1. */
  {
    sqlite3_stmt *st = prep(db, "select ?1");
    int b = sqlite3_bind_text64(st, 1, text, N, SQLITE_TRANSIENT, SQLITE_UTF8);
    int s = sqlite3_step(st);
    printf("1. bind %d, step %d\n", b, s);
    read_row(db, st, "5000-byte TEXT bound with its length, through select ?1", 0);
    done_with(st);
  }
  /* 1b and 1c. The same, then a reset, or a finalize, straight after. */
  {
    sqlite3_stmt *st = prep(db, "select ?1");
    sqlite3_bind_text64(st, 1, text, N, SQLITE_TRANSIENT, SQLITE_UTF8);
    int s = sqlite3_step(st);
    printf("1b. step %d\n", s);
    read_row(db, st, "the same, then a reset", 0);
    int r = sqlite3_reset(st);
    printf("  reset straight after %d; ", r);
    state(db);
    int s2 = sqlite3_step(st);
    printf("\n  then step %d; ", s2);
    state(db);
    printf("\n");
    done_with(st);
  }
  {
    sqlite3_stmt *st = prep(db, "select ?1");
    sqlite3_bind_text64(st, 1, text, N, SQLITE_TRANSIENT, SQLITE_UTF8);
    int s = sqlite3_step(st);
    printf("1c. step %d\n", s);
    read_row(db, st, "the same, then a finalize", 0);
    int f = sqlite3_finalize(st);
    printf("  finalize straight after %d; ", f);
    state(db);
    printf("\n");
  }
  /* 1d. A 5-byte TEXT bound with its length, through select ?1. */
  {
    sqlite3_stmt *st = prep(db, "select ?1");
    int b = sqlite3_bind_text64(st, 1, "abcde", 5, SQLITE_TRANSIENT, SQLITE_UTF8);
    int s = sqlite3_step(st);
    printf("1d. bind %d, step %d\n", b, s);
    read_row(db, st, "5-byte TEXT bound with its length, through select ?1", 0);
    done_with(st);
  }
  /* 2. The same TEXT from a table's row. */
  {
    exec(db, "create table t (x)");
    sqlite3_stmt *ins = prep(db, "insert into t values (?1)");
    sqlite3_bind_text64(ins, 1, text, N, SQLITE_TRANSIENT, SQLITE_UTF8);
    int s0 = sqlite3_step(ins);
    sqlite3_finalize(ins);
    sqlite3_stmt *st = prep(db, "select x from t");
    int s = sqlite3_step(st);
    printf("2. insert %d, step %d\n", s0, s);
    read_row(db, st, "5000-byte TEXT read from a table", 0);
    done_with(st);
  }
  /* 3. A zeroblob, which column_blob expands. */
  {
    sqlite3_stmt *st = prep(db, "select zeroblob(5000)");
    int s = sqlite3_step(st);
    printf("3. step %d\n", s);
    read_row(db, st, "zeroblob(5000)", 1);
    done_with(st);
  }
  /* 4. A BLOB from a table's row. */
  {
    exec(db, "create table b (x)");
    sqlite3_stmt *ins = prep(db, "insert into b values (?1)");
    sqlite3_bind_blob64(ins, 1, text, N, SQLITE_TRANSIENT);
    sqlite3_step(ins);
    sqlite3_finalize(ins);
    sqlite3_stmt *st = prep(db, "select x from b");
    int s = sqlite3_step(st);
    printf("4. step %d\n", s);
    read_row(db, st, "5000-byte BLOB read from a table", 1);
    done_with(st);
  }
  /* 5. sqlite3_column_name with every allocation refused: after prepare, and
   * after a step. Then, to reach the NULL at all, sqlite3_column_name16 first,
   * which converts the name to UTF-16 in place (chez-sqlite3 never calls it):
   * a known error is put on the connection before, to see whether the NULL
   * sets a code. */
  {
    sqlite3_stmt *st = prep(db, "select 1 as plain, 2 as \"\xc3\xa9\xe5\x90\x8d\"");
    for (int phase = 0; phase < 2; phase++) {
      if (phase == 1) printf("5. step %d\n", sqlite3_step(st));
      for (int i = 0; i < 2; i++) {
        long before = refused;
        failing = 1;
        const char *name = sqlite3_column_name(st, i);
        failing = 0;
        printf("5. %s, column %d's name while refusing: ", phase ? "after a step" : "after prepare", i);
        shown_c(name);
        printf(", %ld refused; ", refused - before);
        state(db);
        printf("\n");
      }
    }
    sqlite3_stmt *bad = 0;
    int prc = sqlite3_prepare_v3(db, "select nosuch_col", -1, 0, &bad, 0);
    printf("5. a failed prepare, rc %d: ", prc);
    state(db);
    printf("\n");
    const void *name16 = sqlite3_column_name16(st, 1);
    printf("5. column_name16 of column 1: %s; ", name16 ? "a pointer" : "NULL");
    state(db);
    printf("\n");
    long before = refused;
    failing = 1;
    const char *name = sqlite3_column_name(st, 1);
    failing = 0;
    printf("5. then column_name of column 1 while refusing: ");
    shown_c(name);
    printf(", %ld refused; ", refused - before);
    state(db);
    printf("\n5. and again with nothing refused: ");
    shown_c(sqlite3_column_name(st, 1));
    printf("; ");
    state(db);
    printf("\n  finalize %d\n", sqlite3_finalize(st));
  }
  free(text);
  printf("close %d\n", sqlite3_close(db));
  return 0;
}
