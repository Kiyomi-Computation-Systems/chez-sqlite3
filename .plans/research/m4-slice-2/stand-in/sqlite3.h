/* Review stand-in for an SDK header that marks the load unavailable. */
#include_next <sqlite3.h>
SQLITE_API int sqlite3_load_extension(sqlite3 *db, const char *zFile, const char *zProc, char **pzErrMsg) __attribute__((unavailable("not available on macOS")));
