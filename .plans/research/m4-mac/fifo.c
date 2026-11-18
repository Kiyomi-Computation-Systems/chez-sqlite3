/* fifo: what dlopen, and sqlite3_load_extension, do with a FIFO as the path,
 * each bounded, for the Mac (README.md). L6 of the M4 plan's
 * l1-load-extension.c asks whether the load waits for a writer; on the Mac's
 * first run its writer's one blocking open waited past the probe's 20 s
 * alarm, so either the load never opened the FIFO, or it opened it again
 * after the writer let go.
 *
 *   fifo DIR SUFFIX
 *
 * It makes DIR/fifo.SUFFIX, and DIR/dir.SUFFIX and DIR/empty.SUFFIX must be
 * there, as run-mac.sh makes them. Each case runs in a child process, which
 * makes one call and sends its answer back; this process is the writer, so
 * no thread of the caller's opens the FIFO. A case:
 *
 *   no writer       nothing opens the FIFO for 3000 ms;
 *   one writer      at 500 ms, the FIFO is opened for writing once, as soon
 *                   as a reader has it (polled every 10 ms, without
 *                   blocking, for 3000 ms), and closed at once; then
 *                   nothing more for 3000 ms.
 *
 * A call still running after that is released: the FIFO is opened for
 * writing and closed every 10 ms, for 3000 ms, counting the opens that found
 * a reader; a call still running then is killed. dlopen's flags are SQLite's
 * unix VFS's, RTLD_NOW | RTLD_GLOBAL. The load's connection is :memory:,
 * opened as chez-sqlite3 opens one, with the C call on. Every message has
 * DIR written "DIR". The directory and the empty file show dyld's own
 * reasons, which SQLite's message hides: it keeps only its retry's, with
 * the suffix appended.
 */
#include <sqlite3.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const char *dir;

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static void pause_ms(long ms) {
  struct timespec t = {ms / 1000, (ms % 1000) * 1000000L};
  nanosleep(&t, NULL);
}

/* shown: TEXT with each occurrence of DIR written "DIR", into OUT. */
static void shown(const char *text, char *out, size_t n) {
  size_t d = strlen(dir), o = 0;
  while (*text && o + 4 < n) {
    if (strncmp(text, dir, d) == 0) {
      memcpy(out + o, "DIR", 3);
      o += 3;
      text += d;
    } else {
      out[o++] = *text++;
    }
  }
  out[o] = '\0';
}

/* The child's call. Writes its answer, one line, to FD. */
static void call_dlopen(const char *path, int fd) {
  double t0 = now_ms();
  void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
  double t1 = now_ms();
  char m[2048], line[2300];
  if (h) {
    snprintf(line, sizeof line, "after %.0f ms: a handle", t1 - t0);
  } else {
    const char *e = dlerror();
    shown(e ? e : "(none)", m, sizeof m);
    snprintf(line, sizeof line, "after %.0f ms: NULL, dlerror \"%s\"", t1 - t0, m);
  }
  if (write(fd, line, strlen(line)) < 0) _exit(3);
}

static void call_load(const char *path, int fd) {
  sqlite3 *db = NULL;
  if (sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                      | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK)
    _exit(4);
  int cell = -5;
  if (sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 1, &cell) != SQLITE_OK
      || cell != 1)
    _exit(5);
  char *msg = NULL;
  double t0 = now_ms();
  int rc = sqlite3_load_extension(db, path, NULL, &msg);
  double t1 = now_ms();
  char m[2048], line[2300];
  shown(msg ? msg : "(NULL)", m, sizeof m);
  snprintf(line, sizeof line, "after %.0f ms: answered %d (extended %d), message \"%s\"",
           t1 - t0, rc, sqlite3_extended_errcode(db), m);
  if (msg) sqlite3_free(msg);
  if (write(fd, line, strlen(line)) < 0) _exit(3);
}

/* exited: whether PID has ended, reaped. */
static int exited(pid_t pid) {
  int st;
  return waitpid(pid, &st, WNOHANG) == pid;
}

/* wait_for: whether PID ends within MS, polled every 10 ms. */
static int wait_for(pid_t pid, long ms) {
  double end = now_ms() + ms;
  for (;;) {
    if (exited(pid)) return 1;
    if (now_ms() >= end) return 0;
    pause_ms(10);
  }
}

/* release_once: opens FIFO for writing as soon as a reader has it, within
   MS, unless PID ends first, and closes it at once. Whether it found one. */
static int release_once(const char *fifo, pid_t pid, long ms, int *ended) {
  double end = now_ms() + ms;
  for (;;) {
    int fd = open(fifo, O_WRONLY | O_NONBLOCK);
    if (fd >= 0) {
      close(fd);
      return 1;
    }
    if (exited(pid)) {
      *ended = 1;
      return 0;
    }
    if (now_ms() >= end) return 0;
    pause_ms(10);
  }
}

/* run: one case. CALL runs in a child on PATH; WRITER is 0 or 1. */
static void run(const char *label, void (*call)(const char *, int), const char *path,
                const char *fifo, int writer) {
  int p[2];
  if (pipe(p) != 0) { perror("pipe"); exit(2); }
  fflush(stdout);
  pid_t pid = fork();
  if (pid < 0) { perror("fork"); exit(2); }
  if (pid == 0) {
    close(p[0]);
    call(path, p[1]);
    _exit(0);
  }
  close(p[1]);
  char what[256] = "";
  int ended = 0;
  if (writer) {
    pause_ms(500);
    int found = release_once(fifo, pid, 3000, &ended);
    snprintf(what, sizeof what, "the writer at 500 ms %s; ",
             found ? "found a reader" : ended ? "found none: the call had returned"
                                              : "found no reader in 3000 ms");
  }
  if (!ended) ended = wait_for(pid, 3000);
  char after[256] = "";
  if (!ended) {
    int opens = 0;
    double end = now_ms() + 3000;
    while (!ended && now_ms() < end) {
      int fd = open(fifo, O_WRONLY | O_NONBLOCK);
      if (fd >= 0) {
        opens++;
        close(fd);
      }
      pause_ms(10);
      ended = exited(pid);
    }
    if (ended) {
      snprintf(after, sizeof after, "still in the call 3000 ms on; released, the opens that "
               "found a reader %d; it returned ", opens);
    } else {
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      snprintf(after, sizeof after, "still in the call 3000 ms on; released, the opens that "
               "found a reader %d; still in the call 3000 ms on: killed; ", opens);
    }
  }
  char answer[2400];
  size_t n = 0;
  for (;;) {
    ssize_t r = read(p[0], answer + n, sizeof answer - 1 - n);
    if (r <= 0) break;
    n += (size_t)r;
  }
  answer[n] = '\0';
  close(p[0]);
  printf("  %-36s %s%s%s\n", label, what, after, n > 0 ? answer : "(no answer)");
}

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  if (argc != 3) {
    fprintf(stderr, "usage: fifo DIR SUFFIX\n");
    return 2;
  }
  dir = argv[1];
  const char *suf = argv[2];
  char fifo[4096], dirpath[4096], empty[4096];
  snprintf(fifo, sizeof fifo, "%s/fifo.%s", dir, suf);
  snprintf(dirpath, sizeof dirpath, "%s/dir.%s", dir, suf);
  snprintf(empty, sizeof empty, "%s/empty.%s", dir, suf);
  unlink(fifo);
  if (mkfifo(fifo, 0600) != 0) { perror("mkfifo"); return 2; }
  printf("libversion: %s\n", sqlite3_libversion());
  printf("the FIFO: DIR/fifo.%s\n", suf);
  run("dlopen, no writer", call_dlopen, fifo, fifo, 0);
  run("dlopen, one writer", call_dlopen, fifo, fifo, 1);
  run("load, no writer", call_load, fifo, fifo, 0);
  run("load, one writer", call_load, fifo, fifo, 1);
  run("dlopen, a directory", call_dlopen, dirpath, fifo, 0);
  run("dlopen, an empty file", call_dlopen, empty, fifo, 0);
  unlink(fifo);
  return 0;
}
