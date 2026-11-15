/* The library's compile options, read through sqlite3_compileoption_get,
 * so a difference in a PRAGMA's default between the two libraries can be
 * traced to the build. Never read from the sqlite3 command (AGENTS.md).
 *
 *   options DIR     DIR is unused; every probe takes one.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n",
            SQLITE_VERSION_NUMBER, SQLITE_SOURCE_ID,
            sqlite3_libversion_number(), sqlite3_sourceid());
    exit(2);
  }
  printf("libversion: %s\n", sqlite3_libversion());
  printf("sourceid: %s\n", sqlite3_sourceid());
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: options DIR\n"); return 2; }
  version_lines();
  printf("threadsafe: %d\n", sqlite3_threadsafe());
  for (int i = 0; ; i++) {
    const char *o = sqlite3_compileoption_get(i);
    if (o == NULL) break;
    printf("option: %s\n", o);
  }
  return 0;
}
