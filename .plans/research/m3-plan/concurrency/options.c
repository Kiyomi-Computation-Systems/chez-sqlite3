/* options.c: the library's version, source id, threading mode and every
 * compile option, read through the library itself (never the sqlite3
 * command). Refuses to run unless the runtime version and source id equal
 * the header's.
 *
 *   options            prints to stdout
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER ||
      strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, runtime %d %s\n",
            SQLITE_VERSION_NUMBER, SQLITE_SOURCE_ID,
            sqlite3_libversion_number(), sqlite3_sourceid());
    return 2;
  }
  printf("libversion %s\n", sqlite3_libversion());
  printf("sourceid %s\n", sqlite3_sourceid());
  printf("threadsafe %d\n", sqlite3_threadsafe());
  for (int i = 0;; i++) {
    const char *o = sqlite3_compileoption_get(i);
    if (o == NULL) {
      printf("compile options: %d\n", i);
      break;
    }
    printf("option %s\n", o);
  }
  /* The options this research's measurements depend on, by name. */
  const char *named[] = {"ENABLE_SETLK_TIMEOUT", "DEFAULT_FOREIGN_KEYS",
                         "OMIT_AUTORESET", "OMIT_WAL", "OMIT_PROGRESS_CALLBACK",
                         "ENABLE_API_ARMOR", "DEFAULT_WAL_SYNCHRONOUS",
                         "DEFAULT_JOURNAL_SIZE_LIMIT", "USE_URI", NULL};
  for (int i = 0; named[i]; i++)
    printf("used %s %d\n", named[i], sqlite3_compileoption_used(named[i]));
  return 0;
}
