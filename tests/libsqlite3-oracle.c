/* tests/libsqlite3-oracle.c: what a libsqlite3 says about itself, read in C,
 * for the suites that check what chez-sqlite3 reports
 * (tests/libsqlite3-oracle.sls). chez-sqlite3 itself compiles no C
 * (ADR-0001).
 *
 *   libsqlite3-oracle PATH CODE ...
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
 * A NULL string is #f. It exits 0, or 1 with a message on stderr when PATH
 * will not load, lacks a function, or a CODE is no integer. A missing header
 * or compiler fails the compile, and the suite with it: never a skip
 * (ADR-0001).
 */
#include <dlfcn.h>
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
