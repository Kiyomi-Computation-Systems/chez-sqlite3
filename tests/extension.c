/* tests/extension.c: the loadable SQLite extension the load-extension!
 * suites load, through tests/extension-build.sls only. chez-sqlite3 itself
 * compiles no C (ADR-0001): this is a test's subject, as
 * tests/decoy-libsqlite3.c is.
 *
 * The suites compile it at test time, once per variant below, with $CC
 * -Wall -Werror and -shared -fPIC, or -dynamiclib on a Mac, against the
 * lane's own sqlite3ext.h, the header beside sqlite3.h that C_INCLUDE_PATH
 * or the compiler's own path finds. A missing compiler or header fails the
 * compile, and the suite with it, never a skip (ADR-0001, decision 3). It
 * includes sqlite3ext.h, so it calls SQLite only through the routines the
 * loading library hands its entry point: it links no libsqlite3 of its own.
 *
 * Variants, chosen at compile time:
 *
 *   (none)        sqlite3_extension_init, the entry point SQLite tries first
 *                 when none is named: registers chez_half and chez_inits
 *   EXT_NAMED     chez_named_init alone, registering the same two: no entry
 *                 point SQLite's own search finds, in a file named
 *                 ext-named, whose derived name is sqlite3_extnamed_init
 *   EXT_DERIVED   sqlite3_chezext_init alone: the name SQLite derives from a
 *                 file named libchezext when none is named
 *   EXT_FAILING   sqlite3_extension_init that sets its message, by
 *                 sqlite3_mprintf, to "chez_failing refused", registers
 *                 nothing, and answers SQLITE_ERROR
 *
 * Its two functions:
 *
 *   chez_half(x)   x / 2.0: that the load took, on the connection it took on
 *   chez_inits()   how many times an init of this file has run in the
 *                  process since the file was loaded: every load runs the
 *                  init again, and a close of the last connection that
 *                  loaded it unloads the file, so the count starts again
 *                  (the M4 plan's research, L4)
 *
 * An init counts itself first, then registers both functions, answering the
 * first registration's failure: a load whose init replaces the functions an
 * earlier load registered fails while a statement of the connection is at a
 * row, SQLITE_BUSY from sqlite3_create_function, with no message of its own
 * (the research, L8 and rv1, part B).
 */
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1

/* inits: how many times an init of this file has run in the process. */
static int inits;

#ifndef EXT_FAILING
/* chez_half: its one argument, as a double, halved. */
static void chez_half(sqlite3_context *context, int argc, sqlite3_value **argv)
{
  (void)argc;
  sqlite3_result_double(context, sqlite3_value_double(argv[0]) / 2.0);
}

/* chez_inits: the count, as an integer. */
static void chez_inits(sqlite3_context *context, int argc, sqlite3_value **argv)
{
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, inits);
}

/* registered: the init's work, for every variant but the failing one: the
   count, then the two functions, each registration's code answered. */
static int registered(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
{
  int rc;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;
  inits++;
  rc = sqlite3_create_function(db, "chez_half", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0,
                               chez_half, 0, 0);
  if (rc != SQLITE_OK)
    return rc;
  return sqlite3_create_function(db, "chez_inits", 0, SQLITE_UTF8, 0, chez_inits, 0, 0);
}
#endif

#if defined(EXT_NAMED)
int chez_named_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
{
  return registered(db, pzErrMsg, pApi);
}
#elif defined(EXT_DERIVED)
int sqlite3_chezext_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
{
  return registered(db, pzErrMsg, pApi);
}
#elif defined(EXT_FAILING)
int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
{
  SQLITE_EXTENSION_INIT2(pApi);
  (void)db;
  inits++;
  *pzErrMsg = sqlite3_mprintf("chez_failing refused");
  return SQLITE_ERROR;
}
#else
int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
{
  return registered(db, pzErrMsg, pApi);
}
#endif
