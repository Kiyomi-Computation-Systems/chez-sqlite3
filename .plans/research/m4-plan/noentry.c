/* noentry.c: a shared object with no entry point SQLite looks for (the M4
 * plan, section 8): one function, chez_nothing, that SQLite never calls. */
int chez_nothing(void);

int chez_nothing(void) {
  return 0;
}
