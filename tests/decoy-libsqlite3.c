/* tests/decoy-libsqlite3.c: a stand-in libsqlite3, for
 * tests/test-library-loading.sps only. chez-sqlite3 itself compiles no C
 * (ADR-0001).
 *
 * The suite compiles this file at test time, once per build below, as a
 * shared object (-Wall -Werror -shared -fPIC), and points
 * CHEZ_SQLITE3_LIBRARY at it, so each refusal of the load can be watched
 * firing by name. It includes sqlite3.h, so every function it defines has
 * the header's own prototype: a definition that disagrees fails the compile,
 * and the suite with it, never a skip (ADR-0001).
 *
 * It states no version of its own. The suite passes the floor, read from
 * packaging/floors.sexp, and the version one below it (ADR-0008):
 *
 *   -DDECOY_VERSION_NUMBER=N -DDECOY_VERSION="T"
 *   -DDECOY_BELOW_NUMBER=N-1 -DDECOY_BELOW="T-1"
 *
 * Builds, chosen at compile time, since what a library exports is fixed
 * when it is linked and no switch read at run time can hide an entry point
 * from dlsym:
 *
 *   (none)                   the control: the 15 entry points
 *                            (chez-sqlite3 private native) binds
 *   DECOY_LACKS_<entry>      that one entry point left out
 *   DECOY_NOT_SQLITE         no sqlite3_* function at all
 *   DECOY_MARKER             also defines decoy_marker, which no other
 *                            build has: whether a process ever loaded this
 *                            build is foreign-entry?'s answer for it
 *
 * Behaviour, chosen at run time by CHEZ_SQLITE3_DECOY, read once, when the
 * library is loaded, and compared whole:
 *
 *   unset              the control: at the floor, threadsafe 2, and
 *                      sqlite3_initialize answers SQLITE_OK
 *   below-floor        the version one below the floor
 *   not-threadsafe     sqlite3_threadsafe answers 0
 *   libversion-null    sqlite3_libversion answers NULL
 *   sourceid-null      sqlite3_sourceid answers NULL
 *   sourceid-utf8      sqlite3_sourceid answers "décoy-λ€" in UTF-8: two-
 *                      and three-byte sequences, which only a UTF-8 reading
 *                      reports as written
 *   initialize-fails   sqlite3_initialize answers SQLITE_NOMEM
 *   initialize-misuse  sqlite3_initialize answers SQLITE_MISUSE, a second
 *                      code, so that no single value passes for "non-zero"
 *   anything else      the control's behaviour, an empty value included
 *
 * The call log. Loading the library writes its first entry, decoy(SWITCH):
 * decoy(control) when the variable is unset, decoy(?VALUE) for a value not
 * listed above. Then every sqlite3_* function appends one entry, its name
 * and its arguments, as it is called. decoy_calls() returns the log,
 * entries separated by one space. The suite asserts it whole, so the log
 * holds which switch the library read, the load's order, and that nothing
 * runs after a refusal.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

#if !defined(DECOY_VERSION_NUMBER) || !defined(DECOY_VERSION) || \
    !defined(DECOY_BELOW_NUMBER) || !defined(DECOY_BELOW)
#error "tests/test-library-loading.sps passes the floor and the version below it: -DDECOY_VERSION_NUMBER, -DDECOY_VERSION, -DDECOY_BELOW_NUMBER and -DDECOY_BELOW"
#endif

static char calls[4096];

/* called: appends one entry, printf-style, to the call log. */
static void called(const char *format, ...)
{
  size_t used = strlen(calls);
  va_list args;
  if (used > 0 && used + 1 < sizeof calls) {
    calls[used++] = ' ';
    calls[used] = '\0';
  }
  va_start(args, format);
  vsnprintf(calls + used, sizeof calls - used, format, args);
  va_end(args);
}

/* decoy_calls: the call log. Not an SQLite name, so a real libsqlite3
   lacks it. */
const char *decoy_calls(void)
{
  return calls;
}

#ifdef DECOY_MARKER
/* decoy_marker: present only in a build with DECOY_MARKER. */
int decoy_marker(void)
{
  return 1;
}
#endif

enum decoy_switch {
  CONTROL,
  BELOW_FLOOR,
  NOT_THREADSAFE,
  LIBVERSION_NULL,
  SOURCEID_NULL,
  SOURCEID_UTF8,
  INITIALIZE_FAILS,
  INITIALIZE_MISUSE
};

static const struct {
  const char *name;
  enum decoy_switch which;
} switches[] = {
  {"below-floor", BELOW_FLOOR},
  {"not-threadsafe", NOT_THREADSAFE},
  {"libversion-null", LIBVERSION_NULL},
  {"sourceid-null", SOURCEID_NULL},
  {"sourceid-utf8", SOURCEID_UTF8},
  {"initialize-fails", INITIALIZE_FAILS},
  {"initialize-misuse", INITIALIZE_MISUSE},
};

static enum decoy_switch mode = CONTROL;

/* decoy_load: reads CHEZ_SQLITE3_DECOY once, when the library is loaded,
   and logs what it read. */
__attribute__((constructor)) static void decoy_load(void)
{
  const char *value = getenv("CHEZ_SQLITE3_DECOY");
  size_t i;
  if (!value) {
    called("decoy(control)");
    return;
  }
  for (i = 0; i < sizeof switches / sizeof switches[0]; i++) {
    if (strcmp(value, switches[i].name) == 0) {
      mode = switches[i].which;
      called("decoy(%s)", value);
      return;
    }
  }
  called("decoy(?%s)", value);
}

#ifndef DECOY_NOT_SQLITE

/* --- the report's three ------------------------------------------------ */

#ifndef DECOY_LACKS_sqlite3_libversion_number
int sqlite3_libversion_number(void)
{
  called("sqlite3_libversion_number()");
  return mode == BELOW_FLOOR ? DECOY_BELOW_NUMBER : DECOY_VERSION_NUMBER;
}
#endif

#ifndef DECOY_LACKS_sqlite3_libversion
const char *sqlite3_libversion(void)
{
  called("sqlite3_libversion()");
  if (mode == LIBVERSION_NULL)
    return NULL;
  return mode == BELOW_FLOOR ? DECOY_BELOW : DECOY_VERSION;
}
#endif

#ifndef DECOY_LACKS_sqlite3_sourceid
const char *sqlite3_sourceid(void)
{
  called("sqlite3_sourceid()");
  if (mode == SOURCEID_NULL)
    return NULL;
  if (mode == SOURCEID_UTF8)
    return "d\xc3\xa9" "coy-\xce\xbb" "\xe2\x82\xac";
  return "decoy-sourceid";
}
#endif

/* --- threadsafe and initialize ----------------------------------------- */

#ifndef DECOY_LACKS_sqlite3_threadsafe
/* 2, not 1: the libraries measured here answer 1, so a load that never
   read the answer and took it for 1 shows. */
int sqlite3_threadsafe(void)
{
  called("sqlite3_threadsafe()");
  return mode == NOT_THREADSAFE ? 0 : 2;
}
#endif

#ifndef DECOY_LACKS_sqlite3_initialize
int sqlite3_initialize(void)
{
  called("sqlite3_initialize()");
  if (mode == INITIALIZE_FAILS)
    return SQLITE_NOMEM;
  return mode == INITIALIZE_MISUSE ? SQLITE_MISUSE : SQLITE_OK;
}
#endif

/* --- the rest: bound by the load and never called there ----------------
   Each logs its call, so a call during the load shows in a log the suite
   expects without it, and each answers as a library that can do nothing
   would. */

#ifndef DECOY_LACKS_sqlite3_compileoption_used
int sqlite3_compileoption_used(const char *zOptName)
{
  called("sqlite3_compileoption_used(%s)", zOptName ? zOptName : "NULL");
  return 0;
}
#endif

#ifndef DECOY_LACKS_sqlite3_compileoption_get
const char *sqlite3_compileoption_get(int N)
{
  called("sqlite3_compileoption_get(%d)", N);
  return NULL;
}
#endif

#ifndef DECOY_LACKS_sqlite3_open_v2
int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs)
{
  called("sqlite3_open_v2(%s,%s,%d,%s)", filename ? "filename" : "NULL",
         ppDb ? "ppDb" : "NULL", flags, zVfs ? "vfs" : "NULL");
  if (ppDb)
    *ppDb = NULL;
  return SQLITE_CANTOPEN;
}
#endif

#ifndef DECOY_LACKS_sqlite3_close
int sqlite3_close(sqlite3 *db)
{
  called("sqlite3_close(%s)", db ? "db" : "NULL");
  return SQLITE_OK;
}
#endif

#ifndef DECOY_LACKS_sqlite3_errmsg
const char *sqlite3_errmsg(sqlite3 *db)
{
  called("sqlite3_errmsg(%s)", db ? "db" : "NULL");
  return "decoy";
}
#endif

#ifndef DECOY_LACKS_sqlite3_errstr
const char *sqlite3_errstr(int rc)
{
  called("sqlite3_errstr(%d)", rc);
  return "decoy";
}
#endif

#ifndef DECOY_LACKS_sqlite3_errcode
int sqlite3_errcode(sqlite3 *db)
{
  called("sqlite3_errcode(%s)", db ? "db" : "NULL");
  return SQLITE_ERROR;
}
#endif

#ifndef DECOY_LACKS_sqlite3_extended_errcode
int sqlite3_extended_errcode(sqlite3 *db)
{
  called("sqlite3_extended_errcode(%s)", db ? "db" : "NULL");
  return SQLITE_ERROR;
}
#endif

#ifndef DECOY_LACKS_sqlite3_next_stmt
sqlite3_stmt *sqlite3_next_stmt(sqlite3 *pDb, sqlite3_stmt *pStmt)
{
  called("sqlite3_next_stmt(%s,%s)", pDb ? "db" : "NULL", pStmt ? "stmt" : "NULL");
  return NULL;
}
#endif

#ifndef DECOY_LACKS_sqlite3_memory_used
sqlite3_int64 sqlite3_memory_used(void)
{
  called("sqlite3_memory_used()");
  return 0;
}
#endif

#endif /* DECOY_NOT_SQLITE */
