#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sqlite3.h>
static sqlite3 *a;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static void *interrupter(void *arg) { (void)arg; usleep(100000); sqlite3_interrupt(a); return 0; }
int main(int argc, char **argv) {
  sqlite3 *b; char *err = 0; pthread_t th; double t0, t1; int rc;
  printf("libversion %s\n", sqlite3_libversion());
  unlink(argv[1]);
  sqlite3_open(argv[1], &b); sqlite3_open(argv[1], &a);
  sqlite3_exec(b, "create table t(x); begin exclusive", 0, 0, 0);
  sqlite3_busy_timeout(a, 600);
  pthread_create(&th, 0, interrupter, 0);
  t0 = now(); rc = sqlite3_exec(a, "begin immediate", 0, 0, &err); t1 = now();
  pthread_join(th, 0);
  printf("lock wait: rc %d (%s) after %.0f ms, is_interrupted %d\n", rc, err ? err : "-", t1 - t0, sqlite3_is_interrupted(a));
  sqlite3_free(err); err = 0;
  sqlite3_exec(b, "rollback", 0, 0, 0);
  pthread_create(&th, 0, interrupter, 0);
  t0 = now();
  rc = sqlite3_exec(a, "with recursive c(n) as (select 1 union all select n+1 from c) select count(*) from c", 0, 0, &err);
  t1 = now(); pthread_join(th, 0);
  printf("long computation: rc %d (%s) after %.0f ms\n", rc, err ? err : "-", t1 - t0);
  sqlite3_free(err); sqlite3_close(a); sqlite3_close(b); unlink(argv[1]); return 0;
}
