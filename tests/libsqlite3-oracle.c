/* tests/libsqlite3-oracle.c: what a libsqlite3 says about itself, read in C,
 * for the suites that check what chez-sqlite3 reports
 * (tests/libsqlite3-oracle.sls). chez-sqlite3 itself compiles no C
 * (ADR-0001).
 *
 *   libsqlite3-oracle PATH CODE ...
 *   libsqlite3-oracle --rows PATH HEX
 *   libsqlite3-oracle --transient
 *   libsqlite3-oracle --counters PATH HEX ...
 *
 * It dlopens PATH, exactly as given, and finds each function it calls with
 * dlsym on that handle alone, never RTLD_DEFAULT: it links no libsqlite3, so
 * no other copy of SQLite can answer. Each pointer has the type sqlite3.h
 * gives the function, through __typeof__, so the compile under -Werror holds
 * the calls to the header's prototypes. It prints, as Scheme data, one datum
 * per line:
 *
 *   (version . "3.53.1")                      sqlite3_libversion()
 *   (version-number . 3053001)                sqlite3_libversion_number()
 *   (source-id . "2026-...")                  sqlite3_sourceid()
 *   (threadsafe . 1)                          sqlite3_threadsafe()
 *   (compile-options "ATOMIC_INTRINSICS=1" ...)
 *                                             sqlite3_compileoption_get(N),
 *                                             from 0 to the first NULL
 *   (errstr (0 . "not an error") ...)         sqlite3_errstr(CODE), for each
 *                                             CODE given, in order
 *   (valgrind . yes)                          whether this process runs
 *                                             under Valgrind's memcheck:
 *                                             yes when /proc/self/maps maps
 *                                             vgpreload_memcheck, else no
 *                                             (as off Linux). Under make
 *                                             test-memory the suites require
 *                                             yes (ADR-0005, amended).
 *
 * A NULL string is #f.
 *
 * --rows takes SQL as HEX, its UTF-8 bytes two lowercase or uppercase hex
 * digits each, so no byte is lost on the way through a shell: it opens
 * :memory: on PATH, prepares the SQL with sqlite3_prepare_v3, its byte
 * length as nByte and prepFlags 0, steps it to SQLITE_DONE, and prints
 *
 *   (rows (COLUMN ...) ...)                   one list per row, each read
 *                                             in C, column by column
 *   (valgrind . yes)
 *
 * where each COLUMN is read by these calls, in this order: sqlite3_column_name,
 * _type, _int64, _double, _text, _bytes, _blob and _bytes again, so
 * sqlite3_column_bytes runs twice, once after each pointer, and the rest once:
 *
 *   (NAME TYPE BYTES INT64 BITS TEXT BLOB)
 *     NAME   sqlite3_column_name's bytes, up to its NUL, as #vu8(...)
 *     TYPE   sqlite3_column_type
 *     INT64  sqlite3_column_int64
 *     BITS   sqlite3_column_double's 64 bits, as an unsigned integer
 *     TEXT   sqlite3_column_text's bytes, BYTES of them, as #vu8(...)
 *     BYTES  sqlite3_column_bytes, the first call, read after sqlite3_column_text
 *     BLOB   sqlite3_column_blob's bytes, as many as the second call of
 *            sqlite3_column_bytes answers, read after sqlite3_column_blob
 *
 * --counters takes one or more statements, each as HEX as --rows takes its SQL,
 * and runs them in order on one :memory: database opened on PATH: each is
 * prepared with sqlite3_prepare_v3 (nByte its byte length, prepFlags 0),
 * stepped to SQLITE_DONE, whatever rows it makes, and finalized. After each it
 * reads the four counters, with the types sqlite3.h gives them, and prints
 *
 *   (counters (CHANGES TOTAL ROWID AUTOCOMMIT) ...)
 *                                             one list per statement
 *   (valgrind . yes)
 *
 * CHANGES is sqlite3_changes64, TOTAL sqlite3_total_changes64, ROWID
 * sqlite3_last_insert_rowid and AUTOCOMMIT sqlite3_get_autocommit, each read
 * once, in that order, after the statement's finalize. Both modes refuse a
 * statement with a tail: prepare's tail must be the end of the SQL.
 *
 * A NULL pointer is #f. --transient prints the header's SQLITE_TRANSIENT, as
 * (uintptr_t) reads it, then the valgrind line:
 *
 *   (transient . 18446744073709551615)
 *
 * It exits 0, or 1 with a message on stderr when PATH will not load, lacks a
 * function, a CODE is no integer, the HEX is no hex, a call of the --rows
 * mode answers other than it must, or a prepare leaves a tail. A missing
 * header or compiler fails the compile, and the suite with it: never a skip
 * (ADR-0001).
 */
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

/* put_quoted: "VALUE", with " and \ escaped, or #f for NULL. */
static void put_quoted(const char *value)
{
  const char *p;
  if (!value) {
    printf("#f");
    return;
  }
  putchar('"');
  for (p = value; *p; p++) {
    if (*p == '"' || *p == '\\')
      putchar('\\');
    putchar(*p);
  }
  putchar('"');
}

/* under_valgrind: 1 when /proc/self/maps maps memcheck's preload, else 0. */
static int under_valgrind(void)
{
  char line[4096];
  int found = 0;
  FILE *maps = fopen("/proc/self/maps", "r");
  if (!maps)
    return 0;
  while (!found && fgets(line, sizeof line, maps))
    found = strstr(line, "vgpreload_memcheck") != NULL;
  fclose(maps);
  return found;
}

/* find: NAME's address in LIBRARY, or exit 1 naming it. */
static void *find(void *library, const char *path, const char *name)
{
  void *address = dlsym(library, name);
  if (!address) {
    fprintf(stderr, "libsqlite3-oracle: %s has no %s\n", path, name);
    exit(1);
  }
  return address;
}

/* put_bytes: #vu8(B ...) for N bytes at P, or #f for NULL. */
static void put_bytes(const void *p, size_t n)
{
  const unsigned char *b = p;
  size_t i;
  if (!p) {
    printf("#f");
    return;
  }
  printf("#vu8(");
  for (i = 0; i < n; i++)
    printf(i ? " %u" : "%u", (unsigned)b[i]);
  putchar(')');
}

/* hex_digit: the value of hex digit C, or -1. */
static int hex_digit(int c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

/* fail: a message on stderr, and exit 1. */
static void fail(const char *what, int code)
{
  fprintf(stderr, "libsqlite3-oracle: %s answered %d\n", what, code);
  exit(1);
}

/* decode_hex: the bytes HEX spells, in a new NUL-terminated buffer, their count
 * in *LENGTH; NULL, with a message on stderr, when HEX is odd, no hex or too
 * big for memory. */
static char *decode_hex(const char *hex, size_t *length)
{
  size_t n = strlen(hex), i;
  char *bytes;
  if (n % 2 != 0) {
    fprintf(stderr, "libsqlite3-oracle: odd hex\n");
    return NULL;
  }
  bytes = malloc(n / 2 + 1);
  if (!bytes) {
    fprintf(stderr, "libsqlite3-oracle: out of memory\n");
    return NULL;
  }
  for (i = 0; i < n / 2; i++) {
    int hi = hex_digit(hex[2 * i]), lo = hex_digit(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) {
      fprintf(stderr, "libsqlite3-oracle: not hex: %s\n", hex);
      free(bytes);
      return NULL;
    }
    bytes[i] = (char)(hi * 16 + lo);
  }
  bytes[n / 2] = '\0';
  *length = n / 2;
  return bytes;
}

/* counters: the --counters mode, over the HEX statements in ARGV. */
static int counters(const char *path, char **argv, int count)
{
  void *library;
  __typeof__(sqlite3_open_v2) *open_v2;
  __typeof__(sqlite3_close) *close_db;
  __typeof__(sqlite3_prepare_v3) *prepare_v3;
  __typeof__(sqlite3_step) *step;
  __typeof__(sqlite3_finalize) *finalize;
  __typeof__(sqlite3_changes64) *changes64;
  __typeof__(sqlite3_total_changes64) *total_changes64;
  __typeof__(sqlite3_last_insert_rowid) *last_insert_rowid;
  __typeof__(sqlite3_get_autocommit) *get_autocommit;
  sqlite3 *db = NULL;
  char **sqls;
  size_t *lengths;
  int rc, i, j;

  /* Every statement is decoded before the open, so a bad one leaks nothing. */
  sqls = calloc((size_t)count + 1, sizeof *sqls);
  lengths = calloc((size_t)count + 1, sizeof *lengths);
  if (!sqls || !lengths) {
    fprintf(stderr, "libsqlite3-oracle: out of memory\n");
    free(sqls);
    free(lengths);
    return 1;
  }
  for (i = 0; i < count; i++) {
    sqls[i] = decode_hex(argv[i], &lengths[i]);
    if (!sqls[i]) {
      for (j = 0; j < i; j++)
        free(sqls[j]);
      free(sqls);
      free(lengths);
      return 1;
    }
  }

  library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "libsqlite3-oracle: %s\n", dlerror());
    for (j = 0; j < count; j++)
      free(sqls[j]);
    free(sqls);
    free(lengths);
    return 1;
  }
  *(void **)(&open_v2) = find(library, path, "sqlite3_open_v2");
  *(void **)(&close_db) = find(library, path, "sqlite3_close");
  *(void **)(&prepare_v3) = find(library, path, "sqlite3_prepare_v3");
  *(void **)(&step) = find(library, path, "sqlite3_step");
  *(void **)(&finalize) = find(library, path, "sqlite3_finalize");
  *(void **)(&changes64) = find(library, path, "sqlite3_changes64");
  *(void **)(&total_changes64) = find(library, path, "sqlite3_total_changes64");
  *(void **)(&last_insert_rowid) = find(library, path, "sqlite3_last_insert_rowid");
  *(void **)(&get_autocommit) = find(library, path, "sqlite3_get_autocommit");

  rc = open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  if (rc != SQLITE_OK)
    fail("sqlite3_open_v2", rc);
  printf("(counters");
  for (i = 0; i < count; i++) {
    char *sql = sqls[i];
    const char *tail = NULL;
    sqlite3_stmt *stmt = NULL;
    rc = prepare_v3(db, sql, (int)lengths[i], 0, &stmt, &tail);
    if (rc != SQLITE_OK || !stmt)
      fail("sqlite3_prepare_v3", rc);
    /* A tail would be SQL that never runs: refuse it. */
    if (tail != sql + lengths[i])
      fail("sqlite3_prepare_v3's tail, bytes short of the end,", (int)(sql + lengths[i] - tail));
    while ((rc = step(stmt)) == SQLITE_ROW)
      ;
    if (rc != SQLITE_DONE)
      fail("sqlite3_step", rc);
    rc = finalize(stmt);
    if (rc != SQLITE_OK)
      fail("sqlite3_finalize", rc);
    free(sql);
    sqls[i] = NULL;
    printf(" (%lld", (long long)changes64(db));
    printf(" %lld", (long long)total_changes64(db));
    printf(" %lld", (long long)last_insert_rowid(db));
    printf(" %d)", get_autocommit(db));
  }
  printf(")\n");
  rc = close_db(db);
  if (rc != SQLITE_OK)
    fail("sqlite3_close", rc);
  free(sqls);
  free(lengths);
  printf("(valgrind . %s)\n", under_valgrind() ? "yes" : "no");
  return 0;
}

/* rows: the --rows mode. */
static int rows(const char *path, const char *hex)
{
  void *library;
  __typeof__(sqlite3_open_v2) *open_v2;
  __typeof__(sqlite3_close) *close_db;
  __typeof__(sqlite3_prepare_v3) *prepare_v3;
  __typeof__(sqlite3_step) *step;
  __typeof__(sqlite3_finalize) *finalize;
  __typeof__(sqlite3_column_count) *column_count;
  __typeof__(sqlite3_column_name) *column_name;
  __typeof__(sqlite3_column_type) *column_type;
  __typeof__(sqlite3_column_int64) *column_int64;
  __typeof__(sqlite3_column_double) *column_double;
  __typeof__(sqlite3_column_text) *column_text;
  __typeof__(sqlite3_column_blob) *column_blob;
  __typeof__(sqlite3_column_bytes) *column_bytes;
  sqlite3 *db = NULL;
  sqlite3_stmt *stmt = NULL;
  const char *tail = NULL;
  char *sql;
  size_t n = strlen(hex), i;
  int rc, columns, c;

  if (n % 2 != 0) {
    fprintf(stderr, "libsqlite3-oracle: odd hex\n");
    return 1;
  }
  sql = malloc(n / 2 + 1);
  if (!sql) {
    fprintf(stderr, "libsqlite3-oracle: out of memory\n");
    return 1;
  }
  for (i = 0; i < n / 2; i++) {
    int hi = hex_digit(hex[2 * i]), lo = hex_digit(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) {
      fprintf(stderr, "libsqlite3-oracle: not hex: %s\n", hex);
      free(sql);
      return 1;
    }
    sql[i] = (char)(hi * 16 + lo);
  }
  sql[n / 2] = '\0';

  library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "libsqlite3-oracle: %s\n", dlerror());
    free(sql);
    return 1;
  }
  *(void **)(&open_v2) = find(library, path, "sqlite3_open_v2");
  *(void **)(&close_db) = find(library, path, "sqlite3_close");
  *(void **)(&prepare_v3) = find(library, path, "sqlite3_prepare_v3");
  *(void **)(&step) = find(library, path, "sqlite3_step");
  *(void **)(&finalize) = find(library, path, "sqlite3_finalize");
  *(void **)(&column_count) = find(library, path, "sqlite3_column_count");
  *(void **)(&column_name) = find(library, path, "sqlite3_column_name");
  *(void **)(&column_type) = find(library, path, "sqlite3_column_type");
  *(void **)(&column_int64) = find(library, path, "sqlite3_column_int64");
  *(void **)(&column_double) = find(library, path, "sqlite3_column_double");
  *(void **)(&column_text) = find(library, path, "sqlite3_column_text");
  *(void **)(&column_blob) = find(library, path, "sqlite3_column_blob");
  *(void **)(&column_bytes) = find(library, path, "sqlite3_column_bytes");

  rc = open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  if (rc != SQLITE_OK)
    fail("sqlite3_open_v2", rc);
  rc = prepare_v3(db, sql, (int)(n / 2), 0, &stmt, &tail);
  if (rc != SQLITE_OK || !stmt)
    fail("sqlite3_prepare_v3", rc);
  /* A tail would be SQL that never runs: refuse it. */
  if (tail != sql + n / 2)
    fail("sqlite3_prepare_v3's tail, bytes short of the end,", (int)(sql + n / 2 - tail));
  columns = column_count(stmt);
  printf("(rows");
  while ((rc = step(stmt)) == SQLITE_ROW) {
    printf(" (");
    for (c = 0; c < columns; c++) {
      const char *name = column_name(stmt, c);
      int type = column_type(stmt, c);
      sqlite3_int64 int64 = column_int64(stmt, c);
      double real = column_double(stmt, c);
      uint64_t bits;
      const unsigned char *text;
      const void *blob;
      int text_bytes, blob_bytes;
      memcpy(&bits, &real, sizeof bits);
      printf(c ? " (" : "(");
      put_bytes(name, name ? strlen(name) : 0);
      printf(" %d", type);
      text = column_text(stmt, c);
      text_bytes = column_bytes(stmt, c);
      printf(" %d %lld %" PRIu64 " ", text_bytes, (long long)int64, bits);
      put_bytes(text, (size_t)text_bytes);
      blob = column_blob(stmt, c);
      blob_bytes = column_bytes(stmt, c);
      putchar(' ');
      put_bytes(blob, (size_t)blob_bytes);
      putchar(')');
    }
    putchar(')');
  }
  printf(")\n");
  if (rc != SQLITE_DONE)
    fail("sqlite3_step", rc);
  rc = finalize(stmt);
  if (rc != SQLITE_OK)
    fail("sqlite3_finalize", rc);
  rc = close_db(db);
  if (rc != SQLITE_OK)
    fail("sqlite3_close", rc);
  free(sql);
  printf("(valgrind . %s)\n", under_valgrind() ? "yes" : "no");
  return 0;
}

int main(int argc, char **argv)
{
  void *library;
  __typeof__(sqlite3_libversion) *libversion;
  __typeof__(sqlite3_libversion_number) *libversion_number;
  __typeof__(sqlite3_sourceid) *sourceid;
  __typeof__(sqlite3_threadsafe) *threadsafe;
  __typeof__(sqlite3_compileoption_get) *compileoption_get;
  __typeof__(sqlite3_errstr) *errstr;
  const char *option;
  int i;

  if (argc == 2 && strcmp(argv[1], "--transient") == 0) {
    printf("(transient . %" PRIuPTR ")\n", (uintptr_t)SQLITE_TRANSIENT);
    printf("(valgrind . %s)\n", under_valgrind() ? "yes" : "no");
    return 0;
  }
  if (argc == 4 && strcmp(argv[1], "--rows") == 0)
    return rows(argv[2], argv[3]);
  if (argc >= 4 && strcmp(argv[1], "--counters") == 0)
    return counters(argv[2], argv + 3, argc - 3);
  if (argc < 2) {
    fprintf(stderr, "usage: libsqlite3-oracle PATH CODE ...\n");
    return 1;
  }
  library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "libsqlite3-oracle: %s\n", dlerror());
    return 1;
  }
  *(void **)(&libversion) = find(library, argv[1], "sqlite3_libversion");
  *(void **)(&libversion_number) = find(library, argv[1], "sqlite3_libversion_number");
  *(void **)(&sourceid) = find(library, argv[1], "sqlite3_sourceid");
  *(void **)(&threadsafe) = find(library, argv[1], "sqlite3_threadsafe");
  *(void **)(&compileoption_get) = find(library, argv[1], "sqlite3_compileoption_get");
  *(void **)(&errstr) = find(library, argv[1], "sqlite3_errstr");

  printf("(version . ");
  put_quoted(libversion());
  printf(")\n");
  printf("(version-number . %d)\n", libversion_number());
  printf("(source-id . ");
  put_quoted(sourceid());
  printf(")\n");
  printf("(threadsafe . %d)\n", threadsafe());
  printf("(compile-options");
  for (i = 0; (option = compileoption_get(i)) != NULL; i++) {
    putchar(' ');
    put_quoted(option);
  }
  printf(")\n");
  printf("(errstr");
  for (i = 2; i < argc; i++) {
    char *end;
    long code = strtol(argv[i], &end, 10);
    if (*argv[i] == '\0' || *end != '\0') {
      fprintf(stderr, "libsqlite3-oracle: not a code: %s\n", argv[i]);
      return 1;
    }
    printf(" (%ld . ", code);
    put_quoted(errstr((int)code));
    putchar(')');
  }
  printf(")\n");
  printf("(valgrind . %s)\n", under_valgrind() ? "yes" : "no");
  return 0;
}
