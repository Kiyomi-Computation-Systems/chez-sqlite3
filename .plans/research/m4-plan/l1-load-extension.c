/* L1: sqlite3_load_extension, called as a v1 verb would call it (the M4
 * plan, sections 4.4 and 8).
 *
 *   l1-load-extension DIR TIMING
 *
 * DIR holds the shared objects run.sh built from ext.c and noentry.c, for
 * this library's header: ext.so, ext-named.so, libchezext.so,
 * ext-failing.so and noentry.so; and empty.so, an empty file, and dir.so, a
 * directory. The probe makes fifo.so itself. Every path it passes is
 * absolute, and every path it prints, in its lines or in SQLite's messages,
 * has DIR written as "DIR", so two machines' outputs compare. TIMING gets
 * every time it reads.
 *
 * Every connection is :memory:, opened as chez-sqlite3 opens one, and the C
 * call is turned on by db_config's ENABLE_LOAD_EXTENSION unless a case says
 * otherwise. Every call passes a pzErrMsg slot set to a sentinel address
 * first, so a slot SQLite left shows as "untouched", NULL as "NULL", and a
 * message as its text, then freed with sqlite3_free.
 *
 *   L1  the C call off (each library's start, read first)
 *   L2  the paths and entry points a caller can give
 *   L3  the connection's error state after a failed load
 *   L4  the same file loaded twice, and into a second connection
 *   L5  a connection opened on one thread, loaded on another
 *   L6  a FIFO as the path: whether the call blocks until a writer opens
 *       it (a helper thread opens it for writing after 500 ms)
 *   L7  SQL's load_extension() with the C call on
 *   L8  a load beside the connection's own statements: one held at a row,
 *       and a PERSISTENT one reset, read for re-prepares after each load
 *
 * No call with a side effect stands beside another in one argument list
 * (AGENTS.md).
 */
#include <sqlite3.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>

static const char *dir;
static FILE *timing;
static char sentinel_byte;
#define SENTINEL (&sentinel_byte)

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n", SQLITE_VERSION_NUMBER,
            SQLITE_SOURCE_ID, sqlite3_libversion_number(), sqlite3_sourceid());
    exit(2);
  }
  printf("libversion: %s\n", sqlite3_libversion());
  printf("sourceid: %s\n", sqlite3_sourceid());
  fprintf(timing, "libversion: %s\nsourceid: %s\n", sqlite3_libversion(), sqlite3_sourceid());
}

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

/* shown: TEXT with each occurrence of DIR written "DIR", into OUT. */
static void shown(const char *text, char *out, size_t n) {
  size_t d = strlen(dir), o = 0;
  while (*text && o + 4 < n) {
    if (strncmp(text, dir, d) == 0) {
      memcpy(out + o, "DIR", 3);
      o += 3;
      text += d;
    } else {
      out[o++] = *text++;
    }
  }
  out[o] = '\0';
}

static sqlite3 *open_memory(void) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open: %d\n", rc); exit(2); }
  return db;
}

static void c_call(sqlite3 *db, int onoff) {
  int cell = -5;
  int rc = sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, onoff, &cell);
  if (rc != SQLITE_OK || cell != onoff) {
    fprintf(stderr, "ENABLE_LOAD_EXTENSION %d: rc %d cell %d\n", onoff, rc, cell);
    exit(2);
  }
}

static void close_or_die(sqlite3 *db) {
  int c = sqlite3_close(db);
  if (c != SQLITE_OK) { fprintf(stderr, "close: %d\n", c); exit(2); }
}

/* run_text: SQL's first column of its first row as text, or its failure. */
static void run_text(sqlite3 *db, const char *sql, char *out, size_t n) {
  sqlite3_stmt *s = NULL;
  int p = sqlite3_prepare_v2(db, sql, -1, &s, NULL);
  if (p != SQLITE_OK) {
    char m[512];
    shown(sqlite3_errmsg(db), m, sizeof m);
    snprintf(out, n, "prepare %d \"%s\"", p, m);
    return;
  }
  int r = sqlite3_step(s);
  if (r == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(s, 0);
    snprintf(out, n, "row %s", t ? (const char *)t : "NULL");
  } else {
    char m[512];
    shown(sqlite3_errmsg(db), m, sizeof m);
    snprintf(out, n, "step %d \"%s\"", r, m);
  }
  sqlite3_finalize(s);
}

/* load_path: one call, as v1's verb would make it, of PATH as given. ENTRY
   may be NULL. Prints one line; answers the code. */
static int load_path(sqlite3 *db, const char *path, const char *entry, const char *label) {
  char *msg = SENTINEL;
  double t0 = now_ms();
  int rc = sqlite3_load_extension(db, path, entry, &msg);
  double t1 = now_ms();
  fprintf(timing, "L %s: %.3f ms\n", label, t1 - t0);
  char text[1024];
  if (msg == SENTINEL) {
    snprintf(text, sizeof text, "untouched");
  } else if (msg == NULL) {
    snprintf(text, sizeof text, "NULL");
  } else {
    char m[900];
    shown(msg, m, sizeof m);
    snprintf(text, sizeof text, "\"%s\"", m);
    sqlite3_free(msg);
  }
  char p[1024];
  shown(path, p, sizeof p);
  printf("  %-44s load(%s, %s) answered %d (extended %d); pzErrMsg %s\n", label, p,
         entry ? entry : "NULL", rc, sqlite3_extended_errcode(db), text);
  return rc;
}

/* load: load_path of FILE under DIR. */
static int load(sqlite3 *db, const char *file, const char *entry, const char *label) {
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", dir, file);
  return load_path(db, path, entry, label);
}

static void functions(sqlite3 *db, const char *label) {
  char a[600], b[600];
  run_text(db, "select chez_half(5)", a, sizeof a);
  run_text(db, "select chez_inits()", b, sizeof b);
  printf("  %-44s chez_half(5): %s; chez_inits(): %s\n", label, a, b);
}

/* --- L5 ------------------------------------------------------------------ */

struct other { sqlite3 *db; int rc; };

static void *load_elsewhere(void *arg) {
  struct other *o = arg;
  char path[4096];
  snprintf(path, sizeof path, "%s/ext.so", dir);
  char *msg = SENTINEL;
  o->rc = sqlite3_load_extension(o->db, path, NULL, &msg);
  if (msg != SENTINEL && msg != NULL) sqlite3_free(msg);
  return NULL;
}

/* --- L6 ------------------------------------------------------------------ */

static void *open_writer(void *arg) {
  const char *fifo = arg;
  struct timespec half = {0, 500000000};
  nanosleep(&half, NULL);
  int fd = open(fifo, O_WRONLY);
  if (fd >= 0) close(fd);
  return NULL;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: l1-load-extension DIR TIMING\n"); return 2; }
  dir = argv[1];
  timing = fopen(argv[2], "w");
  if (!timing) { perror(argv[2]); return 2; }
  version_lines();
  printf("constants: ENABLE_LOAD_EXTENSION %d, SQLITE_OK %d, SQLITE_ERROR %d\n",
         SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, SQLITE_OK, SQLITE_ERROR);

  printf("\nL1. The C call off\n");
  sqlite3 *db = open_memory();
  int start = -5;
  int rc = sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, -1, &start);
  printf("  the start: rc %d, ENABLE_LOAD_EXTENSION %d\n", rc, start);
  c_call(db, 0);
  load(db, "ext.so", NULL, "off: ext.so");
  functions(db, "after it");
  close_or_die(db);

  printf("\nL2. Paths and entry points, the C call on\n");
  db = open_memory();
  c_call(db, 1);
  load(db, "nosuch.so", NULL, "a path that doesn't exist");
  load(db, "noentry.so", NULL, "no entry point, NULL given");
  load(db, "noentry.so", "chez_nothing_init", "no entry point, one named");
  load(db, "empty.so", NULL, "an empty file");
  load(db, "dir.so", NULL, "a directory");
  load(db, "ext-failing.so", NULL, "an init that fails");
  functions(db, "after it");
  load(db, "ext-named.so", "no_such_init", "a named entry point it lacks");
  load(db, "ext-named.so", NULL, "ext-named.so, NULL given");
  load(db, "ext-named.so", "chez_named_init", "ext-named.so, its entry named");
  functions(db, "after it");
  close_or_die(db);

  db = open_memory();
  c_call(db, 1);
  load(db, "ext.so", NULL, "ext.so, NULL: sqlite3_extension_init");
  functions(db, "after it");
  close_or_die(db);

  db = open_memory();
  c_call(db, 1);
  load(db, "libchezext.so", NULL, "libchezext.so, NULL: the derived name");
  functions(db, "after it");
  close_or_die(db);

  db = open_memory();
  c_call(db, 1);
  load(db, "ext", NULL, "DIR/ext, no suffix");
  functions(db, "after it");
  close_or_die(db);

  if (chdir(dir) != 0) { perror("chdir"); return 2; }
  db = open_memory();
  c_call(db, 1);
  load_path(db, "ext.so", NULL, "ext.so, a bare name, cwd DIR");
  load_path(db, "./ext.so", NULL, "./ext.so, relative, cwd DIR");
  functions(db, "after it");
  close_or_die(db);

  printf("\nL3. The error state after a failed load\n");
  db = open_memory();
  c_call(db, 1);
  char ignored[64];
  run_text(db, "select 1", ignored, sizeof ignored);
  printf("  before: errcode %d, errmsg \"%s\"\n", sqlite3_errcode(db), sqlite3_errmsg(db));
  load(db, "nosuch.so", NULL, "a path that doesn't exist");
  printf("  after: errcode %d, extended %d, errmsg \"%s\"\n", sqlite3_errcode(db),
         sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  char path[4096];
  snprintf(path, sizeof path, "%s/nosuch.so", dir);
  rc = sqlite3_load_extension(db, path, NULL, NULL);
  printf("  with pzErrMsg NULL: answered %d, errmsg \"%s\"\n", rc, sqlite3_errmsg(db));
  close_or_die(db);

  printf("\nL4. The same file twice, and into a second connection\n");
  db = open_memory();
  c_call(db, 1);
  load(db, "ext.so", NULL, "first");
  load(db, "ext.so", NULL, "again, same connection");
  functions(db, "after it");
  sqlite3 *second = open_memory();
  c_call(second, 1);
  functions(second, "a second connection, before its load");
  load(second, "ext.so", NULL, "into the second connection");
  functions(second, "after it");
  close_or_die(second);
  close_or_die(db);
  db = open_memory();
  c_call(db, 1);
  load(db, "ext.so", NULL, "after both closed, a third connection");
  functions(db, "after it");
  close_or_die(db);

  printf("\nL5. Opened on the main thread, loaded on another\n");
  db = open_memory();
  c_call(db, 1);
  struct other o = {db, -1};
  pthread_t t;
  pthread_create(&t, NULL, load_elsewhere, &o);
  pthread_join(t, NULL);
  printf("  the other thread's load answered %d\n", o.rc);
  functions(db, "after it, on the main thread");
  close_or_die(db);

  printf("\nL6. A FIFO as the path\n");
  char fifo[4096];
  snprintf(fifo, sizeof fifo, "%s/fifo.so", dir);
  if (mkfifo(fifo, 0600) != 0 && errno != EEXIST) { perror("mkfifo"); return 2; }
  alarm(20);
  db = open_memory();
  c_call(db, 1);
  pthread_t w;
  pthread_create(&w, NULL, open_writer, fifo);
  double t0 = now_ms();
  load(db, "fifo.so", NULL, "a FIFO, a writer after 500 ms");
  double t1 = now_ms();
  pthread_join(w, NULL);
  alarm(0);
  printf("  the load returned %s the writer opened it\n",
         t1 - t0 >= 450.0 ? "after" : "before");
  fprintf(timing, "L6 the FIFO load: %.3f ms\n", t1 - t0);
  close_or_die(db);

  printf("\nL8. A load beside the connection's own statements\n");
  db = open_memory();
  c_call(db, 1);
  {
    sqlite3_stmt *cached = NULL, *held = NULL;
    if (sqlite3_prepare_v3(db, "select 1", -1, SQLITE_PREPARE_PERSISTENT, &cached, NULL)
        != SQLITE_OK) exit(2);
    int c1 = sqlite3_step(cached);
    int cz = sqlite3_reset(cached);
    if (sqlite3_prepare_v2(db, "select 2", -1, &held, NULL) != SQLITE_OK) exit(2);
    int h1 = sqlite3_step(held);
    printf("  a PERSISTENT select stepped %d and reset %d; another held at a row, %d\n", c1, cz, h1);
    load(db, "ext.so", NULL, "first load, beside the held row");
    load(db, "ext.so", NULL, "second load, beside the held row");
    functions(db, "after them");
    int before = sqlite3_stmt_status(cached, SQLITE_STMTSTATUS_REPREPARE, 0);
    int c2 = sqlite3_step(cached);
    int after = sqlite3_stmt_status(cached, SQLITE_STMTSTATUS_REPREPARE, 0);
    printf("  the PERSISTENT select's reprepares %d, its step %d, then %d\n", before, c2, after);
    sqlite3_reset(cached);
    int hf = sqlite3_finalize(held);
    load(db, "ext.so", NULL, "third load, nothing held");
    int before3 = sqlite3_stmt_status(cached, SQLITE_STMTSTATUS_REPREPARE, 0);
    int c3 = sqlite3_step(cached);
    int after3 = sqlite3_stmt_status(cached, SQLITE_STMTSTATUS_REPREPARE, 0);
    printf("  held finalized %d; the PERSISTENT select's reprepares %d, its step %d, then %d\n", hf,
           before3, c3, after3);
    sqlite3_finalize(cached);
  }
  close_or_die(db);

  printf("\nL7. SQL's load_extension(), the C call on\n");
  db = open_memory();
  c_call(db, 1);
  char sql[4200], out[700];
  snprintf(sql, sizeof sql, "select load_extension('%s/ext.so')", dir);
  run_text(db, sql, out, sizeof out);
  printf("  select load_extension('DIR/ext.so'): %s\n", out);
  close_or_die(db);
  fclose(timing);
  return 0;
}
