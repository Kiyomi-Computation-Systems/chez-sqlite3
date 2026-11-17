/* constants.c: holds a probe's numbers to sqlite3.h (M4's pre-work).
 *
 * Usage: scheme --program varargs.sps LIBRARY | ./constants
 *        scheme --program census.sps LIBRARY | ./constants
 *
 * Compiled against one header, it reads a probe's output on stdin and checks
 * every line of the form (constant NAME VALUE) against that header's value
 * of NAME, and every (unknown-op N) against SQLITE_DBCONFIG_MAX: an unknown
 * op must be above it. The probes write their numbers once, in the .sps,
 * and print each before they load anything, so every number they use passes
 * through here. This program holds names only; their values come from the
 * header.
 *
 * It prints one line per check and a summary, and exits 1 on any mismatch,
 * on a name it doesn't know, on a malformed line, or when it saw no
 * constant at all. */
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>

#define K(name) { #name, (long long)(name) }

static const struct { const char *name; long long value; } table[] = {
  K(SQLITE_OK),
  K(SQLITE_ERROR),
  K(SQLITE_BUSY),
  K(SQLITE_MISUSE),
  K(SQLITE_ROW),
  K(SQLITE_DONE),
  K(SQLITE_INTEGER),
  K(SQLITE_FLOAT),
  K(SQLITE_TEXT),
  K(SQLITE_BLOB),
  K(SQLITE_NULL),
  K(SQLITE_OPEN_READWRITE),
  K(SQLITE_OPEN_CREATE),
  K(SQLITE_DBCONFIG_LOOKASIDE),
  K(SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION),
  K(SQLITE_DBCONFIG_DEFENSIVE),
  K(SQLITE_DBCONFIG_DQS_DML),
  K(SQLITE_DBCONFIG_DQS_DDL),
  K(SQLITE_DBCONFIG_TRUSTED_SCHEMA),
  K(SQLITE_DBSTATUS_LOOKASIDE_USED),
  K(SQLITE_DBSTATUS_LOOKASIDE_HIT),
  K(SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE),
  K(SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL),
};
#define NTABLE ((int)(sizeof table / sizeof table[0]))

int main(void) {
  char line[1024];
  int checked = 0, faults = 0;
  printf("(header-version \"%s\")\n", SQLITE_VERSION);
  printf("(header-dbconfig-max %d)\n", SQLITE_DBCONFIG_MAX);
  while (fgets(line, sizeof line, stdin) != NULL) {
    char name[128];
    long long value;
    char close;
    if (strncmp(line, "(constant ", 10) == 0) {
      int i, found = -1;
      if (sscanf(line, "(constant %127s %lld%c", name, &value, &close) != 3 || close != ')') {
        printf("(malformed %s", line);
        faults++;
        continue;
      }
      for (i = 0; i < NTABLE; i++)
        if (strcmp(table[i].name, name) == 0) found = i;
      if (found < 0) {
        printf("(constant %s probe %lld header unknown-name FAULT)\n", name, value);
        faults++;
      } else if (table[found].value != value) {
        printf("(constant %s probe %lld header %lld FAULT)\n", name, value, table[found].value);
        faults++;
      } else {
        printf("(constant %s probe %lld header %lld ok)\n", name, value, table[found].value);
      }
      checked++;
    } else if (strncmp(line, "(unknown-op ", 12) == 0) {
      if (sscanf(line, "(unknown-op %lld%c", &value, &close) != 2 || close != ')') {
        printf("(malformed %s", line);
        faults++;
        continue;
      }
      if (value > SQLITE_DBCONFIG_MAX) {
        printf("(unknown-op %lld above-max %d ok)\n", value, SQLITE_DBCONFIG_MAX);
      } else {
        printf("(unknown-op %lld not-above-max %d FAULT)\n", value, SQLITE_DBCONFIG_MAX);
        faults++;
      }
      checked++;
    }
  }
  if (checked == 0) {
    puts("(no-constants-seen FAULT)");
    faults++;
  }
  printf("(constants-checked %d faults %d)\n", checked, faults);
  return faults == 0 ? 0 : 1;
}
