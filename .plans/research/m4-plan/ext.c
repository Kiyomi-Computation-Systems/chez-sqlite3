/* ext.c: the smallest loadable extension a suite could compile at test time
 * (the M4 plan, sections 4.4 and 8). Built by run.sh, with $CC -shared -fPIC
 * against the header of the library it is loaded into, once per variant:
 *
 *   (none)         sqlite3_extension_init, the name SQLite tries first when
 *                  no entry point is given: registers chez_half(x), x / 2.0,
 *                  and chez_inits(), how many times any init of this file
 *                  has run in the process
 *   EXT_NAMED      chez_named_init alone, the same two functions
 *   EXT_DERIVED    sqlite3_chezext_init alone: the name SQLite derives from
 *                  a file named libchezext.so when no entry point is given
 *   EXT_FAILING    sqlite3_extension_init that sets *pzErrMsg, by
 *                  sqlite3_mprintf, to "chez_failing refused", and answers
 *                  SQLITE_ERROR
 *
 * It includes sqlite3ext.h, so it calls SQLite only through the routines
 * the loading library hands it: it links no libsqlite3 of its own.
 */
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1

static int inits;

#ifndef EXT_FAILING
static void chez_half(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  sqlite3_result_double(context, sqlite3_value_double(argv[0]) / 2.0);
}

static void chez_inits(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, inits);
}

static int registered(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;
  inits++;
  int rc = sqlite3_create_function(db, "chez_half", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0,
                                   chez_half, 0, 0);
  if (rc != SQLITE_OK) return rc;
  return sqlite3_create_function(db, "chez_inits", 0, SQLITE_UTF8, 0, chez_inits, 0, 0);
}
#endif

#if defined(EXT_NAMED)
int chez_named_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  return registered(db, pzErrMsg, pApi);
}
#elif defined(EXT_DERIVED)
int sqlite3_chezext_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  return registered(db, pzErrMsg, pApi);
}
#elif defined(EXT_FAILING)
int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  SQLITE_EXTENSION_INIT2(pApi);
  (void)db;
  inits++;
  *pzErrMsg = sqlite3_mprintf("chez_failing refused");
  return SQLITE_ERROR;
}
#else
int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  return registered(db, pzErrMsg, pApi);
}
#endif
